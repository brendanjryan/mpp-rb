# Tempo Session Example

Per-tool-call Tempo micropayments in an MCP context. Each tool invocation is independently paid using `Mpp::Extensions::MCP`.

## Setup

```sh
cd examples/tempo_session
bundle install
ruby app.rb
```

## Usage

```sh
# Returns 402 with JSON-RPC -32042 error containing the challenge
curl -X POST http://localhost:4567/tools/translate \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"translate","text":"hello"}}'
```
