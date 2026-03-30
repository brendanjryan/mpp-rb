# typed: false
# frozen_string_literal: true

module Mpp
  module Methods
    module Tempo
      module Session
        ACTIONS = %w[open topUp voucher close].freeze

        # Escrow contract function selectors (first 4 bytes of keccak256 of signature).
        # open(address,address,uint256,bytes32,address)
        OPEN_SELECTOR = "0xd6e8b973"
        # topUp(bytes32,uint256)
        TOP_UP_SELECTOR = "0x327690ae"
        # close(bytes32,uint128,bytes)
        CLOSE_SELECTOR = "0xf10ee69a"
        # settle(bytes32,uint128,bytes)
        SETTLE_SELECTOR = "0x76489e07"
        # getChannel(bytes32)
        GET_CHANNEL_SELECTOR = "0xa4bfe89a"
        # approve(address,uint256)
        ERC20_APPROVE_SELECTOR = "0x095ea7b3"

        UINT128_MAX = (2**128) - 1
        ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
      end
    end
  end
end
