# typed: false
# frozen_string_literal: true

module Mpp
  module Methods
    module Tempo
      module Session
        # Per-channel persistent state.
        #
        # Tracks the channel's identity, on-chain balance, the highest voucher
        # the server has accepted, and the current session's spend counters.
        #
        # Monotonicity invariants (enforced by update callbacks):
        # - highest_voucher_amount only increases
        # - settled_on_chain only increases
        # - deposit reflects the latest on-chain value
        ChannelState = Data.define(
          :channel_id, :chain_id, :escrow_contract,
          :payer, :payee, :token, :authorized_signer,
          :deposit, :settled_on_chain, :finalized, :close_requested_at,
          :highest_voucher_amount, :highest_voucher, :spent, :units,
          :created_at
        ) do
          def initialize(
            channel_id:, chain_id:, escrow_contract:,
            payer:, payee:, token:, authorized_signer:,
            deposit: 0, settled_on_chain: 0, finalized: false, close_requested_at: 0,
            highest_voucher_amount: 0, highest_voucher: nil, spent: 0, units: 0,
            created_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
          )
            super
          end
        end

        # Duck type for channel stores:
        #   get_channel(channel_id) -> ChannelState | nil
        #   update_channel(channel_id, &block) -> ChannelState | nil
        #   wait_for_update(channel_id) -> void (optional)
        #
        # update_channel yields current state (or nil), expects new state (or nil to delete).
        # Must be atomic per channel_id.

        # In-memory channel store with per-key mutex for atomicity
        # and ConditionVariable for efficient SSE polling.
        class MemoryChannelStore
          def initialize
            @data = {}
            @mutexes = {}
            @global_mutex = Mutex.new
            @waiters = {}
          end

          def get_channel(channel_id)
            mutex_for(channel_id).synchronize { @data[channel_id] }
          end

          # Atomic read-modify-write for channel state.
          # The block receives the current state (or nil) and must return
          # the new state (or nil to delete the channel).
          def update_channel(channel_id)
            result = nil
            mutex_for(channel_id).synchronize do
              current = @data[channel_id]
              next_state = yield current
              if next_state.nil?
                @data.delete(channel_id)
              else
                @data[channel_id] = next_state
              end
              result = next_state
            end
            notify(channel_id)
            result
          end

          # Wait for the next update to a channel. Returns once update_channel
          # is called for the given channel_id. Falls back to polling when
          # not supported.
          def wait_for_update(channel_id, timeout: nil)
            cv = nil
            mtx = nil
            @global_mutex.synchronize do
              @waiters[channel_id] ||= []
              cv = ConditionVariable.new
              mtx = Mutex.new
              @waiters[channel_id] << [cv, mtx]
            end

            mtx.synchronize do
              if timeout
                cv.wait(mtx, timeout)
              else
                cv.wait(mtx)
              end
            end
          end

          private

          def mutex_for(channel_id)
            @global_mutex.synchronize do
              @mutexes[channel_id] ||= Mutex.new
            end
          end

          def notify(channel_id)
            waiters = nil
            @global_mutex.synchronize do
              waiters = @waiters.delete(channel_id)
            end
            return unless waiters

            waiters.each do |cv, mtx|
              mtx.synchronize { cv.signal }
            end
          end
        end

        # Atomically deduct amount from a channel's available balance.
        # Returns { ok: true, channel: } on success, { ok: false, channel: } if insufficient.
        # Raises if channel does not exist.
        def self.deduct_from_channel(store, channel_id, amount)
          deducted = false
          channel = store.update_channel(channel_id) do |current|
            deducted = false
            raise "channel not found" if current.nil?
            if current.finalized
              next current
            end
            if current.highest_voucher_amount - current.spent >= amount
              deducted = true
              current.with(spent: current.spent + amount, units: current.units + 1)
            else
              current
            end
          end
          {ok: deducted, channel: channel}
        end
      end
    end
  end
end
