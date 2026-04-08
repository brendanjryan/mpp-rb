# typed: false
# frozen_string_literal: true

require "net/http"
require "uri"

module Mpp
  module Methods
    module Tempo
      module Session
        class SessionManager
          attr_reader :method, :last_challenge

          def initialize(account:, authorized_signer: nil, chain_id: nil, escrow_contract: nil,
            deposit: nil, decimals: 6, create_open_transaction: nil,
            create_top_up_transaction: nil, requester: nil, on_channel_update: nil)
            @method = ClientMethod.new(
              account: account,
              authorized_signer: authorized_signer,
              chain_id: chain_id,
              escrow_contract: escrow_contract,
              deposit: deposit,
              decimals: decimals,
              create_open_transaction: create_open_transaction,
              create_top_up_transaction: create_top_up_transaction,
              on_channel_update: on_channel_update
            )
            @requester = requester || lambda { |url, method:, headers:, body:|
              default_request(url, method: method, headers: headers, body: body)
            }
            @last_challenge = nil
            @last_url = nil
          end

          def channel_id
            @method.channel_id
          end

          def cumulative
            @method.cumulative_amount
          end

          def opened?
            @method.opened?
          end

          def open(url = nil, deposit_raw: nil, transaction: nil, headers: {})
            challenge = @last_challenge
            raise ArgumentError, "No session challenge available" unless challenge

            target = url || @last_url
            raise ArgumentError, "No URL available for session open" unless target

            prepared = @method.prepare_credential(
              challenge,
              context: {
                action: "open",
                deposit_raw: deposit_raw,
                transaction: transaction
              }
            )

            response = perform_request(
              target,
              method: "POST",
              headers: headers.merge("Authorization" => prepared.credential.to_authorization)
            )
            commit_if_success(prepared, response)
            response
          end

          def fetch(url, method: "GET", headers: {}, body: nil)
            @last_url = url
            initial = perform_request(url, method: method, headers: headers, body: body)
            return initial unless initial.code.to_i == 402

            challenge = find_session_challenge(initial)
            return initial unless challenge

            @last_challenge = challenge
            prepared = @method.prepare_credential(challenge)
            retry_headers = headers.merge("Authorization" => prepared.credential.to_authorization)
            response = perform_request(url, method: method, headers: retry_headers, body: body)
            commit_if_success(prepared, response)
            response
          end

          def sse(url, method: "GET", headers: {}, body: nil, on_receipt: nil)
            @last_url = url
            sse_headers = headers.merge("Accept" => "text/event-stream")
            initial = perform_request(url, method: method, headers: sse_headers, body: body)

            challenge = nil
            auth_headers = sse_headers
            if initial.code.to_i == 402
              challenge = find_session_challenge(initial)
              return empty_enum unless challenge

              @last_challenge = challenge
              prepared = @method.prepare_credential(challenge)
              auth_headers = sse_headers.merge("Authorization" => prepared.credential.to_authorization)
              initial = nil
            end

            Enumerator.new do |yielder|
              stream_request(url, method: method, headers: auth_headers, body: body) do |response|
                if challenge
                  commit_if_success(prepared, response)
                elsif response.code.to_i >= 400
                  raise "SSE request failed with status #{response.code}"
                end

                buffer = +""
                response.read_body do |chunk|
                  buffer << chunk
                  parts = buffer.split("\n\n")
                  buffer = parts.pop.to_s

                  parts.each do |part|
                    next if part.strip.empty?

                    event = Sse.parse_event(part)
                    next unless event

                    case event[:type]
                    when "message"
                      yielder << event[:data]
                    when "payment-receipt"
                      receipt = parse_session_receipt(event[:data])
                      @method.commit(PreparedCredential.new(credential: nil, action: "voucher", channel: @method.channel), receipt: receipt) if @method.channel
                      on_receipt&.call(receipt)
                    when "payment-need-voucher"
                      send_voucher(url, event[:data], headers: headers)
                    end
                  end
                end
              end
            end
          end

          def close(url = nil, headers: {})
            return nil unless opened?

            challenge = @last_challenge
            raise ArgumentError, "No session challenge available" unless challenge

            target = url || @last_url
            raise ArgumentError, "No URL available for session close" unless target

            prepared = @method.prepare_credential(challenge, context: {action: "close"})
            response = perform_request(
              target,
              method: "POST",
              headers: headers.merge("Authorization" => prepared.credential.to_authorization)
            )
            receipt = parse_response_receipt(response)
            commit_if_success(prepared, response, receipt: receipt)
            receipt
          end

          private

          def send_voucher(url, event_data, headers: {})
            challenge = @last_challenge
            return unless challenge

            prepared = @method.prepare_credential(
              challenge,
              context: {
                action: "voucher",
                channel_id: event_data["channelId"],
                cumulative_amount_raw: event_data["requiredCumulative"]
              }
            )
            response = perform_request(
              url,
              method: "POST",
              headers: headers.merge("Authorization" => prepared.credential.to_authorization)
            )
            receipt = parse_response_receipt(response)
            commit_if_success(prepared, response, receipt: receipt)
            receipt
          end

          def commit_if_success(prepared, response, receipt: nil)
            return unless response.code.to_i < 400

            @method.commit(prepared, receipt: receipt || parse_response_receipt(response))
          end

          def parse_response_receipt(response)
            header = response["Payment-Receipt"]
            return nil unless header && !header.empty?

            parse_session_receipt(header)
          end

          def parse_session_receipt(value)
            return SessionReceipt.deserialize(value) if value.is_a?(String)

            SessionReceipt.new(
              status: value.fetch("status", "success"),
              timestamp: value["timestamp"],
              reference: value["reference"],
              method: value.fetch("method", "tempo"),
              intent: value.fetch("intent", "session"),
              challenge_id: value["challengeId"],
              channel_id: value["channelId"],
              accepted_cumulative: value["acceptedCumulative"],
              spent: value["spent"],
              units: value["units"],
              tx_hash: value["txHash"]
            )
          end

          def find_session_challenge(response)
            headers = response.get_fields("www-authenticate") || []
            headers.each do |header|
              next unless header.downcase.start_with?("payment ")

              begin
                challenge = Mpp::Challenge.from_www_authenticate(header)
                return challenge if challenge.method == "tempo" && challenge.intent == "session"
              rescue Mpp::ParseError
                next
              end
            end
            nil
          end

          def empty_enum
            Enumerator.new { |_yielder| }
          end

          def perform_request(url, method:, headers:, body: nil)
            @requester.call(url, method: method, headers: headers, body: body)
          end

          def default_request(url, method:, headers:, body: nil)
            uri = URI(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"

            request_class = case method.to_s.upcase
            when "GET" then Net::HTTP::Get
            when "POST" then Net::HTTP::Post
            when "PUT" then Net::HTTP::Put
            when "DELETE" then Net::HTTP::Delete
            else
              raise ArgumentError, "Unsupported HTTP method: #{method}"
            end

            request = request_class.new(uri)
            headers.each { |key, value| request[key] = value }
            request.body = body if body
            http.request(request)
          end

          def stream_request(url, method:, headers:, body: nil, &block)
            uri = URI(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"

            request_class = case method.to_s.upcase
            when "GET" then Net::HTTP::Get
            when "POST" then Net::HTTP::Post
            when "PUT" then Net::HTTP::Put
            when "DELETE" then Net::HTTP::Delete
            else
              raise ArgumentError, "Unsupported HTTP method: #{method}"
            end

            request = request_class.new(uri)
            headers.each { |key, value| request[key] = value }
            request.body = body if body

            http.request(request, &block)
          end
        end
      end
    end
  end
end
