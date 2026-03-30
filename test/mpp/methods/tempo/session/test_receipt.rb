# frozen_string_literal: true

require "test_helper"

class TestSessionReceipt < Minitest::Test
  def test_create_session_receipt
    receipt = Mpp::Methods::Tempo::Session::SessionReceipt.create(
      challenge_id: "ch_123",
      channel_id: "0xabc",
      accepted_cumulative: 500_000,
      spent: 100_000,
      units: 5,
      tx_hash: "0xtx123"
    )

    assert_equal "success", receipt.status
    assert_equal "tempo", receipt.method
    assert_equal "session", receipt.intent
    assert_equal "ch_123", receipt.challenge_id
    assert_equal "0xabc", receipt.channel_id
    assert_equal "0xabc", receipt.reference
    assert_equal "500000", receipt.accepted_cumulative
    assert_equal "100000", receipt.spent
    assert_equal 5, receipt.units
    assert_equal "0xtx123", receipt.tx_hash
    refute_nil receipt.timestamp
  end

  def test_create_without_optional_fields
    receipt = Mpp::Methods::Tempo::Session::SessionReceipt.create(
      challenge_id: "ch_123",
      channel_id: "0xabc",
      accepted_cumulative: 500_000,
      spent: 100_000
    )

    assert_nil receipt.units
    assert_nil receipt.tx_hash
  end

  def test_serialize_deserialize_roundtrip
    receipt = Mpp::Methods::Tempo::Session::SessionReceipt.create(
      challenge_id: "ch_123",
      channel_id: "0xabc",
      accepted_cumulative: 500_000,
      spent: 100_000,
      units: 5
    )

    encoded = receipt.serialize
    decoded = Mpp::Methods::Tempo::Session::SessionReceipt.deserialize(encoded)

    assert_equal receipt.method, decoded.method
    assert_equal receipt.intent, decoded.intent
    assert_equal receipt.status, decoded.status
    assert_equal receipt.challenge_id, decoded.challenge_id
    assert_equal receipt.channel_id, decoded.channel_id
    assert_equal receipt.accepted_cumulative, decoded.accepted_cumulative
    assert_equal receipt.spent, decoded.spent
    assert_equal receipt.units, decoded.units
  end

  def test_serialize_excludes_nil_fields
    receipt = Mpp::Methods::Tempo::Session::SessionReceipt.create(
      challenge_id: "ch_123",
      channel_id: "0xabc",
      accepted_cumulative: 500_000,
      spent: 100_000
    )

    encoded = receipt.serialize
    json = Base64.urlsafe_decode64(encoded)
    data = JSON.parse(json)

    refute data.key?("units")
    refute data.key?("txHash")
  end
end
