module SocialLogin
  class SignInResolver
    MAX_USERNAME_ATTEMPTS = 5

    def initialize(username_generator: ->(_attempt) { "social_#{SecureRandom.hex(10)}" })
      @username_generator = username_generator
    end

    def call(verified_identity:)
      require_verified_identity!(verified_identity)
      identity = find_identity(verified_identity)
      return sign_in_existing(identity) if identity

      email = verified_identity.verified_email
      return Outcome.new(status: :email_verification_required) unless usable_email?(email)
      return Outcome.new(status: :link_required) if email_taken?(email)

      create_social_account(verified_identity, email)
    end

    private

    def require_verified_identity!(identity)
      raise ArgumentError, 'Verified identity required' unless identity.is_a?(VerifiedIdentity)
    end

    def find_identity(verified_identity)
      UserIdentity.find_by(provider: verified_identity.provider, provider_uid: verified_identity.provider_uid)
    end

    def sign_in_existing(identity)
      identity.update!(last_authenticated_at: Time.current)
      Outcome.new(status: :existing_identity, user: identity.user)
    end

    def usable_email?(email)
      email.present? && email.match?(Devise.email_regexp)
    end

    def email_taken?(email)
      User.where('LOWER(email) = ?', email).exists?
    end

    def create_social_account(verified_identity, email)
      1.upto(MAX_USERNAME_ATTEMPTS) do |attempt|
        username = @username_generator.call(attempt).to_s
        begin
          user = User.transaction do
            account = User.build_for_verified_social_signup(username: username, email: email)
            account.save!
            account.user_identities.create!(
              provider: verified_identity.provider,
              provider_uid: verified_identity.provider_uid,
              last_authenticated_at: Time.current
            )
            account
          end
          return Outcome.new(status: :created_account, user: user)
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          identity = find_identity(verified_identity)
          return sign_in_existing(identity) if identity
          return Outcome.new(status: :link_required) if email_taken?(email)
          raise unless User.exists?(username: username)
        end
      end

      Outcome.new(status: :username_unavailable)
    end
  end
end
