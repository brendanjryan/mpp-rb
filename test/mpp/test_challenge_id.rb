# frozen_string_literal: true

require "test_helper"

class TestChallengeId < Minitest::Test
  # Cross-SDK conformance test vectors
  def test_basic_charge
    result = Mpp.generate_challenge_id(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "1000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0x1234567890abcdef1234567890abcdef12345678"
      }
    )

    assert_equal "s0gsoewXwdYI13oPnrtdKTEN4-sIQ-LbQUNV_HttPnA", result
  end

  def test_with_expires
    result = Mpp.generate_challenge_id(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "5000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0xabcdef1234567890abcdef1234567890abcdef12"
      },
      expires: "2026-01-29T12:00:00Z"
    )

    assert_equal "0rMv3trZIudpkJCQxeL2RLQz6uALKTNErWulN07hDLk", result
  end

  def test_with_digest
    result = Mpp.generate_challenge_id(
      secret_key: "my-server-secret",
      realm: "payments.example.org",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "250000",
        "currency" => "USD",
        "recipient" => "0x9999999999999999999999999999999999999999"
      },
      digest: "sha-256=X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE="
    )

    assert_equal "EAX2sqwdeg8Km8LIKRBFhM5xDQvEgIlbTif9FKBsOiU", result
  end

  def test_full_challenge
    result = Mpp.generate_challenge_id(
      secret_key: "production-secret-abc123",
      realm: "api.tempo.xyz",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "10000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0x742d35Cc6634C0532925a3b844Bc9e7595f1B0F2",
        "description" => "API access fee",
        "externalId" => "order-12345"
      },
      expires: "2026-02-01T00:00:00Z",
      digest: "sha-256=abc123def456"
    )

    assert_equal "jDq_IazIMny5JJk3-xm3eSxGaP6XbbaApxBi6fG_320", result
  end

  def test_different_secret_different_id
    result = Mpp.generate_challenge_id(
      secret_key: "different-secret-key",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "1000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0x1234567890abcdef1234567890abcdef12345678"
      }
    )

    assert_equal "UMEn_1WPt2vz3XK8rrkbHET6RwqfwtK8VVNz0Xc2x4A", result
  end

  def test_empty_request
    result = Mpp.generate_challenge_id(
      secret_key: "test-key",
      realm: "test.example.com",
      method: "tempo",
      intent: "authorize",
      request: {}
    )

    assert_equal "jUTqTVe3kCv5rVizv1XBCs9qKCLg4AZLwBUnk4N3MR8", result
  end

  def test_unicode_in_description
    result = Mpp.generate_challenge_id(
      secret_key: "unicode-test-key",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "100",
        "currency" => "EUR",
        "recipient" => "0x1111111111111111111111111111111111111111",
        "description" => "Payment for café ☕"
      }
    )

    assert_equal "OjiT_PsisJ_SkHEomn9dcfraObt4U3nO5Tg3gU0Etmg", result
  end

  def test_nested_method_details
    result = Mpp.generate_challenge_id(
      secret_key: "nested-test-key",
      realm: "api.tempo.xyz",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "5000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0x2222222222222222222222222222222222222222",
        "methodDetails" => {"chainId" => 42_431, "feePayer" => true}
      }
    )

    assert_equal "9Sl6t74wn9zPaakjTSK6DqhGtS5HQVQEkIUYBYdHTbA", result
  end
end

