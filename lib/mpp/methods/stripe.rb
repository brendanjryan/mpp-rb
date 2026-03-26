# typed: strict
# frozen_string_literal: true

module Mpp
  module Methods
    module Stripe
      autoload :Defaults, "mpp/methods/stripe/defaults"
      autoload :StripeMethod, "mpp/methods/stripe/stripe_method"
      autoload :ChargeIntent, "mpp/methods/stripe/charge_intent"
      autoload :ClientMethod, "mpp/methods/stripe/client_method"
    end
  end
end
