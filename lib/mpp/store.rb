# frozen_string_literal: true

module Mpp
  # In-memory key-value store for development/testing.
  # Production implementations should use Redis, DynamoDB, etc.
  #
  # Duck type interface (Store):
  #   get(key) -> value or nil
  #   put(key, value) -> void
  #   delete(key) -> void
  #   put_if_absent(key, value) -> bool
  class MemoryStore
    def initialize
      @data = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize { @data[key] }
    end

    def put(key, value)
      @mutex.synchronize { @data[key] = value }
    end

    def delete(key)
      @mutex.synchronize { @data.delete(key) }
    end

    # Store value under key only if key does not already exist.
    # Returns true if the key was new, false if it already existed.
    def put_if_absent(key, value)
      @mutex.synchronize do
        return false if @data.key?(key)

        @data[key] = value
        true
      end
    end
  end
end