class TestGoldenVectors < Minitest::Test
  SECRET = "test-vector-secret"

  def test_required_fields_only
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000"}
    )

    assert_equal "SOfbA51LV3LCkGE7RbomqwXdbWVlrZwlW-Z9aOHolxw", result
  end

  def test_golden_with_expires
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000"}, expires: "2025-01-06T12:00:00Z"
    )

    assert_equal "R1ZSIwoIjkFhMCSzUGiCTesiigf5vV65EQ_3gVNtsNw", result
  end

  def test_golden_with_digest
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000"},
      digest: "sha-256=X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE"
    )

    assert_equal "AiMmBdsSOkOYpXTupMnzVnrzZbqMY_P2i80vENRUSN4", result
  end

  def test_golden_with_expires_and_digest
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000"},
      expires: "2025-01-06T12:00:00Z",
      digest: "sha-256=X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE"
    )

    assert_equal "FMBGqN7MzpKagHsCcartZM09CnUqv7UgmaCy45Ozgug", result
  end

  def test_multi_field_request
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000", "currency" => "0x1234", "recipient" => "0xabcd"}
    )

    assert_equal "5CXJi4bWMz2W54WjnlmoxnwTYe-JKwhw0z32ICQ65Es", result
  end

  def test_nested_method_details
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000", "currency" => "0x1234", "methodDetails" => {"chainId" => 42_431}}
    )

    assert_equal "eid66xXUZsj46Pb30AfAf7m5kPehgianI16rZ-QY8HU", result
  end

  def test_empty_request
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "charge",
      request: {}
    )

    assert_equal "6kq-PYTyXtaGAHTHCVUrc_hIsAwLeskeQFtDZerMYhM", result
  end

  def test_different_realm
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "payments.other.com", method: "tempo", intent: "charge",
      request: {"amount" => "1000000"}
    )

    assert_equal "-gMjd8UeUvBcqUaUzarVj6ikH_YoDowpaNbEwK1Tmx8", result
  end

  def test_different_method
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "stripe", intent: "charge",
      request: {"amount" => "1000000"}
    )

    assert_equal "DRH9ycmIlZ2lYUatIHCrxpm9K7ig5pniZ3ulleb7vl0", result
  end

  def test_different_intent
    result = Mpp.generate_challenge_id(
      secret_key: SECRET, realm: "api.example.com", method: "tempo", intent: "session",
      request: {"amount" => "1000000"}
    )

    assert_equal "INeBi93MhinvbwdUxeUUIaT5Q_ufgLKPYZb5Tg43A1o", result
  end
end

class TestChallengeCreate < Minitest::Test
  def test_creates_challenge_with_hmac_id
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "1000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0x1234567890abcdef1234567890abcdef12345678"
      }
    )

    assert_equal "s0gsoewXwdYI13oPnrtdKTEN4-sIQ-LbQUNV_HttPnA", challenge.id
    assert_equal "tempo", challenge.method
    assert_equal "charge", challenge.intent
  end

  def test_create_with_optional_fields
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "5000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0xabcdef1234567890abcdef1234567890abcdef12"
      },
      expires: "2026-01-29T12:00:00Z",
      description: "Test payment"
    )

    assert_equal "0rMv3trZIudpkJCQxeL2RLQz6uALKTNErWulN07hDLk", challenge.id
    assert_equal "2026-01-29T12:00:00Z", challenge.expires
    assert_equal "Test payment", challenge.description
  end
end

class TestChallengeVerify < Minitest::Test
  def test_verify_valid_challenge
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {
        "amount" => "1000000",
        "currency" => "0x20c0000000000000000000000000000000000000",
        "recipient" => "0x1234567890abcdef1234567890abcdef12345678"
      }
    )

    assert challenge.verify("test-secret-key-12345", "api.example.com")
  end

  def test_verify_invalid_secret
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"}
    )

    refute challenge.verify("wrong-secret", "api.example.com")
  end

  def test_verify_invalid_realm
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"}
    )

    refute challenge.verify("test-secret-key-12345", "wrong.realm.com")
  end

  def test_verify_tampered_challenge
    original = Mpp::Challenge.create(
      secret_key: "test-secret-key-12345",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"}
    )
    tampered = Mpp::Challenge.new(
      id: original.id,
      method: original.method,
      intent: original.intent,
      request: {"amount" => "9999999"}
    )

    refute tampered.verify("test-secret-key-12345", "api.example.com")
  end
end

class TestOpaque < Minitest::Test
  def test_meta_sets_opaque_on_challenge
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"},
      meta: {"pi" => "pi_3abc123XYZ"}
    )

    assert_equal({"pi" => "pi_3abc123XYZ"}, challenge.opaque)
  end

  def test_opaque_is_nil_when_no_meta
    challenge = Mpp::Challenge.create(
      secret_key: "test-secret",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"}
    )

    assert_nil challenge.opaque
  end

  def test_opaque_does_not_affect_challenge_id
    with_meta = Mpp::Challenge.create(
      secret_key: "test-secret",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"},
      meta: {"pi" => "pi_3abc123XYZ"}
    )
    without_meta = Mpp::Challenge.create(
      secret_key: "test-secret",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"}
    )

    assert_equal with_meta.id, without_meta.id
  end

  def test_verify_succeeds_with_opaque
    challenge = Mpp::Challenge.create(
      secret_key: "my-secret",
      realm: "api.example.com",
      method: "tempo",
      intent: "charge",
      request: {"amount" => "1000000"},
      meta: {"pi" => "pi_3abc123XYZ"}
    )

    assert challenge.verify("my-secret", "api.example.com")
  end
end
