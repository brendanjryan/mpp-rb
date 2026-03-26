# frozen_string_literal: true

module Mpp
  module Extensions
    module MCP
      class PaymentRequiredError < StandardError
        attr_reader :challenges, :code

        def initialize(challenges:, message: "Payment Required")
          @challenges = challenges
          @code = CODE_PAYMENT_REQUIRED
          super(message)
        end

        def to_jsonrpc_error
          {
            "code" => CODE_PAYMENT_REQUIRED,
            "message" => message,
            "data" => {
              "httpStatus" => HTTP_STATUS_PAYMENT_REQUIRED,
              "challenges" => @challenges.map(&:to_dict)
            }
          }
        end
      end

      class PaymentVerificationError < StandardError
        attr_reader :challenges, :reason, :detail, :code

        def initialize(challenges:, reason: nil, detail: nil, message: "Payment Verification Failed")
          @challenges = challenges
          @reason = reason
          @detail = detail
          @code = CODE_PAYMENT_VERIFICATION_FAILED
          super(message)
        end

        def to_jsonrpc_error
          data = {
            "httpStatus" => HTTP_STATUS_PAYMENT_REQUIRED,
            "challenges" => @challenges.map(&:to_dict)
          }
          if @reason || @detail
            failure = {}
            failure["reason"] = @reason if @reason
            failure["detail"] = @detail if @detail
            data["failure"] = failure
          end
          {
            "code" => CODE_PAYMENT_VERIFICATION_FAILED,
            "message" => message,
            "data" => data
          }
        end
      end

      class MalformedCredentialError < StandardError
        attr_reader :detail, :code

        def initialize(detail:, message: "Invalid params")
          @detail = detail
          @code = CODE_MALFORMED_CREDENTIAL
          super(message)
        end

        def to_jsonrpc_error
          {
            "code" => CODE_MALFORMED_CREDENTIAL,
            "message" => message,
            "data" => {
              "httpStatus" => HTTP_STATUS_PAYMENT_REQUIRED,
              "detail" => @detail
            }
          }
        end
      end
    end
  end
end
