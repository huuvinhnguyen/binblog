module Authentication
  class MethodsProjection
    def initialize(user:)
      @user = user
    end

    def as_json
      identities = @user.user_identities.order(:provider).to_a

      {
        status: 'success',
        password: { usable: @user.usable_password_authentication? },
        providers: identities.map do |identity|
          usable = identity.usable?
          {
            provider: identity.provider,
            usable: usable,
            can_unlink: usable_method_count(identities: identities, excluding: identity) > 0
          }
        end,
        recovery: { codes_enrolled: @user.user_recovery_codes.unused.exists? }
      }
    end

    def usable_method_count(excluding: nil, identities: nil)
      identities ||= @user.user_identities.to_a
      provider_count = identities.count { |identity| identity != excluding && identity.usable? }
      provider_count + (@user.usable_password_authentication? ? 1 : 0)
    end
  end
end
