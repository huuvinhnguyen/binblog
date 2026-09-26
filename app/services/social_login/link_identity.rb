module SocialLogin
  class LinkIdentity
    def call(user:, verified_identity:)
      raise ArgumentError, 'Authenticated user required' unless user.is_a?(User) && user.persisted?
      raise ArgumentError, 'Verified identity required' unless verified_identity.is_a?(VerifiedIdentity)

      user.with_lock { resolve_under_lock(user, verified_identity) }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      # A competing transaction may have claimed either unique key. Re-read
      # authoritative state; never return another user's identity or principal.
      resolve_collision(user, verified_identity, error)
    end

    private

    def resolve_under_lock(user, verified_identity)
      identity = find_identity(verified_identity)
      if identity
        return Outcome.new(status: :identity_conflict, user: user) unless identity.user_id == user.id

        identity.update!(last_authenticated_at: Time.current)
        return Outcome.new(status: :already_linked, user: user)
      end

      if user.user_identities.exists?(provider: verified_identity.provider)
        return Outcome.new(status: :provider_already_linked, user: user)
      end

      user.user_identities.create!(
        provider: verified_identity.provider,
        provider_uid: verified_identity.provider_uid,
        last_authenticated_at: Time.current
      )
      Outcome.new(status: :linked, user: user)
    end

    def resolve_collision(user, verified_identity, error)
      identity = find_identity(verified_identity)
      return Outcome.new(status: :identity_conflict, user: user) if identity && identity.user_id != user.id
      return Outcome.new(status: :already_linked, user: user) if identity
      return Outcome.new(status: :provider_already_linked, user: user) if user.user_identities.exists?(provider: verified_identity.provider)

      raise error
    end

    def find_identity(verified_identity)
      UserIdentity.find_by(provider: verified_identity.provider, provider_uid: verified_identity.provider_uid)
    end
  end
end
