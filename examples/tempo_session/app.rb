require "sinatra"
require "json"
require "mpp"

Session = Mpp::Methods::Tempo::Session

# Create a shared channel store so state persists across requests.
store = Session::MemoryChannelStore.new

session_intent = Session::SessionIntent.new(
  chain_id: Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID,
  escrow_contract: Mpp::Methods::Tempo::Defaults.escrow_contract_for_chain(
    Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID
  ),
  store: store,
  min_voucher_delta: 0,
  channel_state_ttl: 5000
)

# Build a minimal method object with a session intent.
method = Struct.new(:name, :intents, :currency, :recipient, :decimals, :chain_id).new(
  "tempo",
  {"session" => session_intent},
  Mpp::Methods::Tempo::Defaults::PATH_USD,
  ENV.fetch("RECIPIENT", "0x0000000000000000000000000000000000000001"),
  6,
  Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID
)

server = Mpp::Server::MppHandler.new(
  method: method,
  realm: "localhost:4567",
  secret_key: ENV.fetch("SECRET_KEY", "dev-secret-key-for-session-example!")
)

# Helper to handle the challenge/receipt flow.
def handle_session(server, request, amount, description: nil)
  result = server.session(
    request.env["HTTP_AUTHORIZATION"],
    amount,
    description: description
  )

  if result.is_a?(Mpp::Challenge)
    resp = Mpp::Server::Decorator.make_challenge_response(result, server.realm)
    halt resp["status"].to_i, resp["headers"], resp["body"]
  end

  _credential, receipt = result
  headers "Payment-Receipt" => receipt.serialize
  receipt
end

# --- Routes ---

get "/" do
  content_type :json
  JSON.generate({
    message: "Tempo Session Example",
    chain: "Tempo Moderato (testnet)",
    endpoints: {
      "POST /session" => "Open/voucher/topUp/close a session channel",
      "GET /chat" => "SSE streaming chat ($0.001 per token)"
    }
  })
end

# Generic session endpoint — clients send open/voucher/topUp/close credentials here.
post "/session" do
  handle_session(server, request, "0.01", description: "Session operation")
  status 204
end

# One-shot session-paid endpoint — each request costs one voucher tick.
get "/weather" do
  handle_session(server, request, "0.01", description: "Weather forecast")

  content_type :json
  JSON.generate({forecast: "Sunny, 72°F", location: "San Francisco, CA"})
end

# SSE streaming endpoint — charges per token emitted.
get "/chat" do
  result = server.session(
    request.env["HTTP_AUTHORIZATION"],
    "0.001",
    description: "Chat token"
  )

  if result.is_a?(Mpp::Challenge)
    resp = Mpp::Server::Decorator.make_challenge_response(result, server.realm)
    halt resp["status"].to_i, resp["headers"], resp["body"]
  end

  credential, _receipt = result

  # Extract channel context from the credential for SSE metering.
  channel_id = credential.payload["channelId"]
  challenge_id = credential.challenge.id

  # Parse tick cost from the challenge request amount.
  tick_cost = Integer(credential.challenge.request["amount"] || "1000")

  content_type "text/event-stream"
  headers "Cache-Control" => "no-cache"

  # Simulate an LLM streaming response.
  tokens = [
    "The", " weather", " today", " is", " sunny",
    " with", " a", " high", " of", " 72°F",
    " and", " clear", " skies", " throughout",
    " the", " afternoon", "."
  ]

  stream do |out|
    enumerator = Session::Sse.serve(
      store: store,
      channel_id: channel_id,
      tick_cost: tick_cost,
      challenge_id: challenge_id,
      poll_interval: 0.1
    ) { tokens }

    enumerator.each do |event|
      out << event
    rescue IOError
      break
    end
  end
end
