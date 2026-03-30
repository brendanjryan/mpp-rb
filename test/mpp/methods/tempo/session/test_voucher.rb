# frozen_string_literal: true

require "test_helper"

class TestVoucher < Minitest::Test
  def setup
    @eth_available = begin
      require "eth"
      true
    rescue LoadError
      false
    end
  end

  def test_parse_from_payload
    voucher = Mpp::Methods::Tempo::Session::Voucher.parse_from_payload(
      channel_id: "0xabc123",
      cumulative_amount: "500000",
      signature: "0xsig"
    )

    assert_equal "0xabc123", voucher[:channel_id]
    assert_equal 500_000, voucher[:cumulative_amount]
    assert_equal "0xsig", voucher[:signature]
  end

  def test_parse_from_payload_string_amount
    voucher = Mpp::Methods::Tempo::Session::Voucher.parse_from_payload(
      channel_id: "0x1",
      cumulative_amount: "1000000",
      signature: "0xsig"
    )

    assert_equal 1_000_000, voucher[:cumulative_amount]
  end

  def test_typed_data_hash_deterministic
    skip "eth gem not available" unless @eth_available

    hash1 = Mpp::Methods::Tempo::Session::Voucher.typed_data_hash(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      channel_id: "0x" + "ab" * 32,
      cumulative_amount: 1_000_000
    )

    hash2 = Mpp::Methods::Tempo::Session::Voucher.typed_data_hash(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      channel_id: "0x" + "ab" * 32,
      cumulative_amount: 1_000_000
    )

    assert_equal hash1, hash2
    assert_equal 32, hash1.bytesize
  end

  def test_different_amounts_produce_different_hashes
    skip "eth gem not available" unless @eth_available

    hash1 = Mpp::Methods::Tempo::Session::Voucher.typed_data_hash(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      channel_id: "0x" + "ab" * 32,
      cumulative_amount: 1_000_000
    )

    hash2 = Mpp::Methods::Tempo::Session::Voucher.typed_data_hash(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      channel_id: "0x" + "ab" * 32,
      cumulative_amount: 2_000_000
    )

    refute_equal hash1, hash2
  end

  def test_different_chain_ids_produce_different_hashes
    skip "eth gem not available" unless @eth_available

    hash1 = Mpp::Methods::Tempo::Session::Voucher.typed_data_hash(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      channel_id: "0x" + "ab" * 32,
      cumulative_amount: 1_000_000
    )

    hash2 = Mpp::Methods::Tempo::Session::Voucher.typed_data_hash(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 42_431,
      channel_id: "0x" + "ab" * 32,
      cumulative_amount: 1_000_000
    )

    refute_equal hash1, hash2
  end

  def test_verify_rejects_keychain_signatures
    skip "eth gem not available" unless @eth_available

    # Keychain signatures are 86 bytes (172 hex chars) — should be rejected
    long_sig = "0x" + "ab" * 86

    result = Mpp::Methods::Tempo::Session::Voucher.verify(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      voucher: {
        channel_id: "0x" + "ab" * 32,
        cumulative_amount: 1_000_000,
        signature: long_sig
      },
      expected_signer: "0x1234567890abcdef1234567890abcdef12345678"
    )

    refute result
  end

  def test_verify_rejects_short_signatures
    skip "eth gem not available" unless @eth_available

    result = Mpp::Methods::Tempo::Session::Voucher.verify(
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217,
      voucher: {
        channel_id: "0x" + "ab" * 32,
        cumulative_amount: 1_000_000,
        signature: "0x" + "ab" * 10
      },
      expected_signer: "0x1234567890abcdef1234567890abcdef12345678"
    )

    refute result
  end

  def test_verify_raises_without_eth_gem
    # Only meaningful if eth is NOT available
    skip "eth gem is available, can't test missing dep" if @eth_available

    assert_raises(RuntimeError) do
      Mpp::Methods::Tempo::Session::Voucher.verify(
        escrow_contract: "0xescrow",
        chain_id: 4217,
        voucher: {channel_id: "0x1", cumulative_amount: 100, signature: "0x" + "ab" * 65},
        expected_signer: "0xsigner"
      )
    end
  end
end
