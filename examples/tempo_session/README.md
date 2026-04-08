# Tempo Session Example

Payment channels (sessions) with cumulative vouchers over HTTP, including SSE streaming with per-token metering.

## Setup

```sh
cd examples/tempo_session
bundle install
ruby app.rb
```

## Endpoints

| Route | Description |
|-------|-------------|
| `GET /` | Service info |
| `POST /session` | Channel management (open/voucher/topUp/close) |
| `GET /weather` | One-shot session-paid endpoint ($0.01) |
| `GET /chat` | SSE streaming with per-token charges ($0.001/token) |

## How it works

1. **Open a channel** — Client sends a `POST /session` with an `open` credential containing a signed escrow transaction and initial voucher.

2. **Send vouchers** — For each paid request, the client includes a `voucher` credential with a higher cumulative amount. The server verifies the EIP-712 signature and deducts from the channel balance.

3. **SSE streaming** — `GET /chat` returns a `text/event-stream` that meters each emitted token against the channel balance. When balance runs low, the server emits `payment-need-voucher`; the client tops up by sending a new voucher to any session endpoint.

4. **Close** — Client sends a `close` credential with a final voucher. The server settles on-chain and marks the channel finalized.

## Usage

```sh
# Get service info
curl -i http://localhost:4567/

# First request without auth — returns 402 with challenge
curl -i http://localhost:4567/weather

# POST to session endpoint — returns 402 with session challenge
curl -i -X POST http://localhost:4567/session
```

In production, clients use the mppx SDK which handles the challenge-response flow, channel opening, and voucher signing automatically.

`mpp-rb` now includes a Ruby session manager for the same orchestration flow. Voucher signing is built in; open/top-up transaction construction still uses application-supplied callbacks.
