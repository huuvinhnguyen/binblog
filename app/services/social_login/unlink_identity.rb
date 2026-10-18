module SocialLogin
  # Method availability and reauthentication are rechecked inside the user lock.
  class UnlinkIdentity
    def call(user:, provider:, authorization: nil)
      raise ArgumentError, 'Authenticated user required' unless user.is_a?(User) && user.persisted?

      user.with_lock do
        identity = user.user_identities.find_by(provider: provider.to_s.strip.downcase)
        next Outcome.new(status: :not_linked, user: user) unless identity

        methods = Authentication::MethodsProjection.new(user: user)
        unless methods.usable_method_count(excluding: identity).positive?
          next Outcome.new(status: :last_authentication_method, user: user)
        end
        next Outcome.new(status: :reauthentication_required, user: user) unless authorization&.consume!

        identity.destroy!
        user.user_identities.reset
        Outcome.new(status: :unlinked, user: user)
      end
    end
  end
end
