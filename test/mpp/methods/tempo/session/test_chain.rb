# frozen_string_literal: true

require "test_helper"

class TestChain < Minitest::Test
  def test_decode_channel_tuple
    # Build a realistic hex response for getChannel return value
    # (bool finalized, uint256 closeRequestedAt, address payer, address payee,
    #  address token, address authorizedSigner, uint256 deposit, uint256 settled)
    hex = "0x" \
      "0000000000000000000000000000000000000000000000000000000000000000" \
      "0000000000000000000000000000000000000000000000000000000000000000" \
      "000000000000000000000000aabbccddaabbccddaabbccddaabbccddaabbccdd" \
      "0000000000000000000000001122334411223344112233441122334411223344" \
      "000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
      "0000000000000000000000005555555555555555555555555555555555555555" \
      "00000000000000000000000000000000000000000000000000000000000f4240" \
      "0000000000000000000000000000000000000000000000000000000000000000"

    result = Mpp::Methods::Tempo::Session::Chain.decode_channel_tuple(hex)

    refute result[:finalized]
    assert_equal 0, result[:close_requested_at]
    assert_equal "0xaabbccddaabbccddaabbccddaabbccddaabbccdd", result[:payer].downcase
    assert_equal "0x1122334411223344112233441122334411223344", result[:payee].downcase
    assert_equal "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", result[:token].downcase
    assert_equal "0x5555555555555555555555555555555555555555", result[:authorized_signer].downcase
    assert_equal 1_000_000, result[:deposit]
    assert_equal 0, result[:settled]
  end

  def test_decode_channel_tuple_finalized
    hex = "0x" \
      "0000000000000000000000000000000000000000000000000000000000000001" \
      "0000000000000000000000000000000000000000000000000000000065a1bc00" \
      "000000000000000000000000aabbccddaabbccddaabbccddaabbccddaabbccdd" \
      "0000000000000000000000001122334411223344112233441122334411223344" \
      "000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
      "0000000000000000000000005555555555555555555555555555555555555555" \
      "00000000000000000000000000000000000000000000000000000000000f4240" \
      "00000000000000000000000000000000000000000000000000000000000186a0"

    result = Mpp::Methods::Tempo::Session::Chain.decode_channel_tuple(hex)

    assert result[:finalized]
    assert_operator result[:close_requested_at], :>, 0
    assert_equal 1_000_000, result[:deposit]
    assert_equal 100_000, result[:settled]
  end

  def test_decode_empty_channel
    result = Mpp::Methods::Tempo::Session::Chain.decode_channel_tuple("0x")

    refute result[:finalized]
    assert_equal 0, result[:deposit]
    assert_equal Mpp::Methods::Tempo::Session::ZERO_ADDRESS, result[:payer]
  end

  def test_encode_settle_or_close_args
    channel_id = "0x" + "ab" * 32
    cumulative_amount = 500_000
    signature = "0x" + "cd" * 65

    encoded = Mpp::Methods::Tempo::Session::Chain.encode_settle_or_close_args(
      channel_id, cumulative_amount, signature
    )

    # Should start with channel_id (64 hex chars)
    assert_equal "ab" * 32, encoded[0, 64]

    # Second slot is amount (64 hex chars)
    assert_equal cumulative_amount, encoded[64, 64].to_i(16)

    # Third slot is offset (0x60 = 96)
    assert_equal 96, encoded[128, 64].to_i(16)

    # Fourth slot is length of signature bytes
    assert_equal 65, encoded[192, 64].to_i(16)
  end

  def test_assert_uint128_valid
    # Should not raise for valid values
    Mpp::Methods::Tempo::Session::Chain.assert_uint128(0)
    Mpp::Methods::Tempo::Session::Chain.assert_uint128(1_000_000)
    Mpp::Methods::Tempo::Session::Chain.assert_uint128(Mpp::Methods::Tempo::Session::UINT128_MAX)
  end

  def test_assert_uint128_rejects_negative
    assert_raises(Mpp::VerificationError) do
      Mpp::Methods::Tempo::Session::Chain.assert_uint128(-1)
    end
  end

  def test_assert_uint128_rejects_too_large
    assert_raises(Mpp::VerificationError) do
      Mpp::Methods::Tempo::Session::Chain.assert_uint128(Mpp::Methods::Tempo::Session::UINT128_MAX + 1)
    end
  end
end
