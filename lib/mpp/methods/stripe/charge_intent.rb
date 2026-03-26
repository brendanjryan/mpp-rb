# typed: false
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"
require "time"

module Mpp
  module Methods
    module Stripe
      # Server-side charge intent that verifies payment via Stripe PaymentIntents.
      class ChargeIntent
        attr_reader :name

        def initialize(secret_key:, api_base: Defaults::STRIPE_API_BASE)
          @name = "charge"
          @secret_key = secret_key
          @api_base = api_base
        end

        def verify(credential, request)
          # Check challenge expiry
          challenge_expires = credential.challenge.expires
          if challenge_expires
            expires = Time.iso8601(challenge_expires.gsub("Z", "+00:00"))
            raise Mpp::VerificationError, "Request has expired" if expires < Time.now.utc
          end

          payload_data = credential.payload
          unless payload_data.is_a?(Hash) && payload_data.key?("spt")
            raise Mpp::VerificationError, "Invalid credential payload: missing spt"
          end

          spt = payload_data["spt"]
          external_id = payload_data["externalId"]

          # Build PaymentIntent params
          params = {
            "amount" => request["amount"],
            "currency" => request["currency"],
            "shared_payment_granted_token" => spt,
            "confirm" => "true",
            "automatic_payment_methods[enabled]" => "true",
            "automatic_payment_methods[allow_redirects]" => "never"
          }

          # Include metadata from methodDetails if present
          method_details = request["methodDetails"]
          if method_details.is_a?(Hash) && method_details["metadata"].is_a?(Hash)
            method_details["metadata"].each do |k, v|
              params["metadata[#{k}]"] = v.to_s
            end
          end

          # POST to Stripe API
          uri = URI("#{@api_base}/v1/payment_intents")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          req = Net::HTTP::Post.new(uri.path)
          req.basic_auth(@secret_key, "")
          req.set_form_data(params)

          response = http.request(req)

          unless response.is_a?(Net::HTTPSuccess)
            body = begin
              JSON.parse(response.body)
            rescue
              {}
            end
            error_msg = body.dig("error", "message") || "Stripe API error (#{response.code})"
            raise Mpp::VerificationError, error_msg
          end

          result = JSON.parse(response.body)
          pi_id = result["id"]
          status = result["status"]

          if status == "requires_action"
            raise Mpp::PaymentActionRequiredError.new(reason: "PaymentIntent #{pi_id} requires action")
          end

          unless status == "succeeded"
            raise Mpp::VerificationError, "PaymentIntent #{pi_id} has status: #{status}"
          end

          Mpp::Receipt.success(pi_id, method: "stripe", external_id: external_id)
        end
      end
    end
  end
end
