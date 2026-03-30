# typed: false
# frozen_string_literal: true

module Mpp
  module Methods
    module Tempo
      module Session
        module Voucher
          EIP712_DOMAIN_NAME = "Tempo Stream Channel"
          EIP712_DOMAIN_VERSION = "1"

          # EIP-712 type hash for the Voucher struct:
          # keccak256("Voucher(bytes32 channelId,uint128 cumulativeAmount)")
          VOUCHER_TYPEHASH = nil # computed lazily

          module_function

          # Verify a voucher signature via EIP-712 typed data recovery.
          # Returns true if the recovered signer matches expected_signer.
          #
          # Only accepts raw secp256k1 signatures (65 bytes). Keychain,
          # p256, and webAuthn signatures are rejected.
          def verify(escrow_contract:, chain_id:, voucher:, expected_signer:)
            require "eth"

            sig_hex = voucher[:signature].delete_prefix("0x")

            # Reject non-standard signature lengths (keychain = 86 bytes = 172 hex chars)
            return false unless sig_hex.length == 130

            digest = typed_data_hash(
              escrow_contract: escrow_contract,
              chain_id: chain_id,
              channel_id: voucher[:channel_id],
              cumulative_amount: voucher[:cumulative_amount]
            )

            # Decompose signature: r (32 bytes) + s (32 bytes) + v (1 byte)
            r = sig_hex[0, 64]
            s = sig_hex[64, 64]
            v = sig_hex[128, 2].to_i(16)

            # Normalize v value (EIP-155 compatibility)
            v -= 27 if v >= 27

            recovered = ecrecover(digest, v, r, s)
            return false unless recovered

            recovered.downcase == expected_signer.downcase
          rescue LoadError
            raise "eth gem is required for voucher verification. Install with: gem install eth"
          rescue => e
            raise Mpp::VerificationError, "Voucher verification failed: #{e.message}"
          end

          # Compute the EIP-712 typed data hash for a voucher.
          # This is the hash that gets signed/verified: keccak256("\x19\x01" || domainSeparator || structHash)
          def typed_data_hash(escrow_contract:, chain_id:, channel_id:, cumulative_amount:)
            require "eth"

            domain_separator = compute_domain_separator(escrow_contract, chain_id)
            struct_hash = compute_struct_hash(channel_id, cumulative_amount)

            # EIP-712: "\x19\x01" || domainSeparator || structHash
            msg = "\x19\x01".b + domain_separator + struct_hash
            keccak256(msg)
          end

          # Parse a voucher from credential payload fields.
          def parse_from_payload(channel_id:, cumulative_amount:, signature:)
            {
              channel_id: channel_id,
              cumulative_amount: Integer(cumulative_amount),
              signature: signature
            }
          end

          # --- private helpers ---

          def compute_domain_separator(escrow_contract, chain_id)
            # EIP-712 domain separator:
            # keccak256(abi.encode(
            #   keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            #   keccak256(name),
            #   keccak256(version),
            #   chainId,
            #   verifyingContract
            # ))
            type_hash = keccak256(
              "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            )
            name_hash = keccak256(EIP712_DOMAIN_NAME)
            version_hash = keccak256(EIP712_DOMAIN_VERSION)
            chain_id_padded = abi_encode_uint256(chain_id)
            contract_padded = abi_encode_address(escrow_contract)

            keccak256(type_hash + name_hash + version_hash + chain_id_padded + contract_padded)
          end

          def compute_struct_hash(channel_id, cumulative_amount)
            # keccak256("Voucher(bytes32 channelId,uint128 cumulativeAmount)")
            voucher_type_hash = keccak256("Voucher(bytes32 channelId,uint128 cumulativeAmount)")
            channel_id_bytes = abi_encode_bytes32(channel_id)
            amount_padded = abi_encode_uint256(cumulative_amount)

            keccak256(voucher_type_hash + channel_id_bytes + amount_padded)
          end

          def keccak256(data)
            data = data.b if data.is_a?(String) && data.encoding != Encoding::BINARY
            Eth::Util.keccak256(data)
          end

          def ecrecover(hash, v, r, s)
            # Use eth gem's recovery
            r_bytes = [r].pack("H*")
            s_bytes = [s].pack("H*")
            signature = r_bytes + s_bytes + [v].pack("C")

            # eth gem expects hex-encoded hash without 0x prefix
            hash_hex = hash.unpack1("H*")

            public_key = Eth::Signature.recover(hash_hex, signature.unpack1("H*"), Eth::Chain::MAINNET)
            return nil unless public_key

            # Derive address from public key
            Eth::Util.public_key_to_address(public_key).to_s
          rescue
            nil
          end

          # ABI encode helpers (pad to 32 bytes)
          def abi_encode_uint256(value)
            [value.to_i].pack("Q>").rjust(32, "\x00").b
          rescue
            # For large values, use manual hex encoding
            hex = value.to_i.to_s(16).rjust(64, "0")
            [hex].pack("H*")
          end

          def abi_encode_address(addr)
            hex = addr.delete_prefix("0x").downcase
            [hex.rjust(64, "0")].pack("H*")
          end

          def abi_encode_bytes32(hex_str)
            hex = hex_str.delete_prefix("0x")
            [hex.ljust(64, "0")].pack("H*")
          end
        end
      end
    end
  end
end
