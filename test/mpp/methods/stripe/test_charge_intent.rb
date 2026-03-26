# typed: ignore
# frozen_string_literal: true

require "test_helper"
require "json"

class TestStripeChargeIntent < Minitest::Test
  def setup
    @intent = Mpp::Methods::Stripe::ChargeIntent.new(
      secret_key: "sk_test_fake",
      api_base: "https://api.stripe.com"
    )
  end

  def make_credential(payload:, expires: nil)
    expires ||= (Time.now.utc + 300).strftime("%Y-%m-%dT%H:%M:%S.%LZ")
    echo = Mpp::ChallengeEcho.new(
      id: "test-id",
      realm: "test-realm",
      method: "stripe",
      intent: "charge",
      request: "",
      expires: expires,
      digest: nil,
      opaque: nil
    )
    Mpp::Credential.new(challenge: echo, payload: payload)
  end

  def make_request(amount: "100", currency: "usd", method_details: nil)
    req = {
      "amount" => amount,
      "currency" => currency,
      "recipient" => "acct_test123"
    }
    req["methodDetails"] = method_details if method_details
    req
  end

  def test_verify_rejects_missing_spt
    credential = make_credential(payload: {"type" => "token"})
    request = make_request

    assert_raises(Mpp::VerificationError) do
      @intent.verify(credential, request)
    end
  end

  def test_verify_rejects_expired_challenge
    expired = (Time.now.utc - 60).strftime("%Y-%m-%dT%H:%M:%S.%LZ")
    credential = make_credential(
      payload: {"spt" => "spt_test123"},
      expires: expired
    )
    request = make_request

    err = assert_raises(Mpp::VerificationError) do
      @intent.verify(credential, request)
    end
    assert_match(/expired/i, err.message)
  end

  def test_verify_calls_stripe_api
    credential = make_credential(payload: {"spt" => "spt_test123", "externalId" => "ext_1"})
    request = make_request(method_details: {"metadata" => {"order" => "123"}})

    # Stub Net::HTTP
    mock_response = Minitest::Mock.new
    mock_response.expect(:is_a?, true, [Net::HTTPSuccess])
    mock_response.expect(:body, JSON.generate({
      "id" => "pi_abc123",
      "status" => "succeeded"
    }))

    mock_http = Minitest::Mock.new
    mock_http.expect(:use_ssl=, nil, [true])
    mock_http.expect(:request, mock_response, [Net::HTTP::Post])

    Net::HTTP.stub(:new, mock_http) do
      receipt = @intent.verify(credential, request)
      assert_equal "success", receipt.status
      assert_equal "pi_abc123", receipt.reference
      assert_equal "stripe", receipt.method
      assert_equal "ext_1", receipt.external_id
    end

    mock_http.verify
    mock_response.verify
  end

  def test_verify_rejects_failed_payment
    credential = make_credential(payload: {"spt" => "spt_test123"})
    request = make_request

    mock_response = Minitest::Mock.new
    mock_response.expect(:is_a?, false, [Net::HTTPSuccess])
    mock_response.expect(:body, JSON.generate({
      "error" => {"message" => "Card declined"}
    }))
    mock_response.expect(:code, "402")

    mock_http = Minitest::Mock.new
    mock_http.expect(:use_ssl=, nil, [true])
    mock_http.expect(:request, mock_response, [Net::HTTP::Post])

    Net::HTTP.stub(:new, mock_http) do
      err = assert_raises(Mpp::VerificationError) do
        @intent.verify(credential, request)
      end
      assert_match(/Card declined/, err.message)
    end
  end

  def test_verify_rejects_requires_action
    credential = make_credential(payload: {"spt" => "spt_test123"})
    request = make_request

    mock_response = Minitest::Mock.new
    mock_response.expect(:is_a?, true, [Net::HTTPSuccess])
    mock_response.expect(:body, JSON.generate({
      "id" => "pi_needs3ds",
      "status" => "requires_action"
    }))

    mock_http = Minitest::Mock.new
    mock_http.expect(:use_ssl=, nil, [true])
    mock_http.expect(:request, mock_response, [Net::HTTP::Post])

    Net::HTTP.stub(:new, mock_http) do
      assert_raises(Mpp::PaymentActionRequiredError) do
        @intent.verify(credential, request)
      end
    end
  end
end
