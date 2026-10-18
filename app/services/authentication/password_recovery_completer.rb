module Authentication
  class PasswordRecoveryCompleter
    Result = Struct.new(:status, keyword_init: true)

    def call(token:, password:, password_confirmation:, username: nil, recovery_code: nil)
      social_user = SocialRecoveryChallenge.new.verify(token)
      return complete_social_recovery(
        user: social_user, token: token, recovery_code: recovery_code,
        username: username, password: password, password_confirmation: password_confirmation
      ) if social_user

      complete_password_reset(
        token: token, password: password, password_confirmation: password_confirmation
      )
    rescue ActiveRecord::ActiveRecordError
      Result.new(status: :invalid_or_expired_recovery)
    end

    private

    def complete_password_reset(token:, password:, password_confirmation:)
      user = User.reset_password_by_token(
        reset_password_token: token,
        password: password,
        password_confirmation: password_confirmation
      )
      status = user.persisted? && user.errors.empty? ? :password_updated : :invalid_or_expired_recovery
      Result.new(status: status)
    end

    def complete_social_recovery(user:, token:, recovery_code:, username:, password:, password_confirmation:)
      normalized_code = UserRecoveryCode.normalize(recovery_code)
      return Result.new(status: :invalid_or_expired_recovery) unless normalized_code

      code_digest = Authentication::SecretDigest.call(normalized_code, purpose: 'user-recovery-code')
      result = nil
      User.transaction do
        user.lock!
        unless challenge_still_valid?(user, token) && !user.usable_password_authentication?
          result = Result.new(status: :invalid_or_expired_recovery)
          raise ActiveRecord::Rollback
        end

        code = user.user_recovery_codes.unused.lock.find_by(code_digest: code_digest)
        unless code
          result = Result.new(status: :invalid_or_expired_recovery)
          raise ActiveRecord::Rollback
        end

        user.assign_attributes(
          username: username.to_s.strip,
          password: password,
          password_confirmation: password_confirmation
        )
        unless user.save
          result = Result.new(status: :invalid_or_expired_recovery)
          raise ActiveRecord::Rollback
        end

        now = Time.current
        user.user_recovery_codes.unused.update_all(used_at: now, updated_at: now)
        result = Result.new(status: :password_updated)
      end
      result
    end

    def challenge_still_valid?(user, token)
      SocialRecoveryChallenge.new.verify(token)&.id == user.id
    end
  end
end
