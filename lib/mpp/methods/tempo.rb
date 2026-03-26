# frozen_string_literal: true

module Mpp
  module Methods
    module Tempo
      autoload :Defaults, "mpp/methods/tempo/defaults"
      autoload :Account, "mpp/methods/tempo/account"
      autoload :Keychain, "mpp/methods/tempo/keychain"
      autoload :Attribution, "mpp/methods/tempo/attribution"
      autoload :Rpc, "mpp/methods/tempo/rpc"
      autoload :Schemas, "mpp/methods/tempo/schemas"
      autoload :ClientMethod, "mpp/methods/tempo/client_method"
      autoload :TempoMethod, "mpp/methods/tempo/client_method"
      autoload :TransactionError, "mpp/methods/tempo/client_method"
      autoload :Intents, "mpp/methods/tempo/intents"
      autoload :ChargeIntent, "mpp/methods/tempo/intents"
      autoload :FeePayer, "mpp/methods/tempo/fee_payer_envelope"
    end
  end
end
