# frozen_string_literal: true

require "test_helper"

class TestSessionIntent < Minitest::Test
  def setup
    @store = Mpp::Methods::Tempo::Session::MemoryChannelStore.new
    @intent = Mpp::Methods::Tempo::Session::SessionIntent.new(
      rpc_url: "http://localhost:8545",
      store: @store,
      min_voucher_delta: 0,
      escrow_contract: "0xescrow",
      chain_id: 4217
    )
  end

  def make_credential(action:, payload: {}, request: {})
    challenge = Struct.new(:id, :realm, :method, :intent, :request, :expires, :digest, :opaque)
      .new(
        "ch_test",
        "test-realm",
        "tempo",
        "session",
        {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"}.merge(request),
        nil,
        nil,
        nil
      )

    full_payload = {"action" => action}.merge(payload)

    Struct.new(:challenge, :payload)
      .new(challenge, full_payload)
  end

  def test_rejects_missing_action
    credential = make_credential(action: "bogus")
    credential = Struct.new(:challenge, :payload).new(credential.challenge, {})

    assert_raises(Mpp::BadRequestError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_rejects_unknown_action
    credential = make_credential(action: "unknown_action")

    assert_raises(Mpp::BadRequestError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_voucher_rejects_channel_not_found
    credential = make_credential(
      action: "voucher",
      payload: {
        "channelId" => "0xnonexistent",
        "cumulativeAmount" => "500000",
        "signature" => "0x" + "ab" * 65
      }
    )

    assert_raises(Mpp::ChannelNotFoundError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_voucher_rejects_finalized_channel
    channel = Mpp::Methods::Tempo::Session::ChannelState.new(
      channel_id: "0xchannel",
      chain_id: 4217,
      escrow_contract: "0xescrow",
      payer: "0xpayer",
      payee: "0xpayee",
      token: "0xtoken",
      authorized_signer: "0xsigner",
      deposit: 1_000_000,
      finalized: true
    )
    @store.update_channel("0xchannel") { |_| channel }

    credential = make_credential(
      action: "voucher",
      payload: {
        "channelId" => "0xchannel",
        "cumulativeAmount" => "500000",
        "signature" => "0x" + "ab" * 65
      }
    )

    assert_raises(Mpp::ChannelClosedError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_close_rejects_channel_not_found
    credential = make_credential(
      action: "close",
      payload: {
        "channelId" => "0xnonexistent",
        "cumulativeAmount" => "500000",
        "signature" => "0x" + "ab" * 65
      }
    )

    assert_raises(Mpp::ChannelNotFoundError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_close_rejects_already_finalized
    channel = Mpp::Methods::Tempo::Session::ChannelState.new(
      channel_id: "0xchannel",
      chain_id: 4217,
      escrow_contract: "0xescrow",
      payer: "0xpayer",
      payee: "0xpayee",
      token: "0xtoken",
      authorized_signer: "0xsigner",
      deposit: 1_000_000,
      finalized: true
    )
    @store.update_channel("0xchannel") { |_| channel }

    credential = make_credential(
      action: "close",
      payload: {
        "channelId" => "0xchannel",
        "cumulativeAmount" => "500000",
        "signature" => "0x" + "ab" * 65
      }
    )

    assert_raises(Mpp::ChannelClosedError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_top_up_rejects_channel_not_found
    credential = make_credential(
      action: "topUp",
      payload: {
        "channelId" => "0xnonexistent",
        "transaction" => "0xtx",
        "additionalDeposit" => "500000"
      }
    )

    assert_raises(Mpp::ChannelNotFoundError) do
      @intent.verify(credential, {"amount" => "1000000", "currency" => "0xtoken", "recipient" => "0xpayee"})
    end
  end

  def test_intent_name
    assert_equal "session", @intent.name
  end

  def test_intent_exposes_store
    assert_equal @store, @intent.store
  end
end
