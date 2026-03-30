# typed: false
# frozen_string_literal: true

require "json"

module Mpp
  module Methods
    module Tempo
      module Session
        module Sse
          module_function

          # Format a session receipt as a Server-Sent Event.
          def format_receipt(receipt)
            data = if receipt.respond_to?(:serialize)
              # SessionReceipt — serialize to JSON
              json = {
                "method" => receipt.method,
                "intent" => receipt.intent,
                "status" => receipt.status,
                "timestamp" => receipt.timestamp,
                "reference" => receipt.reference,
                "challengeId" => receipt.challenge_id,
                "channelId" => receipt.channel_id,
                "acceptedCumulative" => receipt.accepted_cumulative,
                "spent" => receipt.spent
              }
              json["units"] = receipt.units unless receipt.units.nil?
              json["txHash"] = receipt.tx_hash unless receipt.tx_hash.nil?
              JSON.generate(json)
            else
              JSON.generate(receipt)
            end
            "event: payment-receipt\ndata: #{data}\n\n"
          end

          # Format a need-voucher event as a Server-Sent Event.
          def format_need_voucher(params)
            "event: payment-need-voucher\ndata: #{JSON.generate(params)}\n\n"
          end

          # Format a message event as a Server-Sent Event.
          def format_message(data)
            "event: message\ndata: #{data}\n\n"
          end

          # Parse a raw SSE event string into a typed hash.
          # Returns { type:, data: } or nil.
          def parse_event(raw)
            event_type = "message"
            data_lines = []

            raw.split("\n").each do |line|
              if line.start_with?("event: ")
                event_type = line[7..].strip
              elsif line.start_with?("data: ")
                data_lines << line[6..]
              elsif line == "data:"
                data_lines << ""
              end
            end

            return nil if data_lines.empty?
            data = data_lines.join("\n")

            case event_type
            when "message"
              {type: "message", data: data}
            when "payment-need-voucher"
              {type: "payment-need-voucher", data: JSON.parse(data)}
            when "payment-receipt"
              {type: "payment-receipt", data: JSON.parse(data)}
            else
              {type: "message", data: data}
            end
          end

          # Streaming metering loop — returns an Enumerator that yields SSE-formatted strings.
          #
          # For each value yielded by the generate block:
          # 1. Deducts tick_cost from the channel balance atomically
          # 2. If balance sufficient, yields "event: message\ndata: {value}\n\n"
          # 3. If balance exhausted, yields "event: payment-need-voucher" and
          #    polls store until the client tops up
          # 4. On completion, yields a final "event: payment-receipt"
          #
          # Compatible with Rack streaming responses.
          def serve(store:, channel_id:, tick_cost:, challenge_id:, poll_interval: 0.1, &generate)
            raise ArgumentError, "block required" unless generate

            Enumerator.new do |yielder|
              generate.call.each do |value|
                # Charge or wait for top-up
                charge_or_wait(
                  store: store,
                  channel_id: channel_id,
                  amount: tick_cost,
                  yielder: yielder,
                  poll_interval: poll_interval
                )

                yielder << format_message(value)
              end

              # Emit final receipt
              channel = store.get_channel(channel_id)
              if channel
                receipt = SessionReceipt.create(
                  challenge_id: challenge_id,
                  channel_id: channel_id,
                  accepted_cumulative: channel.highest_voucher_amount,
                  spent: channel.spent,
                  units: channel.units
                )
                yielder << format_receipt(receipt)
              end
            end
          end

          # Atomically deduct amount from a channel, retrying when balance is
          # insufficient. Emits payment-need-voucher events via yielder while waiting.
          def charge_or_wait(store:, channel_id:, amount:, yielder:, poll_interval: 0.1)
            result = Session.deduct_from_channel(store, channel_id, amount)

            unless result[:ok]
              # Emit a single need-voucher event
              channel = result[:channel]
              yielder << format_need_voucher(
                "channelId" => channel_id,
                "requiredCumulative" => (channel.spent + amount).to_s,
                "acceptedCumulative" => channel.highest_voucher_amount.to_s,
                "deposit" => channel.deposit.to_s
              )

              # Poll/wait until client sends updated voucher
              until result[:ok]
                if store.respond_to?(:wait_for_update)
                  store.wait_for_update(channel_id, timeout: poll_interval)
                else
                  sleep(poll_interval)
                end
                result = Session.deduct_from_channel(store, channel_id, amount)
              end
            end
          end
        end
      end
    end
  end
end
