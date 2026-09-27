module SocialLogin
  class GoogleIdentityVerifier
    ISSUERS = ['accounts.google.com', 'https://accounts.google.com'].freeze

    class InvalidCredential < StandardError; end
    class Unavailable < StandardError; end

    def initialize(jwks: GoogleJwks.new, audiences:)
      @jwks = jwks
      @audiences = audiences.map(&:strip).reject(&:empty?)
    end

    def call(credential:)
      raise Unavailable if @audiences.empty?
      raise InvalidCredential unless credential.is_a?(String) && credential.present?

      payload, = JWT.decode(
        credential, nil, true,
        algorithms: ['RS256'],
        jwks: ->(options) { @jwks.call(force_refresh: options[:invalidate]) },
        verify_iss: true, iss: ISSUERS,
        verify_aud: true, aud: @audiences,
        verify_expiration: true,
        required_claims: %w[iss aud exp sub]
      )
      subject = payload['sub']
      raise InvalidCredential unless subject.is_a?(String) && subject.present?

      email = authoritative_verified_email(payload)
      VerifiedIdentity.from_verified_claims(
        provider: 'google', provider_uid: subject, verified_email: email
      )
    rescue GoogleJwks::Unavailable
      raise Unavailable
    rescue JWT::DecodeError, JWT::JWKError, ArgumentError
      raise InvalidCredential
    end

    private

    def authoritative_verified_email(payload)
      email = payload['email']
      return unless payload['email_verified'] == true && email.is_a?(String)

      # Google warns that a verified third-party address without hd can be stale.
      return unless email.downcase.end_with?('@gmail.com') || payload['hd'].present?

      email
    end
  end
end
