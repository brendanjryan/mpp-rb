# frozen_string_literal: true

require "test_helper"

class TestSessionClientMethod < Minitest::Test
  FakeAccount = Struct.new(:address) do
    def sign_hash(_digest)
      "\x11" * 65
    end
  end

  def setup
    @account = FakeAccount.new("0x1234567890abcdef1234567890abcdef12345678")
    @challenge = Mpp::Challenge.new(
      id: "challenge-1",
      method: "tempo",
      intent: "session",
      request: {
        "amount" => "1000",
        "currency" => Mpp::Methods::Tempo::Defaults::PATH_USD,
        "recipient" => "0x0000000000000000000000000000000000000001",
        "methodDetails" => {
          "chainId" => Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID,
          "escrowContract" => Mpp::Methods::Tempo::Defaults.escrow_contract_for_chain(
            Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID
          )
        }
      },
      realm: "test"
    )
  end

  def test_prepare_open_credential_uses_transaction_builder
    prepared = nil
    Mpp::Methods::Tempo::Session::Voucher.stub(:typed_data_hash, "\x00" * 32) do
      method = Mpp::Methods::Tempo::Session::ClientMethod.new(
        account: @account,
        deposit: "1.5",
        create_open_transaction: lambda { |**kwargs|
          assert_equal "1000", kwargs[:cumulative_amount].to_s
          assert_equal @account.address, kwargs[:authorized_signer]
          "0xopen-tx"
        }
      )

      prepared = method.prepare_credential(@challenge)
    end

    assert_equal "open", prepared.action
    assert_equal "0xopen-tx", prepared.credential.payload["transaction"]
    assert_equal "1000", prepared.credential.payload["cumulativeAmount"]
    assert_equal Mpp::Units.parse_units("1.5", 6), prepared.channel.deposit
  end

  def test_prepare_voucher_credential_uses_existing_channel_state
    voucher_prepared = nil
    open_prepared = nil
    Mpp::Methods::Tempo::Session::Voucher.stub(:typed_data_hash, "\x00" * 32) do
      method = Mpp::Methods::Tempo::Session::ClientMethod.new(
        account: @account,
        create_open_transaction: ->(**_kwargs) { "0xopen-tx" }
      )

      open_prepared = method.prepare_credential(@challenge, context: {action: "open", deposit_raw: "5000"})
      method.commit(open_prepared)

      voucher_prepared = method.prepare_credential(@challenge, context: {action: "voucher"})
    end

    assert_equal "voucher", voucher_prepared.action
    assert_equal open_prepared.channel.channel_id, voucher_prepared.credential.payload["channelId"]
    assert_equal "2000", voucher_prepared.credential.payload["cumulativeAmount"]
  end

  def test_close_requires_open_channel
    method = Mpp::Methods::Tempo::Session::ClientMethod.new(account: @account)

    error = assert_raises(ArgumentError) do
      method.prepare_credential(@challenge, context: {action: "close"})
    end

    assert_includes error.message, "No open session channel"
  end
end
