module Authentication
  class RecoveryCodeRotator
    CODE_COUNT = 10
    Result = Struct.new(:status, :codes, keyword_init: true)

    def call(user:, authorization:)
      result = nil
      User.transaction do
        user.lock!
        unless authorization.consume!
          result = Result.new(status: :reauthentication_required)
          raise ActiveRecord::Rollback
        end

        now = Time.current
        user.user_recovery_codes.unused.update_all(used_at: now, updated_at: now)
        codes = Array.new(CODE_COUNT) { generate_code }
        codes.each do |raw_code|
          user.user_recovery_codes.create!(code_digest: digest(raw_code))
        end
        result = Result.new(status: :recovery_codes_rotated, codes: codes)
      end
      result
    end

    private

    def generate_code
      SecureRandom.hex(16).scan(/.{4}/).join('-')
    end

    def digest(raw_code)
      normalized = UserRecoveryCode.normalize(raw_code)
      Authentication::SecretDigest.call(normalized, purpose: 'user-recovery-code')
    end
  end
end
