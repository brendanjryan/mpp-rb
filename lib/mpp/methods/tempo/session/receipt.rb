# typed: false
# frozen_string_literal: true

require "json"
require "base64"
require "time"

module Mpp
  module Methods
    module Tempo
      module Session
        SessionReceipt = Data.define(
          :status, :timestamp, :reference, :method, :intent,
          :challenge_id, :channel_id, :accepted_cumulative, :spent,
          :units, :tx_hash
        ) do
          def initialize(
            status: "success",
            timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ"),
            reference: nil,
            method: "tempo",
            intent: "session",
            challenge_id: nil,
            channel_id: nil,
            accepted_cumulative: nil,
            spent: nil,
            units: nil,
            tx_hash: nil
          )
            super
          end

          def self.create(challenge_id:, channel_id:, accepted_cumulative:, spent:, units: nil, tx_hash: nil)
            new(
              reference: channel_id,
              challenge_id: challenge_id,
              channel_id: channel_id,
              accepted_cumulative: accepted_cumulative.to_s,
              spent: spent.to_s,
              units: units,
              tx_hash: tx_hash
            )
          end

          # Serialize to base64url-encoded JSON for Payment-Receipt header.
          def serialize
            method_name = method # Data.define member, not Object#method
            data = {
              "method" => method_name,
              "intent" => intent,
              "status" => status,
              "timestamp" => timestamp,
              "reference" => reference,
              "challengeId" => challenge_id,
              "channelId" => channel_id,
              "acceptedCumulative" => accepted_cumulative,
              "spent" => spent
            }
            data["units"] = units unless units.nil?
            data["txHash"] = tx_hash unless tx_hash.nil?
            Base64.urlsafe_encode64(JSON.generate(data), padding: false)
          end

          # Deserialize from base64url-encoded JSON.
          def self.deserialize(encoded)
            json = Base64.urlsafe_decode64(encoded)
            data = JSON.parse(json)
            new(
              method: data["method"],
              intent: data["intent"],
              status: data["status"],
              timestamp: data["timestamp"],
              reference: data["reference"],
              challenge_id: data["challengeId"],
              channel_id: data["channelId"],
              accepted_cumulative: data["acceptedCumulative"],
              spent: data["spent"],
              units: data["units"],
              tx_hash: data["txHash"]
            )
          end

          # Format as Payment-Receipt header value (compatible with Receipt).
          def to_payment_receipt
            Mpp::Parsing.format_payment_receipt(self)
          end
        end
      end
    end
  end
end
