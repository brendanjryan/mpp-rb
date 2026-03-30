# frozen_string_literal: true

require "test_helper"

class TestSessionHandler < Minitest::Test
  def setup
    @store = Mpp::Methods::Tempo::Session::MemoryChannelStore.new
    @session_intent = Mpp::Methods::Tempo::Session::SessionIntent.new(
      rpc_url: "http://localhost:8545",
      store: @store,
      escrow_contract: "0x33b901018174DDabE4841042ab76ba85D4e24f25",
      chain_id: 4217
    )

    # Create a minimal method object that has both charge and session intents
    @method = Struct.new(:name, :intents, :currency, :recipient, :decimals, :chain_id)
      .new(
        "tempo",
        {"session" => @session_intent},
        "0x20C000000000000000000000b9537d11c60E8b50",
        "0x1234567890abcdef1234567890abcdef12345678",
        6,
        4217
      )

    @handler = Mpp::Server::MppHandler.new(
      method: @method,
      realm: "test-realm",
      secret_key: "test-secret-key-minimum-32-bytes!"
    )
  end

  def test_session_returns_challenge_for_nil_auth
    result = @handler.session(nil, "0.01")

    assert_instance_of Mpp::Challenge, result
    assert_equal "session", result.intent
    assert_equal "tempo", result.method
    assert_equal "test-realm", result.realm
  end

  def test_session_challenge_has_correct_request
    result = @handler.session(nil, "1.5")

    assert_instance_of Mpp::Challenge, result
    # 1.5 * 10^6 = 1_500_000
    request = result.request
    assert_equal "1500000", request["amount"]
    assert_equal "0x20C000000000000000000000b9537d11c60E8b50", request["currency"]
    assert_equal "0x1234567890abcdef1234567890abcdef12345678", request["recipient"]
  end

  def test_session_raises_without_session_intent
    method_no_session = Struct.new(:name, :intents, :currency, :recipient, :decimals)
      .new("tempo", {}, "0xtoken", "0xrecipient", 6)

    handler = Mpp::Server::MppHandler.new(
      method: method_no_session,
      realm: "test",
      secret_key: "test-secret-key-minimum-32-bytes!"
    )

    assert_raises(ArgumentError) do
      handler.session(nil, "0.01")
    end
  end

  def test_session_raises_without_currency
    method_no_currency = Struct.new(:name, :intents)
      .new("tempo", {"session" => @session_intent})

    handler = Mpp::Server::MppHandler.new(
      method: method_no_currency,
      realm: "test",
      secret_key: "test-secret-key-minimum-32-bytes!"
    )

    assert_raises(ArgumentError) do
      handler.session(nil, "0.01")
    end
  end

  def test_session_raises_without_recipient
    method_no_recipient = Struct.new(:name, :intents, :currency)
      .new("tempo", {"session" => @session_intent}, "0xtoken")

    handler = Mpp::Server::MppHandler.new(
      method: method_no_recipient,
      realm: "test",
      secret_key: "test-secret-key-minimum-32-bytes!"
    )

    assert_raises(ArgumentError) do
      handler.session(nil, "0.01")
    end
  end

  def test_session_with_extra_params
    result = @handler.session(nil, "0.01", extra: {"model" => "gpt-4"})

    assert_instance_of Mpp::Challenge, result
    request = result.request
    assert_equal({"model" => "gpt-4"}, request["extra"])
  end

  def test_session_with_chain_id_and_escrow
    result = @handler.session(
      nil, "0.01",
      chain_id: 42_431,
      escrow_contract: "0xe1c4d3dce17bc111181ddf716f75bae49e61a336"
    )

    assert_instance_of Mpp::Challenge, result
    method_details = result.request["methodDetails"]
    assert_equal 42_431, method_details["chainId"]
    assert_equal "0xe1c4d3dce17bc111181ddf716f75bae49e61a336", method_details["escrowContract"]
  end

  def test_session_rejects_invalid_authorization
    result = @handler.session("Bearer invalid-token", "0.01")

    # Should get a new challenge (no payment scheme found)
    assert_instance_of Mpp::Challenge, result
  end
end
