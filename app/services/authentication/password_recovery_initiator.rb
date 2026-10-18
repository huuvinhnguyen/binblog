module Authentication
  class PasswordRecoveryInitiator
    def call(email:)
      user = User.where('LOWER(email) = ?', email.to_s.strip.downcase).first
      return unless user

      if user.usable_password_authentication?
        user.send_reset_password_instructions
      elsif user.user_recovery_codes.unused.exists?
        token = SocialRecoveryChallenge.new.issue(user)
        AuthenticationMailer.social_recovery_instructions(user, token).deliver_now
      end
    end
  end
end
