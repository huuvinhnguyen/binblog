module Api
  class SessionsController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      user = User.find_by(username: params[:username])

      if user&.valid_password?(params[:password])
        token = JWT.encode(
          { user_id: user.id, exp: 7.days.from_now.to_i },
          Rails.application.secret_key_base
        )

        render json: {
          status: 'success',
          token: token,
          user: {
            id: user.id,
            username: user.username,
            email: user.email
          }
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
