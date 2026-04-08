# typed: false
# frozen_string_literal: true

require "securerandom"

module Mpp
  module Methods
    module Tempo
      module Session
        ClientChannel = Data.define(
          :channel_id, :chain_id, :escrow_contract, :payee, :currency,
          :authorized_signer, :deposit, :cumulative_amount, :opened
        )

        PreparedCredential = Data.define(:credential, :action, :channel)

        class ClientMethod
          attr_reader :name, :account, :authorized_signer, :channel, :decimals

          def initialize(account:, authorized_signer: nil, chain_id: nil, escrow_contract: nil,
            deposit: nil, decimals: 6, create_open_transaction: nil,
            create_top_up_transaction: nil, on_channel_update: nil)
            @name = "tempo"
            @account = account
            @authorized_signer = authorized_signer
            @chain_id = chain_id
            @escrow_contract = escrow_contract
            @deposit = deposit
            @decimals = decimals
            @create_open_transaction = create_open_transaction
            @create_top_up_transaction = create_top_up_transaction
            @on_channel_update = on_channel_update
            @channel = nil
          end

          def create_credential(challenge, context: nil)
            prepare_credential(challenge, context: context).credential
          end

          def prepare_credential(challenge, context: nil)
            raise ArgumentError, "No account configured for signing" unless @account
            raise ArgumentError, "Unsupported intent: #{challenge.intent}" unless challenge.intent == "session"

            ctx = normalize_context(context)
            action = ctx[:action] || default_action_for(challenge)

            case action
            when "open"
              build_open_credential(challenge, ctx)
            when "topUp"
              build_top_up_credential(challenge, ctx)
            when "voucher"
              build_voucher_credential(challenge, ctx)
            when "close"
              build_close_credential(challenge, ctx)
            else
              raise ArgumentError, "Unsupported session action: #{action}"
            end
          end

          def commit(prepared, receipt: nil)
            next_channel = prepared.channel
            if next_channel
              accepted_cumulative = receipt&.accepted_cumulative
              if accepted_cumulative
                next_channel = next_channel.with(
                  cumulative_amount: [next_channel.cumulative_amount, Integer(accepted_cumulative)].max
                )
              end
              @channel = next_channel
            elsif prepared.action == "close"
              @channel = nil
            end

            @on_channel_update&.call(@channel)
            @channel
          end

          def channel_id
            @channel&.channel_id
          end

          def cumulative_amount
            @channel&.cumulative_amount || 0
          end

          def opened?
            @channel&.opened || false
          end

          private

          def normalize_context(context)
            context ||= {}
            context.each_with_object({}) do |(key, value), acc|
              acc[key.to_sym] = value
            end
          end

          def default_action_for(challenge)
            @channel&.opened ? "voucher" : "open"
          end

          def build_open_credential(challenge, context)
            request = challenge.request
            chain_id = resolve_chain_id(request, context)
            escrow_contract = resolve_escrow_contract(request, chain_id, context)
            channel_id = (context[:channel_id] || request.dig("methodDetails", "channelId") || random_channel_id).to_s
            cumulative_amount = resolve_cumulative_amount(
              request_amount: Integer(request.fetch("amount")),
              context: context
            )
            deposit = resolve_deposit(request, context)
            transaction = context[:transaction] || build_open_transaction(
              challenge: challenge,
              channel_id: channel_id,
              chain_id: chain_id,
              escrow_contract: escrow_contract,
              cumulative_amount: cumulative_amount,
              deposit: deposit
            )

            raise ArgumentError, "transaction required for open action" unless transaction

            channel = ClientChannel.new(
              channel_id: channel_id,
              chain_id: chain_id,
              escrow_contract: escrow_contract,
              payee: request.fetch("recipient"),
              currency: request.fetch("currency"),
              authorized_signer: effective_authorized_signer,
              deposit: deposit,
              cumulative_amount: cumulative_amount,
              opened: true
            )

            payload = {
              "action" => "open",
              "type" => "transaction",
              "channelId" => channel_id,
              "transaction" => transaction,
              "authorizedSigner" => channel.authorized_signer,
              "cumulativeAmount" => cumulative_amount.to_s,
              "signature" => sign_voucher(
                escrow_contract: escrow_contract,
                chain_id: chain_id,
                channel_id: channel_id,
                cumulative_amount: cumulative_amount
              )
            }

            PreparedCredential.new(
              credential: build_credential(challenge, payload, chain_id),
              action: "open",
              channel: channel
            )
          end

          def build_top_up_credential(challenge, context)
            current = require_channel!(context)
            additional_deposit = resolve_additional_deposit(context)
            transaction = context[:transaction] || build_top_up_transaction(
              challenge: challenge,
              channel_id: current.channel_id,
              chain_id: current.chain_id,
              escrow_contract: current.escrow_contract,
              additional_deposit: additional_deposit
            )

            raise ArgumentError, "transaction required for topUp action" unless transaction

            channel = current.with(deposit: current.deposit + additional_deposit)
            payload = {
              "action" => "topUp",
              "type" => "transaction",
              "channelId" => current.channel_id,
              "transaction" => transaction,
              "additionalDeposit" => additional_deposit.to_s
            }

            PreparedCredential.new(
              credential: build_credential(challenge, payload, current.chain_id),
              action: "topUp",
              channel: channel
            )
          end

          def build_voucher_credential(challenge, context)
            request = challenge.request
            current = resolve_existing_channel(challenge, context)
            raise ArgumentError, "channel_id required for voucher action" unless current

            next_amount = resolve_cumulative_amount(
              request_amount: Integer(request.fetch("amount")),
              context: context,
              current_cumulative: current.cumulative_amount
            )

            payload = {
              "action" => "voucher",
              "channelId" => current.channel_id,
              "cumulativeAmount" => next_amount.to_s,
              "signature" => sign_voucher(
                escrow_contract: current.escrow_contract,
                chain_id: current.chain_id,
                channel_id: current.channel_id,
                cumulative_amount: next_amount
              )
            }

            PreparedCredential.new(
              credential: build_credential(challenge, payload, current.chain_id),
              action: "voucher",
              channel: current.with(cumulative_amount: next_amount, opened: true)
            )
          end

          def build_close_credential(challenge, context)
            current = require_channel!(context)
            close_amount = resolve_cumulative_amount(
              request_amount: 0,
              context: context,
              current_cumulative: current.cumulative_amount,
              default_to_current: true
            )

            payload = {
              "action" => "close",
              "channelId" => current.channel_id,
              "cumulativeAmount" => close_amount.to_s,
              "signature" => sign_voucher(
                escrow_contract: current.escrow_contract,
                chain_id: current.chain_id,
                channel_id: current.channel_id,
                cumulative_amount: close_amount
              )
            }

            PreparedCredential.new(
              credential: build_credential(challenge, payload, current.chain_id),
              action: "close",
              channel: nil
            )
          end

          def resolve_chain_id(request, context)
            raw = context[:chain_id] || request.dig("methodDetails", "chainId") || @chain_id || Defaults::CHAIN_ID
            Integer(raw)
          end

          def resolve_escrow_contract(request, chain_id, context)
            context[:escrow_contract] ||
              request.dig("methodDetails", "escrowContract") ||
              @escrow_contract ||
              Defaults.escrow_contract_for_chain(chain_id)
          end

          def resolve_deposit(request, context)
            raw = context[:deposit_raw] || request["suggestedDeposit"]
            return Integer(raw) if raw
            return Mpp::Units.parse_units(@deposit, @decimals) if @deposit

            raise ArgumentError,
              "No deposit amount available. Pass deposit:, deposit_raw:, or suggestedDeposit in the challenge."
          end

          def resolve_additional_deposit(context)
            raw = context[:additional_deposit_raw]
            return Integer(raw) if raw
            return Mpp::Units.parse_units(context[:additional_deposit], @decimals) if context[:additional_deposit]

            raise ArgumentError, "additional_deposit or additional_deposit_raw required for topUp action"
          end

          def resolve_cumulative_amount(request_amount:, context:, current_cumulative: nil, default_to_current: false)
            raw = context[:cumulative_amount_raw]
            return Integer(raw) if raw
            return Mpp::Units.parse_units(context[:cumulative_amount], @decimals) if context[:cumulative_amount]
            return current_cumulative if default_to_current && current_cumulative
            return current_cumulative + request_amount if current_cumulative

            request_amount
          end

          def resolve_existing_channel(challenge, context)
            if @channel && (!context[:channel_id] || context[:channel_id] == @channel.channel_id)
              return @channel
            end

            channel_id = context[:channel_id] || challenge.request.dig("methodDetails", "channelId")
            return nil unless channel_id

            ClientChannel.new(
              channel_id: channel_id.to_s,
              chain_id: resolve_chain_id(challenge.request, context),
              escrow_contract: resolve_escrow_contract(
                challenge.request,
                resolve_chain_id(challenge.request, context),
                context
              ),
              payee: challenge.request.fetch("recipient"),
              currency: challenge.request.fetch("currency"),
              authorized_signer: effective_authorized_signer,
              deposit: 0,
              cumulative_amount: 0,
              opened: true
            )
          end

          def require_channel!(context)
            current = @channel
            current = current.with(channel_id: context[:channel_id].to_s) if current && context[:channel_id]
            return current if current

            raise ArgumentError, "No open session channel is available"
          end

          def effective_authorized_signer
            @authorized_signer || @account.address
          end

          def build_open_transaction(**kwargs)
            return unless @create_open_transaction

            @create_open_transaction.call(**kwargs, account: @account, authorized_signer: effective_authorized_signer)
          end

          def build_top_up_transaction(**kwargs)
            return unless @create_top_up_transaction

            @create_top_up_transaction.call(**kwargs, account: @account, authorized_signer: effective_authorized_signer)
          end

          def build_credential(challenge, payload, chain_id)
            Mpp::Credential.new(
              challenge: challenge.to_echo,
              payload: payload,
              source: "did:pkh:eip155:#{chain_id}:#{@account.address}"
            )
          end

          def sign_voucher(escrow_contract:, chain_id:, channel_id:, cumulative_amount:)
            digest = Voucher.typed_data_hash(
              escrow_contract: escrow_contract,
              chain_id: chain_id,
              channel_id: channel_id,
              cumulative_amount: cumulative_amount
            )
            "0x#{@account.sign_hash(digest).unpack1("H*")}"
          end

          def random_channel_id
            "0x#{SecureRandom.hex(32)}"
          end
        end
      end
    end
  end
end
