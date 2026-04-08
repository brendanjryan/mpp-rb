# typed: false
# frozen_string_literal: true

module Mpp
  module Methods
    module Tempo
      module Session
        autoload :ChannelState, "mpp/methods/tempo/session/channel_store"
        autoload :PreparedCredential, "mpp/methods/tempo/session/client_method"
        autoload :ClientChannel, "mpp/methods/tempo/session/client_method"
        autoload :ClientMethod, "mpp/methods/tempo/session/client_method"
        autoload :SessionManager, "mpp/methods/tempo/session/session_manager"
        autoload :MemoryChannelStore, "mpp/methods/tempo/session/channel_store"
        autoload :SessionIntent, "mpp/methods/tempo/session/session_intent"
        autoload :SessionReceipt, "mpp/methods/tempo/session/receipt"
        autoload :Voucher, "mpp/methods/tempo/session/voucher"
        autoload :Chain, "mpp/methods/tempo/session/chain"
        autoload :Sse, "mpp/methods/tempo/session/sse"

        module_function

        def session_manager(**kwargs)
          SessionManager.new(**kwargs)
        end
      end
    end
  end
end
