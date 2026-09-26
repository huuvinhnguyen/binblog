module SocialLogin
  # The future HTTP/web boundary must verify recent authentication before calling.
  class UnlinkIdentity
    def call(user:, provider:)
      raise ArgumentError, 'Authenticated user required' unless user.is_a?(User) && user.persisted?

      user.with_lock do
        identity = user.user_identities.find_by(provider: provider.to_s.strip.downcase)
        next Outcome.new(status: :not_linked, user: user) unless identity

        other_identity = user.user_identities.where.not(id: identity.id).exists?
        unless user.usable_password_authentication? || other_identity
          next Outcome.new(status: :last_authentication_method, user: user)
        end

        identity.destroy!
        Outcome.new(status: :unlinked, user: user)
      end
    end
  end
end
