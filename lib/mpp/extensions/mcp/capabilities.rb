# frozen_string_literal: true

module Mpp
  module Extensions
    module MCP
      module_function

      # Build payment capabilities object for MCP.
      def payment_capabilities(methods, intents)
        {
          "payment" => {
            "methods" => methods,
            "intents" => intents
          }
        }
      end
    end
  end
end
