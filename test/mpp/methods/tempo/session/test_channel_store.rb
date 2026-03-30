# frozen_string_literal: true

require "test_helper"

class TestChannelStore < Minitest::Test
  def setup
    @store = Mpp::Methods::Tempo::Session::MemoryChannelStore.new
  end

  def make_channel(id: "0xabc123", deposit: 1_000_000, **overrides)
    Mpp::Methods::Tempo::Session::ChannelState.new(
      channel_id: id,
      chain_id: 4217,
      escrow_contract: "0xescrow",
      payer: "0xpayer",
      payee: "0xpayee",
      token: "0xtoken",
      authorized_signer: "0xsigner",
      deposit: deposit,
      **overrides
    )
  end

  def test_get_channel_returns_nil_when_empty
    assert_nil @store.get_channel("0xnonexistent")
  end

  def test_update_channel_creates_new
    channel = make_channel

    result = @store.update_channel("0xabc123") do |current|
      assert_nil current
      channel
    end

    assert_equal channel, result
    assert_equal channel, @store.get_channel("0xabc123")
  end

  def test_update_channel_updates_existing
    channel = make_channel
    @store.update_channel("0xabc123") { |_| channel }

    result = @store.update_channel("0xabc123") do |current|
      assert_equal channel, current
      current.with(deposit: 2_000_000)
    end

    assert_equal 2_000_000, result.deposit
    assert_equal 2_000_000, @store.get_channel("0xabc123").deposit
  end

  def test_update_channel_deletes_on_nil_return
    channel = make_channel
    @store.update_channel("0xabc123") { |_| channel }

    result = @store.update_channel("0xabc123") { |_| nil }

    assert_nil result
    assert_nil @store.get_channel("0xabc123")
  end

  def test_concurrent_updates_are_serialized
    channel = make_channel(deposit: 0)
    @store.update_channel("0xabc123") { |_| channel }

    threads = 10.times.map do
      Thread.new do
        @store.update_channel("0xabc123") do |current|
          sleep(0.001) # Simulate some work
          current.with(deposit: current.deposit + 1)
        end
      end
    end
    threads.each(&:join)

    assert_equal 10, @store.get_channel("0xabc123").deposit
  end

  def test_wait_for_update_notification
    channel = make_channel
    @store.update_channel("0xabc123") { |_| channel }

    notified = false
    waiter = Thread.new do
      @store.wait_for_update("0xabc123")
      notified = true
    end

    sleep(0.05) # Give waiter time to start
    refute notified

    @store.update_channel("0xabc123") do |current|
      current.with(deposit: 999)
    end

    waiter.join(1)
    assert notified
  end

  def test_wait_for_update_with_timeout
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @store.wait_for_update("0xnonexistent", timeout: 0.1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    assert_operator elapsed, :>=, 0.05 # Should have waited ~0.1s
    assert_operator elapsed, :<, 1.0 # But not too long
  end

  def test_deduct_from_channel_success
    channel = make_channel(deposit: 1000, highest_voucher_amount: 500, spent: 100)
    @store.update_channel("0xabc123") { |_| channel }

    result = Mpp::Methods::Tempo::Session.deduct_from_channel(@store, "0xabc123", 100)

    assert result[:ok]
    assert_equal 200, result[:channel].spent
    assert_equal 1, result[:channel].units
  end

  def test_deduct_from_channel_insufficient
    channel = make_channel(deposit: 1000, highest_voucher_amount: 500, spent: 500)
    @store.update_channel("0xabc123") { |_| channel }

    result = Mpp::Methods::Tempo::Session.deduct_from_channel(@store, "0xabc123", 100)

    refute result[:ok]
    assert_equal 500, result[:channel].spent # Unchanged
  end

  def test_deduct_from_channel_raises_when_not_found
    assert_raises(RuntimeError) do
      Mpp::Methods::Tempo::Session.deduct_from_channel(@store, "0xnonexistent", 100)
    end
  end

  def test_deduct_from_channel_skips_finalized
    channel = make_channel(deposit: 1000, highest_voucher_amount: 500, spent: 0, finalized: true)
    @store.update_channel("0xabc123") { |_| channel }

    result = Mpp::Methods::Tempo::Session.deduct_from_channel(@store, "0xabc123", 100)

    refute result[:ok]
    assert_equal 0, result[:channel].spent
  end

  def test_channel_state_defaults
    channel = Mpp::Methods::Tempo::Session::ChannelState.new(
      channel_id: "0x1",
      chain_id: 4217,
      escrow_contract: "0xe",
      payer: "0xp",
      payee: "0xr",
      token: "0xt",
      authorized_signer: "0xs"
    )

    assert_equal 0, channel.deposit
    assert_equal 0, channel.settled_on_chain
    refute channel.finalized
    assert_equal 0, channel.close_requested_at
    assert_equal 0, channel.highest_voucher_amount
    assert_nil channel.highest_voucher
    assert_equal 0, channel.spent
    assert_equal 0, channel.units
  end
end
