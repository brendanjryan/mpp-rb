# typed: false
# frozen_string_literal: true

require "time"
require_relative "types"

module Mpp
  module Methods
    module Tempo
      module Session
        module Chain
          module_function

          # Query escrow contract for channel state via eth_call.
          # Returns a hash with on-chain channel fields.
          def get_on_chain_channel(rpc_url, escrow_contract, channel_id)
            # ABI-encode getChannel(bytes32 channelId)
            selector = GET_CHANNEL_SELECTOR.delete_prefix("0x")
            channel_bytes = channel_id.delete_prefix("0x").ljust(64, "0")
            data = "0x#{selector}#{channel_bytes}"

            result = Rpc.call(rpc_url, "eth_call", [
              {"to" => escrow_contract, "data" => data},
              "latest"
            ])

            raise Mpp::VerificationError, "Failed to read channel state" unless result

            decode_channel_tuple(result)
          end

          # Broadcast and confirm a signed open transaction.
          # Returns { tx_hash:, on_chain: }
          def broadcast_open_transaction(
            rpc_url:, transaction:, escrow_contract:, channel_id:,
            recipient:, currency:, fee_payer: nil, wait: true
          )
            # Validate the transaction contains an open call to the escrow contract
            validate_open_transaction(transaction, escrow_contract, recipient, currency, channel_id)

            raw_tx = transaction
            if fee_payer
              raw_tx = cosign_fee_payer(rpc_url, raw_tx, fee_payer)
            end

            tx_hash = Rpc.call(rpc_url, "eth_sendRawTransaction", [raw_tx])
            raise Mpp::VerificationError, "No transaction hash returned" unless tx_hash

            if wait
              wait_for_receipt(rpc_url, tx_hash)
            end

            on_chain = get_on_chain_channel(rpc_url, escrow_contract, channel_id)
            {tx_hash: tx_hash, on_chain: on_chain}
          end

          # Broadcast and confirm a signed topUp transaction.
          # Returns { tx_hash:, new_deposit: }
          def broadcast_top_up_transaction(
            rpc_url:, transaction:, escrow_contract:, channel_id:,
            declared_deposit:, previous_deposit:, currency: nil, fee_payer: nil
          )
            raw_tx = transaction
            if fee_payer
              raw_tx = cosign_fee_payer(rpc_url, raw_tx, fee_payer)
            end

            tx_hash = Rpc.call(rpc_url, "eth_sendRawTransaction", [raw_tx])
            raise Mpp::VerificationError, "No transaction hash returned" unless tx_hash

            wait_for_receipt(rpc_url, tx_hash)

            on_chain = get_on_chain_channel(rpc_url, escrow_contract, channel_id)
            unless on_chain[:deposit] > previous_deposit
              raise Mpp::VerificationError, "channel deposit did not increase after topUp"
            end

            {tx_hash: tx_hash, new_deposit: on_chain[:deposit]}
          end

          # Submit close on-chain by building and sending a close transaction.
          # For now, uses the fee payer service if available.
          def close_on_chain(rpc_url:, escrow_contract:, channel_id:,
            cumulative_amount:, signature:, account: nil, fee_payer: nil)
            assert_uint128(cumulative_amount)

            # ABI-encode close(bytes32,uint128,bytes)
            selector = CLOSE_SELECTOR.delete_prefix("0x")
            encoded = encode_settle_or_close_args(channel_id, cumulative_amount, signature)
            data = "0x#{selector}#{encoded}"

            send_contract_tx(
              rpc_url: rpc_url, to: escrow_contract, data: data,
              account: account, fee_payer: fee_payer
            )
          end

          # Submit settle on-chain.
          def settle_on_chain(rpc_url:, escrow_contract:, channel_id:,
            cumulative_amount:, signature:, account: nil, fee_payer: nil)
            assert_uint128(cumulative_amount)

            selector = SETTLE_SELECTOR.delete_prefix("0x")
            encoded = encode_settle_or_close_args(channel_id, cumulative_amount, signature)
            data = "0x#{selector}#{encoded}"

            send_contract_tx(
              rpc_url: rpc_url, to: escrow_contract, data: data,
              account: account, fee_payer: fee_payer
            )
          end

          # --- private helpers ---

          def assert_uint128(amount)
            if amount < 0 || amount > UINT128_MAX
              raise Mpp::VerificationError, "cumulativeAmount exceeds uint128 range"
            end
          end

          def validate_open_transaction(raw_tx, escrow_contract, recipient, currency, channel_id)
            # Best-effort pre-broadcast validation via RLP decode
            begin
              require "rlp"
            rescue LoadError
              return # Skip validation if rlp gem unavailable
            end

            begin
              tx_bytes = [raw_tx.delete_prefix("0x")].pack("H*")
            rescue ArgumentError
              return
            end

            return if tx_bytes.empty?
            return unless [0x76, 0x78].include?(tx_bytes.getbyte(0))

            begin
              decoded = RLP.decode(tx_bytes[1..])
            rescue
              return
            end

            return unless decoded.is_a?(Array) && decoded.length >= 5

            calls_data = decoded[4] || []
            return if calls_data.empty?

            found_open = calls_data.any? do |call_item|
              next unless call_item.is_a?(Array) && call_item.length >= 3
              begin
                to_hex = "0x#{call_item[0].unpack1("H*")}"
              rescue
                next
              end
              next unless to_hex.downcase == escrow_contract.downcase

              begin
                data_hex = call_item[2].unpack1("H*")
              rescue
                next
              end
              next unless data_hex[0, 8].downcase == OPEN_SELECTOR.delete_prefix("0x").downcase
              true
            end

            raise Mpp::VerificationError, "transaction does not contain escrow open call" unless found_open
          end

          # Decode the getChannel return tuple.
          # Solidity returns: (bool finalized, uint256 closeRequestedAt, address payer,
          #   address payee, address token, address authorizedSigner, uint256 deposit, uint256 settled)
          def decode_channel_tuple(hex_data)
            hex = hex_data.delete_prefix("0x")
            return empty_channel if hex.length < 256 # 8 * 32 bytes = 512 hex chars

            # Each field is 32 bytes (64 hex chars)
            finalized = hex[0, 64].to_i(16) != 0
            close_requested_at = hex[64, 64].to_i(16)
            payer = "0x#{hex[128 + 24, 40]}"
            payee = "0x#{hex[192 + 24, 40]}"
            token = "0x#{hex[256 + 24, 40]}"
            authorized_signer = "0x#{hex[320 + 24, 40]}"
            deposit = hex[384, 64].to_i(16)
            settled = hex[448, 64].to_i(16)

            {
              finalized: finalized,
              close_requested_at: close_requested_at,
              payer: payer,
              payee: payee,
              token: token,
              authorized_signer: authorized_signer,
              deposit: deposit,
              settled: settled
            }
          end

          def empty_channel
            {
              finalized: false, close_requested_at: 0,
              payer: ZERO_ADDRESS, payee: ZERO_ADDRESS,
              token: ZERO_ADDRESS, authorized_signer: ZERO_ADDRESS,
              deposit: 0, settled: 0
            }
          end

          # Encode arguments for settle/close: (bytes32 channelId, uint128 cumulativeAmount, bytes signature)
          # Uses dynamic encoding for the bytes parameter.
          def encode_settle_or_close_args(channel_id, cumulative_amount, signature)
            # bytes32 channelId - slot 0
            ch = channel_id.delete_prefix("0x").ljust(64, "0")
            # uint128 cumulativeAmount - slot 1
            amt = cumulative_amount.to_s(16).rjust(64, "0")
            # offset for bytes signature - slot 2 (points to slot 3 = 0x60 = 96)
            offset = "0000000000000000000000000000000000000000000000000000000000000060"
            # bytes length
            sig_hex = signature.delete_prefix("0x")
            sig_len = (sig_hex.length / 2).to_s(16).rjust(64, "0")
            # bytes data (padded to 32 bytes)
            sig_padded = sig_hex.ljust(((sig_hex.length + 63) / 64) * 64, "0")

            "#{ch}#{amt}#{offset}#{sig_len}#{sig_padded}"
          end

          def send_contract_tx(rpc_url:, to:, data:, account: nil, fee_payer: nil)
            if fee_payer
              # Use fee payer service to sponsor the transaction
              result = Rpc.call(
                fee_payer,
                "eth_signAndSendTransaction",
                [{"to" => to, "data" => data}]
              )
              raise Mpp::VerificationError, "Fee payer returned no tx hash" unless result
              wait_for_receipt(rpc_url, result)
              result
            elsif account
              # Sign and send with the account (requires eth gem)
              require "eth"
              sender = account.respond_to?(:address) ? account.address : account
              nonce_hex = Rpc.call(rpc_url, "eth_getTransactionCount", [sender.to_s, "pending"])
              gas_hex = Rpc.call(rpc_url, "eth_gasPrice", [])

              tx_params = {
                "from" => sender.to_s,
                "to" => to,
                "data" => data,
                "nonce" => nonce_hex,
                "gasPrice" => gas_hex,
                "gas" => "0x100000"
              }

              # For full signing we'd need the account's private key
              # This is a simplified path - production would use account.sign_hash
              signed = Rpc.call(rpc_url, "eth_sendTransaction", [tx_params])
              raise Mpp::VerificationError, "No transaction hash returned" unless signed
              wait_for_receipt(rpc_url, signed)
              signed
            else
              raise Mpp::VerificationError,
                "Cannot send transaction: no account or fee payer available"
            end
          end

          def cosign_fee_payer(rpc_url, raw_tx, fee_payer_url)
            result = Rpc.call(fee_payer_url, "eth_signRawTransaction", [raw_tx])
            raise Mpp::VerificationError, "Fee payer returned no signed transaction" unless result
            result
          end

          MAX_RECEIPT_RETRIES = 20
          RECEIPT_RETRY_DELAY = 0.5

          def wait_for_receipt(rpc_url, tx_hash)
            receipt = nil
            MAX_RECEIPT_RETRIES.times do |attempt|
              receipt = Rpc.call(rpc_url, "eth_getTransactionReceipt", [tx_hash])
              break if receipt
              sleep(RECEIPT_RETRY_DELAY) if attempt < MAX_RECEIPT_RETRIES - 1
            end

            raise Mpp::VerificationError, "Transaction receipt not found after retries" unless receipt
            unless receipt["status"] == "0x1"
              raise Mpp::VerificationError, "Transaction reverted: #{tx_hash}"
            end
            receipt
          end
        end
      end
    end
  end
end
