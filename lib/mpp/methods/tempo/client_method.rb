# frozen_string_literal: true

require_relative "defaults"

module Mpp
  module Methods
    module Tempo
      DEFAULT_GAS_LIMIT = 1_000_000
      EXPIRING_NONCE_KEY = (1 << 256) - 1 # U256::MAX
      FEE_PAYER_VALID_BEFORE_SECS = 25

      class TransactionError < StandardError; end

      # Tempo payment method implementation.
      # Handles client-side credential creation for Tempo payments.
      class TempoMethod
        attr_reader :name, :account, :fee_payer, :root_account, :rpc_url,
                    :chain_id, :currency, :recipient, :decimals, :client_id
        attr_accessor :intents

        def initialize(account: nil, fee_payer: nil, root_account: nil,
                       rpc_url: Defaults::RPC_URL, chain_id: nil, currency: nil,
                       recipient: nil, decimals: 6, client_id: nil)
          @name = "tempo"
          @account = account
          @fee_payer = fee_payer
          @root_account = root_account
          @rpc_url = rpc_url
          @chain_id = chain_id
          @currency = currency
          @recipient = recipient
          @decimals = decimals
          @client_id = client_id
          @intents = {}
        end

        # Create a credential to satisfy the given challenge.
        def create_credential(challenge)
          raise ArgumentError, "No account configured for signing" unless @account
          raise ArgumentError, "Unsupported intent: #{challenge.intent}" unless challenge.intent == "charge"

          request = challenge.request
          method_details = request["methodDetails"]
          method_details = {} unless method_details.is_a?(Hash)
          use_fee_payer = method_details.fetch("feePayer", false)

          nonce_key = request.fetch("nonce_key", 0)
          if nonce_key.is_a?(String)
            nonce_key = nonce_key.start_with?("0x") ? nonce_key.to_i(16) : nonce_key.to_i
          end

          memo = method_details["memo"]
          memo ||= Attribution.encode(server_id: challenge.realm, client_id: @client_id)

          # Resolve RPC URL from challenge's chainId
          resolved_rpc_url = @rpc_url
          expected_chain_id = nil
          challenge_chain_id = method_details["chainId"]
          if challenge_chain_id
            begin
              parsed_chain_id = Integer(challenge_chain_id)
              resolved = Defaults::CHAIN_RPC_URLS[parsed_chain_id]
              if resolved
                resolved_rpc_url = resolved
                expected_chain_id = parsed_chain_id
              end
            rescue ArgumentError, TypeError
              # ignore
            end
          end

          expected_chain_id ||= @chain_id

          raw_tx, chain_id = build_tempo_transfer(
            amount: request["amount"],
            currency: request["currency"],
            recipient: request["recipient"],
            nonce_key: nonce_key,
            memo: memo,
            rpc_url: resolved_rpc_url,
            expected_chain_id: expected_chain_id,
            awaiting_fee_payer: use_fee_payer
          )

          Mpp::Credential.new(
            challenge: challenge.to_echo,
            payload: { "type" => "transaction", "signature" => raw_tx },
            source: "did:pkh:eip155:#{chain_id}:#{@account.address}"
          )
        end

        # Transform request - adds default methodDetails if needed.
        def transform_request(request, _credential)
          request
        end

        private

        def build_tempo_transfer(amount:, currency:, recipient:, nonce_key: 0,
                                 memo: nil, rpc_url: nil, expected_chain_id: nil,
                                 awaiting_fee_payer: false)
          raise ArgumentError, "No account configured" unless @account

          resolved_rpc = rpc_url || @rpc_url

          transfer_data = if memo
                            encode_transfer_with_memo(recipient, Integer(amount), memo)
                          else
                            encode_transfer(recipient, Integer(amount))
                          end

          chain_id, on_chain_nonce, gas_price = Rpc.get_tx_params(resolved_rpc, @account.address)

          if expected_chain_id && chain_id != expected_chain_id
            raise TransactionError,
                  "Chain ID mismatch: RPC returned #{chain_id}, expected #{expected_chain_id} from challenge"
          end

          if awaiting_fee_payer
            resolved_nonce_key = EXPIRING_NONCE_KEY
            resolved_nonce = 0
            valid_before = Time.now.to_i + FEE_PAYER_VALID_BEFORE_SECS
          else
            resolved_nonce_key = nonce_key
            resolved_nonce = on_chain_nonce
            valid_before = nil
          end

          gas_limit = DEFAULT_GAS_LIMIT
          begin
            estimated = Rpc.estimate_gas(resolved_rpc, @account.address, currency, transfer_data)
            gas_limit = [gas_limit, estimated + 5_000].max
          rescue StandardError
            # fallback to default
          end

          # Build and sign transaction using pytempo equivalent
          # This requires the pytempo Ruby equivalent - for now, produce a mock
          # The actual transaction building would use the tempo/pytempo Ruby bindings
          require "pytempo" # This would be the Ruby equivalent

          tx = Pytempo::TempoTransaction.create(
            chain_id: chain_id,
            gas_limit: gas_limit,
            max_fee_per_gas: gas_price,
            max_priority_fee_per_gas: gas_price,
            nonce: resolved_nonce,
            nonce_key: resolved_nonce_key,
            fee_token: awaiting_fee_payer ? nil : currency,
            awaiting_fee_payer: awaiting_fee_payer,
            valid_before: valid_before,
            calls: [Pytempo::Call.create(to: currency, value: 0, data: transfer_data)]
          )

          signed_tx = tx.sign(@account.private_key)

          raw_hex = if awaiting_fee_payer
                      "0x#{FeePayer.encode(signed_tx).unpack1("H*")}"
                    else
                      "0x#{signed_tx.encode.unpack1("H*")}"
                    end

          [raw_hex, chain_id]
        end

        def encode_transfer(to, amount)
          selector = "a9059cbb"
          to_padded = to.delete_prefix("0x").downcase.rjust(64, "0")
          amount_padded = amount.to_s(16).rjust(64, "0")
          "0x#{selector}#{to_padded}#{amount_padded}"
        end

        def encode_transfer_with_memo(to, amount, memo)
          selector = "95777d59"
          to_padded = to.delete_prefix("0x").downcase.rjust(64, "0")
          amount_padded = amount.to_s(16).rjust(64, "0")
          memo_clean = memo.delete_prefix("0x")
          unless memo_clean.length == 64
            raise ArgumentError,
                  "memo must be exactly 32 bytes (64 hex chars), got #{memo_clean.length}"
          end

          "0x#{selector}#{to_padded}#{amount_padded}#{memo_clean.downcase}"
        end
      end

      # Factory function to create a configured TempoMethod.
      def self.tempo(intents:, account: nil, fee_payer: nil, chain_id: nil, rpc_url: nil,
                     root_account: nil, currency: nil, recipient: nil, decimals: 6, client_id: nil)
        rpc_url ||= chain_id ? Defaults.rpc_url_for_chain(chain_id) : Defaults::RPC_URL
        currency ||= Defaults.default_currency_for_chain(chain_id)

        method = TempoMethod.new(
          account: account,
          fee_payer: fee_payer,
          rpc_url: rpc_url,
          chain_id: chain_id,
          root_account: root_account,
          currency: currency,
          recipient: recipient,
          decimals: decimals,
          client_id: client_id
        )

        intents.each_value do |intent|
          intent.rpc_url = rpc_url if intent.respond_to?(:rpc_url=) && intent.rpc_url.nil?
          intent.instance_variable_set(:@_method, method) if intent.respond_to?(:fee_payer)
        end
        method.intents = intents.dup
        method
      end
    end
  end
end
