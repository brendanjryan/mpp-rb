# mpp-rb

Ruby SDK for the [**Machine Payments Protocol**](https://mpp.dev)

[![Gem Version](https://img.shields.io/gem/v/mpp.svg)](https://rubygems.org/gems/mpp-rb)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Documentation

Full documentation, API reference, and guides are available at **[mpp.dev/sdk/ruby](https://mpp.dev/sdk/ruby)**.

## Install

```bash
gem install mpp
```

Or add to your Gemfile:

```ruby
gem "mpp"
```

## Quick Start

### Server

```ruby
require "mpp"

server = Mpp.create(
  method: Mpp::Methods::Tempo.tempo(
    intents: {"charge" => Mpp::Methods::Tempo::ChargeIntent.new},
    recipient: "0x742d35Cc6634c0532925a3b844bC9e7595F8fE00",
  ),
)

# In your request handler (Sinatra, Rails, Rack, etc.)
result = server.charge(authorization_header, "0.50", description: "Paid endpoint")

if result.is_a?(Mpp::Challenge)
  # Return 402 with WWW-Authenticate header
  resp = Mpp::Server::Decorator.make_challenge_response(result, server.realm)
  # resp["status"], resp["headers"], resp["body"]
else
  credential, receipt = result
  # credential.source — payer address
  # receipt.to_payment_receipt — Payment-Receipt header value
end
```

### Client

```ruby
require "mpp"

account = Mpp::Methods::Tempo::Account.from_key("0x...")

transport = Mpp::Client::Transport.new(
  methods: [
    Mpp::Methods::Tempo.tempo(
      account: account,
      intents: {"charge" => Mpp::Methods::Tempo::ChargeIntent.new},
    ),
  ],
)

response = transport.request(:get, "https://mpp.dev/api/ping/paid")
```

### Event hooks

Register hooks to observe the automatic payment lifecycle. Each registration returns an unsubscribe proc.

```ruby
server.on_challenge_created do |payload|
  puts "challenge: #{payload[:challenge].id}"
end

server.on_payment_success do |payload|
  puts "paid: #{payload[:receipt].reference}"
end

transport.on_challenge_received do |payload|
  puts "received: #{payload[:challenge].id}"
  nil
end

transport.on_payment_response do |payload|
  puts "retry status: #{payload[:response].code}"
end

transport.on("*") do |event|
  puts "payment event: #{event.name}"
end
```

Client events are `challenge.received`, `credential.created`, `payment.response`, and `payment.failed`. Server events are `challenge.created`, `payment.success`, and `payment.failed`.

### Session Client

```ruby
require "mpp"

manager = Mpp::Methods::Tempo::Session.session_manager(
  account: Mpp::Methods::Tempo::Account.from_key("0x..."),
  deposit: "1.0",
  create_open_transaction: ->(**kwargs) { my_open_transaction_builder(**kwargs) },
)

response = manager.fetch("https://example.com/chat")
```

## Examples

| Example | Description |
|---------|-------------|
| [tempo_charge](./examples/tempo_charge/) | Tempo charge server example |
| [tempo_session](./examples/tempo_session/) | Tempo session server example |
| [stripe_charge](./examples/stripe_charge/) | Stripe charge server example |

## Support Matrix

| Method | Charge Client | Charge Server | Session Client | Session Server |
|--------|---------------|---------------|----------------|----------------|
| Tempo | Yes, implemented in Ruby with `eth` + `rlp` | Yes | Yes, orchestration + voucher signing in Ruby | Yes |
| Stripe | Yes | Yes | No | No |

Tempo charge transaction construction is implemented directly in Ruby. The Tempo-specific dependencies are the `eth` and `rlp` gems.

## Protocol

Built on the ["Payment" HTTP Authentication Scheme](https://datatracker.ietf.org/doc/draft-ryan-httpauth-payment/). See [mpp-specs](https://tempoxyz.github.io/mpp-specs/) for the full specification.

## License

MIT
