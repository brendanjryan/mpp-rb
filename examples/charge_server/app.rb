require "sinatra"
require "json"
require "mpp"

DESTINATION = ENV.fetch("PAYMENT_DESTINATION", "0x0000000000000000000000000000000000000001")

server = Mpp.create(
  method: Mpp::Methods::Tempo.tempo(
    chain_id: Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID,
    currency: Mpp::Methods::Tempo::Defaults::PATH_USD,
    recipient: DESTINATION,
    intents: {"charge" => Mpp::Methods::Tempo::ChargeIntent.new}
  ),
  realm: ENV.fetch("MPP_REALM", "localhost:4567"),
  secret_key: ENV.fetch("MPP_SECRET_KEY", "dev-secret-key")
)

get "/" do
  content_type :json
  JSON.generate({
    message: "MPP Example Server",
    endpoints: {
      "GET /weather" => "Paid endpoint ($0.01) — returns weather data"
    }
  })
end

get "/weather" do
  result = server.charge(env["HTTP_AUTHORIZATION"], "0.01", description: "Weather forecast")

  if result.is_a?(Mpp::Challenge)
    resp = Mpp::Server::Decorator.make_challenge_response(result, server.realm)
    status resp["status"]
    headers resp["headers"]
    body resp["body"]
    return
  end

  _credential, receipt = result
  headers "Payment-Receipt" => receipt.to_payment_receipt
  content_type :json
  JSON.generate({
    forecast: "Sunny, 72°F",
    location: "San Francisco, CA",
    paid: true
  })
end
