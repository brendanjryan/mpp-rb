require "sinatra"
require "json"
require "mpp"

# Per-tool-call micropayments in an MCP context.
# Each tool invocation requires its own payment, verified statelessly.

CHARGE_INTENT = Mpp::Methods::Tempo::ChargeIntent.new
CURRENCY = Mpp::Methods::Tempo::Defaults::PATH_USD
RECIPIENT = "0x0000000000000000000000000000000000000001"

def verify_payment(meta, amount:, description: nil)
  Mpp::Extensions::MCP.verify_or_challenge(
    meta: meta,
    intent: CHARGE_INTENT,
    request: {
      "amount" => Mpp::Units.parse_units(amount, 6).to_s,
      "currency" => CURRENCY,
      "recipient" => RECIPIENT
    },
    realm: "localhost:4567",
    secret_key: "dev-secret-key",
    method: "tempo",
    description: description
  )
end

get "/" do
  content_type :json
  JSON.generate({
    message: "Tempo Session Example (MCP-style per-tool-call payments)",
    endpoints: {
      "POST /tools/translate" => "Translate text ($0.02 per call)",
      "POST /tools/summarize" => "Summarize text ($0.05 per call)"
    }
  })
end

post "/tools/translate" do
  body = JSON.parse(request.body.read)
  meta = body.dig("params", "_meta")

  begin
    result = verify_payment(meta, amount: "0.02", description: "Translation")
  rescue Mpp::Extensions::MCP::PaymentRequiredError => e
    status 402
    content_type :json
    return JSON.generate(e.to_jsonrpc_error)
  rescue Mpp::Extensions::MCP::PaymentVerificationError => e
    status 402
    content_type :json
    return JSON.generate(e.to_jsonrpc_error)
  end

  _credential, receipt = result
  text = body.dig("params", "text") || "Hello, world!"

  content_type :json
  JSON.generate({
    jsonrpc: "2.0",
    result: {
      content: [{type: "text", text: "Translated: #{text.reverse}"}],
      _meta: receipt.to_meta
    }
  })
end

post "/tools/summarize" do
  body = JSON.parse(request.body.read)
  meta = body.dig("params", "_meta")

  begin
    result = verify_payment(meta, amount: "0.05", description: "Summarization")
  rescue Mpp::Extensions::MCP::PaymentRequiredError => e
    status 402
    content_type :json
    return JSON.generate(e.to_jsonrpc_error)
  rescue Mpp::Extensions::MCP::PaymentVerificationError => e
    status 402
    content_type :json
    return JSON.generate(e.to_jsonrpc_error)
  end

  _credential, receipt = result
  text = body.dig("params", "text") || "Some long document..."

  content_type :json
  JSON.generate({
    jsonrpc: "2.0",
    result: {
      content: [{type: "text", text: "Summary: #{text[0, 50]}..."}],
      _meta: receipt.to_meta
    }
  })
end
