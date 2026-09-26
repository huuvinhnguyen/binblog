module Api
  class SessionsController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      user = User.find_by(username: params[:username])

      if user&.valid_password?(params[:password])
        token = SocialLogin::BinblogSession.token_for(user)

        render json: {
          status: 'success',
          token: token,
          user: SocialLogin::BinblogSession.user_json(user)
        }, status: :ok
      else
        render json: {
          status: 'error',
          message: 'Invalid username or password'
        }, status: :unauthorized
      end
    end
  end
end
