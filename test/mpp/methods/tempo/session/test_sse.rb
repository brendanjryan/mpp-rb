# frozen_string_literal: true

require "test_helper"

class TestSse < Minitest::Test
  def setup
    @store = Mpp::Methods::Tempo::Session::MemoryChannelStore.new
  end

  def make_channel(id: "0xabc", deposit: 1_000_000, highest_voucher_amount: 500_000, spent: 0, **overrides)
    Mpp::Methods::Tempo::Session::ChannelState.new(
      channel_id: id,
      chain_id: 4217,
      escrow_contract: "0xescrow",
      payer: "0xpayer",
      payee: "0xpayee",
      token: "0xtoken",
      authorized_signer: "0xsigner",
      deposit: deposit,
      highest_voucher_amount: highest_voucher_amount,
      spent: spent,
      **overrides
    )
  end

  def test_format_message
    result = Mpp::Methods::Tempo::Session::Sse.format_message("hello world")
    assert_equal "event: message\ndata: hello world\n\n", result
  end

  def test_format_need_voucher
    result = Mpp::Methods::Tempo::Session::Sse.format_need_voucher(
      "channelId" => "0xabc",
      "requiredCumulative" => "600000",
      "acceptedCumulative" => "500000",
      "deposit" => "1000000"
    )

    assert result.start_with?("event: payment-need-voucher\ndata: ")
    assert result.end_with?("\n\n")

    parsed = JSON.parse(result.split("data: ", 2)[1].strip)
    assert_equal "0xabc", parsed["channelId"]
    assert_equal "600000", parsed["requiredCumulative"]
  end

  def test_format_receipt
    receipt = Mpp::Methods::Tempo::Session::SessionReceipt.create(
      challenge_id: "ch_1",
      channel_id: "0xabc",
      accepted_cumulative: 500_000,
      spent: 100_000,
      units: 5
    )

    result = Mpp::Methods::Tempo::Session::Sse.format_receipt(receipt)
    assert result.start_with?("event: payment-receipt\ndata: ")
    assert result.end_with?("\n\n")

    parsed = JSON.parse(result.split("data: ", 2)[1].strip)
    assert_equal "success", parsed["status"]
    assert_equal "0xabc", parsed["channelId"]
    assert_equal "500000", parsed["acceptedCumulative"]
  end

  def test_parse_event_message
    raw = "event: message\ndata: hello"
    event = Mpp::Methods::Tempo::Session::Sse.parse_event(raw)

    assert_equal "message", event[:type]
    assert_equal "hello", event[:data]
  end

  def test_parse_event_need_voucher
    data = {"channelId" => "0xabc", "requiredCumulative" => "600000"}
    raw = "event: payment-need-voucher\ndata: #{JSON.generate(data)}"
    event = Mpp::Methods::Tempo::Session::Sse.parse_event(raw)

    assert_equal "payment-need-voucher", event[:type]
    assert_equal "0xabc", event[:data]["channelId"]
  end

  def test_parse_event_receipt
    data = {"method" => "tempo", "status" => "success", "channelId" => "0xabc"}
    raw = "event: payment-receipt\ndata: #{JSON.generate(data)}"
    event = Mpp::Methods::Tempo::Session::Sse.parse_event(raw)

    assert_equal "payment-receipt", event[:type]
    assert_equal "tempo", event[:data]["method"]
  end

  def test_parse_event_returns_nil_for_empty
    assert_nil Mpp::Methods::Tempo::Session::Sse.parse_event("")
    assert_nil Mpp::Methods::Tempo::Session::Sse.parse_event("event: message")
  end

  def test_parse_event_default_type_is_message
    raw = "data: hello"
    event = Mpp::Methods::Tempo::Session::Sse.parse_event(raw)

    assert_equal "message", event[:type]
    assert_equal "hello", event[:data]
  end

  def test_deduct_from_channel_success
    channel = make_channel(highest_voucher_amount: 500_000, spent: 0)
    @store.update_channel("0xabc") { |_| channel }

    result = Mpp::Methods::Tempo::Session.deduct_from_channel(@store, "0xabc", 100_000)

    assert result[:ok]
    assert_equal 100_000, result[:channel].spent
    assert_equal 1, result[:channel].units
  end

  def test_deduct_from_channel_insufficient
    channel = make_channel(highest_voucher_amount: 500_000, spent: 500_000)
    @store.update_channel("0xabc") { |_| channel }

    result = Mpp::Methods::Tempo::Session.deduct_from_channel(@store, "0xabc", 100_000)

    refute result[:ok]
    assert_equal 500_000, result[:channel].spent
  end

  def test_serve_yields_messages_and_receipt
    channel = make_channel(highest_voucher_amount: 500_000, spent: 0)
    @store.update_channel("0xabc") { |_| channel }

    events = []
    enumerator = Mpp::Methods::Tempo::Session::Sse.serve(
      store: @store,
      channel_id: "0xabc",
      tick_cost: 100_000,
      challenge_id: "ch_1"
    ) { %w[hello world] }

    enumerator.each { |event| events << event }

    messages = events.select { |e| e.start_with?("event: message") }
    receipts = events.select { |e| e.start_with?("event: payment-receipt") }

    assert_equal 2, messages.length
    assert_equal 1, receipts.length
    assert_includes messages[0], "hello"
    assert_includes messages[1], "world"
  end

  def test_serve_emits_need_voucher_when_exhausted
    # Only enough balance for 1 tick
    channel = make_channel(highest_voucher_amount: 100_000, spent: 0)
    @store.update_channel("0xabc") { |_| channel }

    events = []
    enumerator = Mpp::Methods::Tempo::Session::Sse.serve(
      store: @store,
      channel_id: "0xabc",
      tick_cost: 100_000,
      challenge_id: "ch_1",
      poll_interval: 0.01
    ) { %w[first second] }

    # Run in a thread so we can top up from outside
    collector = Thread.new do
      enumerator.each { |event| events << event }
    end

    # Wait for need-voucher to be emitted
    sleep(0.1)

    # Top up the channel by increasing highest_voucher_amount
    @store.update_channel("0xabc") do |current|
      current.with(highest_voucher_amount: 300_000)
    end

    collector.join(5)

    need_voucher = events.select { |e| e.start_with?("event: payment-need-voucher") }
    assert_operator need_voucher.length, :>=, 1
  end
end
