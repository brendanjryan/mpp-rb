# frozen_string_literal: true

require "test_helper"

class TestSessionManager < Minitest::Test
  FakeAccount = Struct.new(:address) do
    def sign_hash(_digest)
      "\x22" * 65
    end
  end

  FakeResponse = Struct.new(:code, :body, :headers) do
    def [](key)
      headers[key]
    end

    def get_fields(key)
      value = headers[key]
      return nil unless value

      Array(value)
    end
  end

  def setup
    @challenge = Mpp::Challenge.create(
      secret_key: "test-secret",
      realm: "api.example.com",
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
      expires: Mpp::Expires.minutes(5)
    )
  end

  def test_fetch_retries_with_session_credential_and_tracks_state
    seen_authorization = []
    queue = [
      FakeResponse.new("402", "", {"www-authenticate" => @challenge.to_www_authenticate("api.example.com")}),
      FakeResponse.new("200", "ok", {})
    ]

    response = nil
    Mpp::Methods::Tempo::Session::Voucher.stub(:typed_data_hash, "\x00" * 32) do
      manager = Mpp::Methods::Tempo::Session::SessionManager.new(
        account: FakeAccount.new("0x1234567890abcdef1234567890abcdef12345678"),
        deposit: "1.0",
        create_open_transaction: ->(**_kwargs) { "0xopen-tx" },
        requester: lambda { |_url, method:, headers:, body:|
          seen_authorization << headers["Authorization"] if headers["Authorization"]
          response = queue.shift
          refute_nil response
          assert_nil body
          assert_includes %w[GET POST], method
          response
        }
      )

      response = manager.fetch("https://api.example.com/paid")

      assert manager.opened?
      refute_nil manager.channel_id
      assert_equal 1000, manager.cumulative
    end

    assert_equal "200", response.code
    assert_equal 1, seen_authorization.length
  end

  def test_open_posts_authorization_using_last_challenge
    queue = [
      FakeResponse.new("204", "", {})
    ]
    posted_headers = []

    response = nil
    Mpp::Methods::Tempo::Session::Voucher.stub(:typed_data_hash, "\x00" * 32) do
      manager = Mpp::Methods::Tempo::Session::SessionManager.new(
        account: FakeAccount.new("0x1234567890abcdef1234567890abcdef12345678"),
        deposit: "1.0",
        create_open_transaction: ->(**_kwargs) { "0xopen-tx" },
        requester: lambda { |_url, method:, headers:, body:|
          posted_headers << headers
          assert_equal "POST", method
          assert_nil body
          queue.shift
        }
      )

      manager.instance_variable_set(:@last_challenge, @challenge)
      manager.instance_variable_set(:@last_url, "https://api.example.com/session")
      response = manager.open
    end

    assert_equal "204", response.code
    assert_match(/^Payment /, posted_headers.first["Authorization"])
  end
end
