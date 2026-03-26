require "sinatra"
require "json"
require "mpp"

STRIPE_SECRET_KEY = ENV.fetch("STRIPE_SECRET_KEY")
STRIPE_NETWORK_ID = ENV.fetch("STRIPE_NETWORK_ID")

server = Mpp.create(
  method: Mpp::Methods::Stripe.stripe(
    secret_key: STRIPE_SECRET_KEY,
    network_id: STRIPE_NETWORK_ID,
    currency: "usd",
    payment_methods: ["card"],
    metadata: {"app" => "mpp-example"}
  ),
  realm: "localhost:4567",
  secret_key: "dev-secret-key"
)

get "/" do
  content_type :json
  JSON.generate({
    message: "Stripe Charge Example",
    payment_method: "stripe",
    currency: "usd",
    endpoints: {
      "GET /weather" => "Weather forecast ($0.10)",
      "GET /premium" => "Premium content ($1.00)"
    }
  })
end

get "/weather" do
  result = server.charge(env["HTTP_AUTHORIZATION"], "0.10",
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

get "/premium" do
  result = server.charge(env["HTTP_AUTHORIZATION"], "1.00",
    description: "Premium content")

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
    title: "The Definitive Guide to Payment Authentication",
    content: "HTTP 402 was reserved in 1997 for future use..."
  })
end
