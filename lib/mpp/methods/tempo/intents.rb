# frozen_string_literal: true

require "time"
require "json"

module Mpp
  module Methods
    module Tempo
      MAX_RECEIPT_RETRY_ATTEMPTS = 20
      RECEIPT_RETRY_DELAY_SECONDS = 0.5

      TRANSFER_SELECTOR = "a9059cbb"
      TRANSFER_WITH_MEMO_SELECTOR = "95777d59"
      TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
      TRANSFER_WITH_MEMO_TOPIC = "0x57bc7354aa85aed339e000bccffabbc529466af35f0772c8f8ee1145927de7f0"

      # Tempo charge intent for server-side verification.
      class ChargeIntent
        attr_reader :name
        attr_accessor :rpc_url

        def initialize(chain_id: nil, rpc_url: nil, timeout: 30, store: nil)
          @name = "charge"
          @rpc_url = rpc_url || (chain_id ? Defaults.rpc_url_for_chain(chain_id) : nil)
          @_method = nil
          @timeout = timeout
          @store = store
        end

        def fee_payer
          @_method&.fee_payer
        end

        def verify(credential, request)
          req = Schemas::ChargeRequest.from_hash(request)

          # Check challenge expiry
          challenge_expires = credential.challenge.expires
          if challenge_expires
            expires = Time.iso8601(challenge_expires.gsub("Z", "+00:00"))
            raise Mpp::VerificationError, "Request has expired" if expires < Time.now.utc
          end

          payload_data = credential.payload
          unless payload_data.is_a?(Hash) && payload_data.key?("type")
            raise Mpp::VerificationError,
                  "Invalid credential payload"
          end

          case payload_data["type"]
          when "hash"
            payload = Schemas::HashCredentialPayload.new(type: "hash", hash: payload_data["hash"])
            verify_hash(payload, req)
          when "transaction"
            payload = Schemas::TransactionCredentialPayload.new(
              type: "transaction", signature: payload_data["signature"]
            )
            verify_transaction(payload, req)
          else
            raise Mpp::VerificationError, "Invalid credential type: #{payload_data["type"]}"
          end
        end

        private

        def get_rpc_url
          raise Mpp::VerificationError, "No rpc_url configured on ChargeIntent" unless @rpc_url

          @rpc_url
        end

        def verify_hash(payload, request)
          if @store
            store_key = "mpp:charge:#{payload.hash.downcase}"
            raise Mpp::VerificationError, "Transaction hash already used" unless @store.put_if_absent(store_key,
                                                                                                      payload.hash)
          end

          rpc_url = get_rpc_url
          result = Rpc.call(rpc_url, "eth_getTransactionReceipt", [payload.hash])

          raise Mpp::VerificationError, "Transaction not found" unless result
          raise Mpp::VerificationError, "Transaction reverted" unless result["status"] == "0x1"
          unless verify_transfer_logs(
            result, request
          )
            raise Mpp::VerificationError,
                  "Transaction must contain a Transfer log matching request parameters"
          end

          Mpp::Receipt.success(payload.hash)
        end

        def verify_transaction(payload, request)
          validate_transaction_payload(payload.signature, request)

          raw_tx = payload.signature

          if request.method_details.fee_payer
            if fee_payer
              raw_tx = cosign_as_fee_payer(raw_tx, request.currency, request: request)
            else
              fee_payer_url = request.method_details.fee_payer_url || Defaults::DEFAULT_FEE_PAYER_URL
              result = Rpc.call(fee_payer_url, "eth_signRawTransaction", [raw_tx])
              raise Mpp::VerificationError, "Fee payer returned no signed transaction" unless result

              raw_tx = result
            end
          end

          rpc_url = get_rpc_url
          tx_hash = Rpc.call(rpc_url, "eth_sendRawTransaction", [raw_tx])
          raise Mpp::VerificationError, "No transaction hash returned" unless tx_hash

          receipt_data = nil
          MAX_RECEIPT_RETRY_ATTEMPTS.times do |attempt|
            receipt_data = Rpc.call(rpc_url, "eth_getTransactionReceipt", [tx_hash])
            break if receipt_data

            sleep(RECEIPT_RETRY_DELAY_SECONDS) if attempt < MAX_RECEIPT_RETRY_ATTEMPTS - 1
          end

          raise Mpp::VerificationError, "Transaction receipt not found after retries" unless receipt_data
          raise Mpp::VerificationError, "Transaction reverted" unless receipt_data["status"] == "0x1"
          unless verify_transfer_logs(
            receipt_data, request
          )
            raise Mpp::VerificationError,
                  "Transaction must contain a Transfer log matching request parameters"
          end

          Mpp::Receipt.success(tx_hash)
        end

        def verify_transfer_logs(receipt, request, expected_sender: nil)
          expected_memo = request.method_details.memo

          (receipt["logs"] || []).each do |log|
            next unless log["address"]&.downcase == request.currency.downcase

            topics = log["topics"] || []
            next if topics.length < 3

            from_address = "0x#{topics[1][-40..]}"
            to_address = "0x#{topics[2][-40..]}"

            next unless to_address.downcase == request.recipient.downcase
            next if expected_sender && from_address.downcase != expected_sender.downcase

            if expected_memo
              next unless topics[0] == TRANSFER_WITH_MEMO_TOPIC
              next if topics.length < 4

              data = log.fetch("data", "0x")
              next if data.length < 66

              amount = data[2, 64].to_i(16)
              memo = topics[3]
              memo_clean = expected_memo.downcase
              memo_clean = "0x#{memo_clean}" unless memo_clean.start_with?("0x")
              return true if amount == Integer(request.amount) && memo.downcase == memo_clean
            else
              next unless topics[0] == TRANSFER_TOPIC

              data = log.fetch("data", "0x")
              next if data.length < 66

              amount = data.delete_prefix("0x").to_i(16)
              return true if amount == Integer(request.amount)
            end
          end

          false
        end

        def validate_transaction_payload(signature, request)
          # Best-effort pre-broadcast check
          begin
            require "rlp"
          rescue LoadError
            return
          end

          begin
            tx_bytes = [signature.delete_prefix("0x")].pack("H*")
          rescue ArgumentError
            return
          end

          return if tx_bytes.empty? || ![0x76, 0x78].include?(tx_bytes.getbyte(0))

          begin
            decoded = RLP.decode(tx_bytes[1..])
          rescue StandardError
            return
          end

          return unless decoded.is_a?(Array) && decoded.length >= 5

          calls_data = decoded[4] || []
          raise Mpp::VerificationError, "Transaction contains no calls" if calls_data.empty?

          found = calls_data.any? do |call_item|
            next unless call_item.is_a?(Array) && call_item.length >= 3

            call_to_bytes = call_item[0]
            call_data_bytes = call_item[2]
            next unless call_to_bytes && call_data_bytes

            to_hex = call_to_bytes.is_a?(String) ? call_to_bytes.unpack1("H*") : call_to_bytes.to_s
            next unless "0x#{to_hex}".downcase == request.currency.downcase

            data_hex = call_data_bytes.is_a?(String) ? call_data_bytes.unpack1("H*") : call_data_bytes.to_s
            match_transfer_calldata(data_hex, request)
          end

          raise Mpp::VerificationError, "Invalid transaction: no matching payment call found" unless found
        end

        def match_transfer_calldata(call_data_hex, request)
          return false if call_data_hex.length < 136

          selector = call_data_hex[0, 8].downcase
          expected_memo = request.method_details.memo

          if expected_memo
            return false unless selector == TRANSFER_WITH_MEMO_SELECTOR
          elsif ![TRANSFER_SELECTOR, TRANSFER_WITH_MEMO_SELECTOR].include?(selector)
            return false
          end

          decoded_to = "0x#{call_data_hex[32, 40]}"
          decoded_amount = call_data_hex[72, 64].to_i(16)

          return false unless decoded_to.downcase == request.recipient.downcase
          return false unless decoded_amount == Integer(request.amount)

          if expected_memo
            return false if call_data_hex.length < 200

            decoded_memo = "0x#{call_data_hex[136, 64]}"
            memo_clean = expected_memo.downcase
            memo_clean = "0x#{memo_clean}" unless memo_clean.start_with?("0x")
            return false unless decoded_memo.downcase == memo_clean
          end

          true
        end

        def cosign_as_fee_payer(_raw_tx, _fee_token, request: nil) # rubocop:disable Lint/UnusedMethodArgument
          # Full fee payer cosigning requires pytempo Ruby equivalent
          raise Mpp::VerificationError, "Fee payer cosigning not yet implemented in Ruby"
        end
      end
    end
  end
end
