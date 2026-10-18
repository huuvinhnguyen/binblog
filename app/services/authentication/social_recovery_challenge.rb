module Authentication
  class SocialRecoveryChallenge
    PURPOSE = 'social-password-recovery'.freeze
    LIFETIME = 30.minutes

    def issue(user)
      encryptor.encrypt_and_sign(
        {
          'user_id' => user.id,
          'email_digest' => email_digest(user.email),
          'nonce' => SecureRandom.hex(16)
        },
        expires_in: LIFETIME,
        purpose: PURPOSE
      )
    end

    def verify(raw_token)
      payload = encryptor.decrypt_and_verify(raw_token, purpose: PURPOSE)
      user = User.find_by(id: payload['user_id'])
      return unless user
      return unless secure_match?(payload['email_digest'], email_digest(user.email))

      user
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, KeyError, TypeError
      nil
    end

    private

    def encryptor
      key_length = ActiveSupport::MessageEncryptor.key_len
      key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key(PURPOSE, key_length)
      ActiveSupport::MessageEncryptor.new(key, serializer: JSON)
    end

    def email_digest(email)
      Authentication::SecretDigest.hex(email.to_s.downcase, purpose: 'social-recovery-email')
    end

    def secure_match?(left, right)
      left.is_a?(String) && left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
