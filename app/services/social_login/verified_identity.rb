module SocialLogin
  # Construct only from claims already checked by a provider-specific verifier.
  # Controllers must never build this from request email, UID, or verified flags.
  class VerifiedIdentity
    attr_reader :provider, :provider_uid, :verified_email

    def self.from_verified_claims(provider:, provider_uid:, verified_email: nil)
      new(provider: provider, provider_uid: provider_uid, verified_email: verified_email)
    end

    def initialize(provider:, provider_uid:, verified_email:)
      @provider = provider.to_s.strip.downcase
      @provider_uid = provider_uid.to_s
      @verified_email = verified_email.to_s.strip.downcase.presence
      raise ArgumentError, 'Invalid provider' unless @provider.match?(/\A[a-z][a-z0-9_]*\z/)
      raise ArgumentError, 'Invalid provider UID' if @provider_uid.strip.empty?
      raise ArgumentError, 'Provider UID too long' if @provider_uid.bytesize > UserIdentity::MAX_PROVIDER_UID_BYTES

      freeze
    end

    private_class_method :new
  end
end
