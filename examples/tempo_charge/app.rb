require "sinatra"
require "json"
require "mpp"

server = Mpp.create(
  method: Mpp::Methods::Tempo.tempo(
    chain_id: Mpp::Methods::Tempo::Defaults::TESTNET_CHAIN_ID,
    currency: Mpp::Methods::Tempo::Defaults::PATH_USD,
    recipient: "0x0000000000000000000000000000000000000001",
    intents: {"charge" => Mpp::Methods::Tempo::ChargeIntent.new}
  ),
  realm: "localhost:4567",
  secret_key: "dev-secret-key"
)

get "/" do
  content_type :json
  JSON.generate({
    message: "Tempo Charge Example",
    chain: "Tempo Moderato (testnet)",
    endpoints: {
      "GET /weather" => "Weather forecast ($0.01)",
      "GET /joke" => "Random joke ($0.005)"
    }
  })
end

get "/weather" do
  result = server.charge(env["HTTP_AUTHORIZATION"], "0.01",
    description: "Weather forecast")

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
  JSON.generate({forecast: "Sunny, 72°F", location: "San Francisco, CA"})
end

get "/joke" do
  result = server.charge(env["HTTP_AUTHORIZATION"], "0.005",
    description: "Random joke")

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
  JSON.generate({joke: "Why do programmers prefer dark mode? Because light attracts bugs."})
end
