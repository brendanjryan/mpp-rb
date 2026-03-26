# frozen_string_literal: true

require "openssl"

module Mpp
  module_function

  # Timing-safe string comparison to prevent timing attacks.
  # Falls back to OpenSSL.fixed_length_secure_compare when lengths match,
  # otherwise uses double-HMAC comparison for variable-length safety.
  def secure_compare(a, b)
    return false if a.nil? || b.nil?

    a_bytes = a.encode(Encoding::UTF_8)
    b_bytes = b.encode(Encoding::UTF_8)

    return false unless a_bytes.bytesize == b_bytes.bytesize

    OpenSSL.fixed_length_secure_compare(a_bytes, b_bytes)
  end
end
