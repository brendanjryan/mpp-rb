# frozen_string_literal: true

module Mpp
  module Server
    # Intent interface (duck type):
    #   name  -> String
    #   verify(credential, request) -> Receipt
    #
    # Implement this interface for custom payment intents.

    # Function-based intent wrapper.
    class FunctionalIntent
      attr_reader :name

      def initialize(name, &verify_fn)
        @name = name
        @verify_fn = verify_fn
      end

      def verify(credential, request)
        @verify_fn.call(credential, request)
      end
    end

    # Decorator to define an intent from a block.
    #   intent = Mpp::Server.intent("charge") { |credential, request| ... }
    def self.intent(name, &)
      FunctionalIntent.new(name, &)
    end
  end
end
