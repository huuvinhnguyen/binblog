module Reauthentication
  class ProviderVerifier
    MAX_AGE = 5.minutes
    FUTURE_LEEWAY = 1.minute

    def call(user:, provider:, credential:, verifier:)
      return false unless SocialLogin::ProviderPolicy.enabled?(provider)

      verified_identity = verifier.call(credential: credential)
      return false unless verified_identity.provider == provider
      return false unless fresh?(verified_identity.issued_at)

      identity = user.user_identities.enabled.find_by(
        provider: verified_identity.provider,
        provider_uid: verified_identity.provider_uid
      )
      return false unless identity

      identity.update!(last_authenticated_at: Time.current)
      true
    end

    private

    def fresh?(issued_at)
      issued_at && issued_at >= MAX_AGE.ago && issued_at <= FUTURE_LEEWAY.from_now
    end
  end
end
