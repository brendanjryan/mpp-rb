# typed: false
# frozen_string_literal: true

require "time"
require_relative "types"

module Mpp
  module Methods
    module Tempo
      module Session
        # Server-side session intent for payment channel verification.
        #
        # Handles the full channel lifecycle: open, topUp, voucher, close.
        # Each incoming request carries a session credential with a cumulative
        # voucher that the server validates and records.
        class SessionIntent
          attr_reader :name

          def initialize(
            rpc_url: nil, store: nil, min_voucher_delta: 0,
            channel_state_ttl: 5000, wait_for_confirmation: true,
            escrow_contract: nil, chain_id: nil
          )
            @name = "session"
            @rpc_url = rpc_url || (chain_id ? Defaults.rpc_url_for_chain(chain_id) : nil)
            @store = store || MemoryChannelStore.new
            @min_voucher_delta = min_voucher_delta
            @channel_state_ttl = channel_state_ttl
            @wait_for_confirmation = wait_for_confirmation
            @escrow_contract = escrow_contract
            @chain_id = chain_id
            @last_on_chain_verified = {}
          end

          attr_reader :store

          def verify(credential, request)
            payload = credential.payload
            unless payload.is_a?(Hash) && payload.key?("action")
              raise Mpp::BadRequestError.new(reason: "missing action in session credential")
            end

            action = payload["action"]
            unless Session::ACTIONS.include?(action)
              raise Mpp::BadRequestError.new(reason: "unknown action: #{action}")
            end

            challenge = credential.challenge
            method_details = extract_method_details(challenge, request)

            case action
            when "open"
              receipt = handle_open(challenge, payload, method_details)
              @last_on_chain_verified[payload["channelId"]] = monotonic_now
              receipt
            when "topUp"
              receipt = handle_top_up(challenge, payload, method_details)
              @last_on_chain_verified[payload["channelId"]] = monotonic_now
              receipt
            when "voucher"
              handle_voucher(challenge, payload, method_details)
            when "close"
              handle_close(challenge, payload, method_details)
            end
          end

          private

          def get_rpc_url(method_details = nil)
            url = @rpc_url
            if url.nil? && method_details && method_details[:chain_id]
              url = Defaults.rpc_url_for_chain(method_details[:chain_id])
            end
            raise Mpp::VerificationError, "No rpc_url configured on SessionIntent" unless url
            url
          end

          def get_escrow_contract(method_details)
            contract = method_details[:escrow_contract] || @escrow_contract
            if contract.nil? && method_details[:chain_id]
              contract = Defaults.escrow_contract_for_chain(method_details[:chain_id])
            end
            raise Mpp::VerificationError, "No escrow_contract configured" unless contract
            contract
          end

          def extract_method_details(challenge, request)
            md = request["methodDetails"] || {}
            chain_id = md["chainId"] || @chain_id || Defaults::CHAIN_ID
            escrow = md["escrowContract"] || @escrow_contract
            escrow ||= Defaults::ESCROW_CONTRACTS[chain_id]

            {
              chain_id: chain_id,
              escrow_contract: escrow,
              min_voucher_delta: md["minVoucherDelta"] ? Integer(md["minVoucherDelta"]) : @min_voucher_delta
            }
          end

          # --- Action Handlers ---

          def handle_open(challenge, payload, method_details)
            channel_id = payload["channelId"]
            rpc_url = get_rpc_url(method_details)
            escrow = get_escrow_contract(method_details)

            recipient = challenge.request["recipient"] || challenge.request[:recipient]
            currency = challenge.request["currency"] || challenge.request[:currency]
            amount = challenge.request["amount"] || challenge.request[:amount]
            amount = amount ? Integer(amount) : nil

            voucher = Voucher.parse_from_payload(
              channel_id: channel_id,
              cumulative_amount: payload["cumulativeAmount"],
              signature: payload["signature"]
            )

            # Broadcast the open transaction
            result = Chain.broadcast_open_transaction(
              rpc_url: rpc_url,
              transaction: payload["transaction"],
              escrow_contract: escrow,
              channel_id: channel_id,
              recipient: recipient,
              currency: currency,
              wait: @wait_for_confirmation
            )

            on_chain = result[:on_chain]
            tx_hash = result[:tx_hash]

            validate_on_chain_channel(on_chain, recipient, currency, amount)

            authorized_signer = if on_chain[:authorized_signer] == ZERO_ADDRESS
              on_chain[:payer]
            else
              on_chain[:authorized_signer]
            end

            # Verify voucher amount bounds
            if voucher[:cumulative_amount] > on_chain[:deposit]
              raise Mpp::AmountExceedsDepositError.new(reason: "voucher amount exceeds on-chain deposit")
            end

            if voucher[:cumulative_amount] <= on_chain[:settled]
              raise Mpp::VerificationFailedError.new(
                reason: "voucher cumulativeAmount is below on-chain settled amount"
              )
            end

            # Verify voucher signature
            verify_voucher_signature(escrow, method_details[:chain_id], voucher, authorized_signer)

            # Create or update channel in store
            updated = @store.update_channel(channel_id) do |existing|
              if existing
                settled = [on_chain[:settled], existing.settled_on_chain].max
                spent = [settled, existing.spent].max

                if voucher[:cumulative_amount] > existing.highest_voucher_amount
                  existing.with(
                    deposit: on_chain[:deposit],
                    settled_on_chain: settled,
                    spent: spent,
                    highest_voucher_amount: voucher[:cumulative_amount],
                    highest_voucher: voucher,
                    authorized_signer: authorized_signer
                  )
                else
                  existing.with(
                    deposit: on_chain[:deposit],
                    settled_on_chain: settled,
                    spent: spent,
                    authorized_signer: authorized_signer
                  )
                end
              else
                ChannelState.new(
                  channel_id: channel_id,
                  chain_id: method_details[:chain_id],
                  escrow_contract: escrow,
                  close_requested_at: on_chain[:close_requested_at],
                  payer: on_chain[:payer],
                  payee: on_chain[:payee],
                  token: on_chain[:token],
                  authorized_signer: authorized_signer,
                  deposit: on_chain[:deposit],
                  settled_on_chain: on_chain[:settled],
                  highest_voucher_amount: voucher[:cumulative_amount],
                  highest_voucher: voucher,
                  spent: on_chain[:settled],
                  units: 0,
                  finalized: false
                )
              end
            end

            raise Mpp::VerificationFailedError.new(reason: "failed to create channel") unless updated

            SessionReceipt.create(
              challenge_id: challenge.id,
              channel_id: channel_id,
              accepted_cumulative: updated.highest_voucher_amount,
              spent: updated.spent,
              units: updated.units,
              tx_hash: tx_hash
            )
          end

          def handle_top_up(challenge, payload, method_details)
            channel_id = payload["channelId"]
            channel = @store.get_channel(channel_id)
            raise Mpp::ChannelNotFoundError.new(reason: "channel not found") unless channel

            rpc_url = get_rpc_url(method_details)
            escrow = get_escrow_contract(method_details)
            declared_deposit = Integer(payload["additionalDeposit"])
            currency = challenge.request["currency"] || challenge.request[:currency]

            result = Chain.broadcast_top_up_transaction(
              rpc_url: rpc_url,
              transaction: payload["transaction"],
              escrow_contract: escrow,
              channel_id: channel_id,
              declared_deposit: declared_deposit,
              previous_deposit: channel.deposit,
              currency: currency
            )

            updated = @store.update_channel(channel_id) do |current|
              raise Mpp::ChannelNotFoundError.new(reason: "channel not found") unless current
              current.with(deposit: result[:new_deposit])
            end

            SessionReceipt.create(
              challenge_id: challenge.id,
              channel_id: channel_id,
              accepted_cumulative: (updated || channel).highest_voucher_amount,
              spent: (updated || channel).spent,
              units: (updated || channel).units
            )
          end

          def handle_voucher(challenge, payload, method_details)
            channel_id = payload["channelId"]
            channel = @store.get_channel(channel_id)
            raise Mpp::ChannelNotFoundError.new(reason: "channel not found") unless channel
            raise Mpp::ChannelClosedError.new(reason: "channel is finalized") if channel.finalized

            voucher = Voucher.parse_from_payload(
              channel_id: channel_id,
              cumulative_amount: payload["cumulativeAmount"],
              signature: payload["signature"]
            )

            escrow = get_escrow_contract(method_details)

            # Use cached channel state unless stale (avoid RPC per voucher)
            last_verified = @last_on_chain_verified[channel_id] || 0
            is_stale = (monotonic_now - last_verified) > @channel_state_ttl

            on_chain = if is_stale
              rpc_url = get_rpc_url(method_details)
              on_chain_data = Chain.get_on_chain_channel(rpc_url, escrow, channel_id)
              @last_on_chain_verified[channel_id] = monotonic_now

              # Persist closeRequestedAt so cached path detects force-close
              if on_chain_data[:close_requested_at] != 0
                @store.update_channel(channel_id) do |current|
                  current&.with(close_requested_at: on_chain_data[:close_requested_at])
                end
              end

              on_chain_data
            else
              {
                finalized: channel.finalized,
                close_requested_at: channel.close_requested_at,
                payer: channel.payer,
                payee: channel.payee,
                token: channel.token,
                authorized_signer: channel.authorized_signer,
                deposit: channel.deposit,
                settled: channel.settled_on_chain
              }
            end

            verify_and_accept_voucher(
              channel: channel,
              channel_id: channel_id,
              voucher: voucher,
              on_chain: on_chain,
              method_details: method_details,
              escrow: escrow,
              challenge: challenge
            )
          end

          def handle_close(challenge, payload, method_details)
            channel_id = payload["channelId"]
            channel = @store.get_channel(channel_id)
            raise Mpp::ChannelNotFoundError.new(reason: "channel not found") unless channel
            raise Mpp::ChannelClosedError.new(reason: "channel is already finalized") if channel.finalized

            voucher = Voucher.parse_from_payload(
              channel_id: channel_id,
              cumulative_amount: payload["cumulativeAmount"],
              signature: payload["signature"]
            )

            rpc_url = get_rpc_url(method_details)
            escrow = get_escrow_contract(method_details)
            on_chain = Chain.get_on_chain_channel(rpc_url, escrow, channel_id)

            if on_chain[:finalized]
              raise Mpp::ChannelClosedError.new(reason: "channel is finalized on-chain")
            end

            min_close_amount = [channel.spent, on_chain[:settled]].max
            if voucher[:cumulative_amount] < min_close_amount
              raise Mpp::VerificationFailedError.new(
                reason: "close voucher amount must be >= #{min_close_amount} (max of spent and on-chain settled)"
              )
            end

            if voucher[:cumulative_amount] > on_chain[:deposit]
              raise Mpp::AmountExceedsDepositError.new(
                reason: "close voucher amount exceeds on-chain deposit"
              )
            end

            verify_voucher_signature(escrow, method_details[:chain_id], voucher, channel.authorized_signer)

            tx_hash = Chain.close_on_chain(
              rpc_url: rpc_url,
              escrow_contract: escrow,
              channel_id: channel_id,
              cumulative_amount: voucher[:cumulative_amount],
              signature: voucher[:signature]
            )

            updated = @store.update_channel(channel_id) do |current|
              next nil unless current
              attrs = {deposit: on_chain[:deposit], finalized: true}
              if voucher[:cumulative_amount] > current.highest_voucher_amount
                attrs[:highest_voucher_amount] = voucher[:cumulative_amount]
                attrs[:highest_voucher] = voucher
              end
              current.with(**attrs)
            end

            SessionReceipt.create(
              challenge_id: challenge.id,
              channel_id: channel_id,
              accepted_cumulative: voucher[:cumulative_amount],
              spent: (updated || channel).spent,
              units: (updated || channel).units,
              tx_hash: tx_hash
            )
          end

          # --- Shared verification logic ---

          def verify_and_accept_voucher(channel:, channel_id:, voucher:, on_chain:, method_details:, escrow:, challenge:)
            if on_chain[:finalized]
              raise Mpp::ChannelClosedError.new(reason: "channel is finalized on-chain")
            end
            if on_chain[:close_requested_at] != 0
              raise Mpp::ChannelClosedError.new(reason: "channel has a pending close request")
            end

            if voucher[:cumulative_amount] <= on_chain[:settled]
              raise Mpp::VerificationFailedError.new(
                reason: "voucher cumulativeAmount is below on-chain settled amount"
              )
            end

            if voucher[:cumulative_amount] > on_chain[:deposit]
              raise Mpp::AmountExceedsDepositError.new(
                reason: "voucher amount exceeds on-chain deposit"
              )
            end

            if voucher[:cumulative_amount] < channel.highest_voucher_amount
              raise Mpp::VerificationFailedError.new(
                reason: "voucher cumulativeAmount must be strictly greater than highest accepted voucher"
              )
            end

            verify_voucher_signature(escrow, method_details[:chain_id], voucher, channel.authorized_signer)

            # Idempotent replay: equal cumulative voucher accepted without advancing state
            if voucher[:cumulative_amount] == channel.highest_voucher_amount
              return SessionReceipt.create(
                challenge_id: challenge.id,
                channel_id: channel_id,
                accepted_cumulative: channel.highest_voucher_amount,
                spent: channel.spent,
                units: channel.units
              )
            end

            min_delta = method_details[:min_voucher_delta] || @min_voucher_delta
            delta = voucher[:cumulative_amount] - channel.highest_voucher_amount
            if delta < min_delta
              raise Mpp::DeltaTooSmallError.new(
                reason: "voucher delta #{delta} below minimum #{min_delta}"
              )
            end

            updated = @store.update_channel(channel_id) do |current|
              raise Mpp::ChannelNotFoundError.new(reason: "channel not found") unless current
              if voucher[:cumulative_amount] > current.highest_voucher_amount
                current.with(
                  deposit: on_chain[:deposit],
                  highest_voucher_amount: voucher[:cumulative_amount],
                  highest_voucher: voucher
                )
              else
                current
              end
            end

            raise Mpp::ChannelNotFoundError.new(reason: "channel not found") unless updated

            SessionReceipt.create(
              challenge_id: challenge.id,
              channel_id: channel_id,
              accepted_cumulative: updated.highest_voucher_amount,
              spent: updated.spent,
              units: updated.units
            )
          end

          def verify_voucher_signature(escrow, chain_id, voucher, expected_signer)
            valid = Voucher.verify(
              escrow_contract: escrow,
              chain_id: chain_id,
              voucher: voucher,
              expected_signer: expected_signer
            )
            unless valid
              raise Mpp::InvalidSignatureError.new(reason: "invalid voucher signature")
            end
          end

          def validate_on_chain_channel(on_chain, recipient, currency, amount = nil)
            if on_chain[:deposit] == 0
              raise Mpp::ChannelNotFoundError.new(reason: "channel not funded on-chain")
            end
            if on_chain[:finalized]
              raise Mpp::ChannelClosedError.new(reason: "channel is finalized on-chain")
            end
            if on_chain[:close_requested_at] != 0
              raise Mpp::ChannelClosedError.new(reason: "channel has a pending close request")
            end
            if on_chain[:payee].downcase != recipient.downcase
              raise Mpp::VerificationFailedError.new(
                reason: "on-chain payee does not match server destination"
              )
            end
            if on_chain[:token].downcase != currency.downcase
              raise Mpp::VerificationFailedError.new(
                reason: "on-chain token does not match server token"
              )
            end
            if amount && (on_chain[:deposit] - on_chain[:settled]) < amount
              raise Mpp::InsufficientBalanceError.new(
                reason: "channel available balance insufficient for requested amount"
              )
            end
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          end
        end
      end
    end
  end
end
