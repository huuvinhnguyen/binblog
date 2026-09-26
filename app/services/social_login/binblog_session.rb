module SocialLogin
  class BinblogSession
    def self.token_for(user)
      JWT.encode(
        { user_id: user.id, exp: 7.days.from_now.to_i },
        Rails.application.secret_key_base,
        'HS256'
      )
    end

    def self.user_json(user)
      { id: user.id, username: user.username, email: user.email }
    end
  end
end
