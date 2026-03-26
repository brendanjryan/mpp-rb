# frozen_string_literal: true

module Mpp
  module Extensions
    module MCP
      module_function

      # Wrapper for MCP tool handlers with payment verification.
      #
      # Usage:
      #   result = Mpp::Extensions::MCP.pay(mpp_handler, meta: params["_meta"],
      #     request: { "amount" => "1000" }, realm: "api.example.com") do |credential, receipt|
      #     # execute tool
      #   end
      def pay_tool(intent:, request:, meta:, realm: nil, secret_key: nil,
                   method: nil, expires_in: DEFAULT_CHALLENGE_TTL, description: nil)
        resolved_realm = realm || Mpp::Server::Defaults.detect_realm
        resolved_secret_key = secret_key || Mpp::Server::Defaults.detect_secret_key

        request_params = request.respond_to?(:call) ? request.call : request

        result = verify_or_challenge(
          meta: meta,
          intent: intent,
          request: request_params,
          realm: resolved_realm,
          secret_key: resolved_secret_key,
          method: method,
          expires_in: expires_in,
          description: description
        )

        raise PaymentRequiredError.new(challenges: [result]) if result.is_a?(MCPChallenge)

        credential, receipt = result
        yield credential, receipt
      end
    end
  end
end
