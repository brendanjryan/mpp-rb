# frozen_string_literal: true

module Mpp
  BASE_URI = "https://paymentauth.org/problems"

  # Parse error for malformed payment headers.
  class ParseError < StandardError; end

  # Base verification error.
  class VerificationError < StandardError; end

  # Base class for all payment-related errors with RFC 9457 support.
  class PaymentError < StandardError
    def self.inherited(subclass)
      super
      return if subclass.instance_variable_defined?(:@_mpp_configured)

      subclass.instance_variable_set(:@_mpp_configured, true)
      name = subclass.name&.split("::")&.last || "PaymentError"
      unless subclass.instance_variable_defined?(:@type)
        subclass.instance_variable_set(:@type,
                                       "#{BASE_URI}/#{to_slug(name)}")
      end
      subclass.instance_variable_set(:@title, to_title(name)) unless subclass.instance_variable_defined?(:@title)
      subclass.instance_variable_set(:@status, 402) unless subclass.instance_variable_defined?(:@status)
    end

    class << self
      attr_reader :status, :type, :title

      private

      def to_slug(name)
        name.sub(/Error$/, "").gsub(/(?<=[a-z0-9])(?=[A-Z])/, "-").downcase
      end

      def to_title(name)
        name.sub(/Error$/, "").gsub(/(?<=[a-z0-9])(?=[A-Z])/, " ")
      end
    end

    @status = 402
    @type = "#{BASE_URI}/payment-error"
    @title = "Payment Error"

    def status = self.class.status
    def type = self.class.type
    def title = self.class.title

    # Convert to RFC 9457 Problem Details format.
    def to_problem_details(challenge_id: nil)
      details = {
        "type" => type,
        "title" => title,
        "status" => status,
        "detail" => message
      }
      details["challengeId"] = challenge_id if challenge_id
      details
    end
  end

  class PaymentRequiredError < PaymentError
    def initialize(realm: nil, description: nil)
      parts = ["Payment is required"]
      parts << "for \"#{realm}\"" if realm
      parts << "(#{description})" if description
      super("#{parts.join(" ")}.")
    end
  end

  class MalformedCredentialError < PaymentError
    def initialize(reason: nil)
      msg = reason ? "Credential is malformed: #{reason}." : "Credential is malformed."
      super(msg)
    end
  end

  class InvalidChallengeError < PaymentError
    def initialize(challenge_id: nil, reason: nil)
      id_part = challenge_id ? " \"#{challenge_id}\"" : ""
      reason_part = reason ? ": #{reason}" : ""
      super("Challenge#{id_part} is invalid#{reason_part}.")
    end
  end

  class VerificationFailedError < PaymentError
    def initialize(reason: nil)
      msg = reason ? "Payment verification failed: #{reason}." : "Payment verification failed."
      super(msg)
    end
  end

  class PaymentExpiredError < PaymentError
    def initialize(expires: nil)
      msg = expires ? "Payment expired at #{expires}." : "Payment has expired."
      super(msg)
    end
  end

  class InvalidPayloadError < PaymentError
    def initialize(reason: nil)
      msg = reason ? "Credential payload is invalid: #{reason}." : "Credential payload is invalid."
      super(msg)
    end
  end

  class BadRequestError < PaymentError
    @status = 400

    def initialize(reason: nil)
      msg = reason ? "Bad request: #{reason}." : "Bad request."
      super(msg)
    end
  end

  class PaymentInsufficientError < PaymentError
    def initialize(reason: nil)
      msg = reason ? "Payment insufficient: #{reason}." : "Payment amount is insufficient."
      super(msg)
    end
  end

  class PaymentMethodUnsupportedError < PaymentError
    @status = 400
    @type = "#{BASE_URI}/method-unsupported"
    @title = "Method Unsupported"

    def initialize(method: nil)
      msg = method ? "Payment method \"#{method}\" is not supported." : "Payment method is not supported."
      super(msg)
    end
  end

  class PaymentActionRequiredError < PaymentError
    def initialize(reason: nil)
      msg = reason ? "Payment requires action: #{reason}." : "Payment requires action."
      super(msg)
    end
  end
end
