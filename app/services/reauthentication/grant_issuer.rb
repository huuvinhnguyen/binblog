module Reauthentication
  class GrantIssuer
    LIFETIME = 5.minutes
    Result = Struct.new(:token, :expires_at, keyword_init: true)

    def call(user:, session_binding_digest:, purpose:, method:, provider: nil)
      expires_at = LIFETIME.from_now
      raw_token = SecureRandom.urlsafe_base64(32)
      user.reauthentication_grants.create!(
        token_digest: token_digest(raw_token),
        session_binding_digest: session_binding_digest,
        purpose: purpose,
        method: method,
        provider: provider,
        expires_at: expires_at
      )
      Result.new(token: raw_token, expires_at: expires_at)
    end

    private

    def token_digest(raw_token)
      Authentication::SecretDigest.call(raw_token, purpose: 'reauthentication-grant')
    end
  end
end
