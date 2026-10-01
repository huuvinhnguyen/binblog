module Reauthentication
  class Authorization
    MAX_TOKEN_BYTES = 512

    def initialize(user:, session_binding_digest:, purpose:, token: nil, current_password: nil)
      @user = user
      @session_binding_digest = session_binding_digest
      @purpose = purpose
      @token = token
      @current_password = current_password
    end

    def preflight_valid?
      token_authorization? ? grant_available? : valid_legacy_password?
    end

    def consume!
      return valid_legacy_password? unless token_authorization?

      grant = ReauthenticationGrant.find_by(token_digest: token_digest)
      return false unless grant

      grant.with_lock do
        return false unless usable_grant?(grant)

        grant.update!(consumed_at: Time.current)
        true
      end
    end

    private

    def token_authorization?
      @token.is_a?(String) && @token.present? && @token.bytesize <= MAX_TOKEN_BYTES
    end

    def token_digest
      Authentication::SecretDigest.call(@token, purpose: 'reauthentication-grant')
    end

    def grant_available?
      grant = ReauthenticationGrant.find_by(token_digest: token_digest)
      grant && usable_grant?(grant)
    end

    def usable_grant?(grant)
      grant.user_id == @user.id &&
        grant.purpose == @purpose &&
        grant.consumed_at.nil? &&
        grant.expires_at.future? &&
        secure_match?(grant.session_binding_digest, @session_binding_digest)
    end

    def secure_match?(left, right)
      return false unless left.is_a?(String) && right.is_a?(String) && left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def valid_legacy_password?
      @current_password.is_a?(String) && @current_password.present? &&
        @user.usable_password_authentication? && @user.valid_password?(@current_password)
    end
  end
end
