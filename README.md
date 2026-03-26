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

account = Mpp::Methods::Tempo::TempoAccount.from_key("0x...")

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

## Examples

| Example | Description |
|---------|-------------|
| [charge-server](./examples/charge_server/) | Payment-gated Sinatra API server |

## Protocol

Built on the ["Payment" HTTP Authentication Scheme](https://datatracker.ietf.org/doc/draft-ryan-httpauth-payment/). See [mpp-specs](https://tempoxyz.github.io/mpp-specs/) for the full specification.

## License

MIT
