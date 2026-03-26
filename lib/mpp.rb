# frozen_string_literal: true

require_relative "mpp/version"
require_relative "mpp/json"
require_relative "mpp/challenge_id"
require_relative "mpp/secure_compare"

module Mpp
  autoload :Challenge, "mpp/challenge"
  autoload :ChallengeEcho, "mpp/challenge_echo"
  autoload :Credential, "mpp/credential"
  autoload :Receipt, "mpp/receipt"
  autoload :Parsing, "mpp/parsing"
  autoload :Json, "mpp/json"
  autoload :BodyDigest, "mpp/body_digest"
  autoload :Expires, "mpp/expires"
  autoload :Units, "mpp/units"
  autoload :MemoryStore, "mpp/store"

  # Server module (autoloaded)
  autoload :Server, "mpp/server"

  # Client module (autoloaded)
  autoload :Client, "mpp/client"

  # Methods namespace
  module Methods
    autoload :Tempo, "mpp/methods/tempo"
  end

  # Extensions namespace
  module Extensions
    autoload :MCP, "mpp/extensions/mcp"
  end

  # Error hierarchy
  autoload :PaymentError, "mpp/errors"
  autoload :PaymentRequiredError, "mpp/errors"
  autoload :MalformedCredentialError, "mpp/errors"
  autoload :InvalidChallengeError, "mpp/errors"
  autoload :VerificationFailedError, "mpp/errors"
  autoload :PaymentExpiredError, "mpp/errors"
  autoload :InvalidPayloadError, "mpp/errors"
  autoload :PaymentInsufficientError, "mpp/errors"
  autoload :PaymentMethodUnsupportedError, "mpp/errors"
  autoload :PaymentActionRequiredError, "mpp/errors"
  autoload :BadRequestError, "mpp/errors"
  autoload :VerificationError, "mpp/errors"
  autoload :ParseError, "mpp/errors"
end
