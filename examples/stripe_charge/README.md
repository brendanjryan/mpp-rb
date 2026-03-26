# Stripe Charge Example

One-shot payments via Stripe Shared Payment Tokens (SPTs) using the MPP charge flow.

## Setup

```sh
cd examples/stripe_charge
bundle install

# Edit app.rb and set STRIPE_SECRET_KEY and STRIPE_NETWORK_ID
ruby app.rb
```

## Usage

```sh
curl -i http://localhost:4567/
curl -i http://localhost:4567/weather
```
