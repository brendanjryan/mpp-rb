# MPP Charge Server Example

A minimal Sinatra app demonstrating the MPP charge flow.

## Setup

```sh
cd examples/charge_server
bundle install
ruby app.rb
```

## Usage

```sh
# Health check
curl -i http://localhost:4567/

# Paid endpoint — returns 402 with WWW-Authenticate challenge
curl -i http://localhost:4567/weather
```

## Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `MPP_SECRET_KEY` | `dev-secret-key` | HMAC secret for challenge signing |
| `MPP_REALM` | `localhost:4567` | Server realm for challenges |
| `PAYMENT_DESTINATION` | `0x000...0001` | Recipient address for payments |
