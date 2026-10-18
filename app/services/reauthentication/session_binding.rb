module Reauthentication
  class SessionBinding
    def self.for_bearer(raw_token)
      Authentication::SecretDigest.call(raw_token, purpose: 'bearer-session-binding')
    end
  end
end
