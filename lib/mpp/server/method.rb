# frozen_string_literal: true

module Mpp
  module Server
    # Method interface (duck type):
    #   name       -> String
    #   intents    -> Hash[String, Intent]
    #   create_credential(challenge) -> Credential

    module MethodHelper
      module_function

      # Transform request using method's transform_request if available.
      def transform_request(method, request, credential)
        if method.respond_to?(:transform_request)
          method.transform_request(request, credential)
        else
          request
        end
      end
    end
  end
end
