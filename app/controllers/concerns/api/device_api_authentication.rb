module Api
  module DeviceApiAuthentication
    extend ActiveSupport::Concern

    private

    def authenticate_device_api_user!
      token = request.headers['Authorization']&.split(' ')&.last
      if token.present?
        payload = JWT.decode(
          token,
          Rails.application.secret_key_base,
          true,
          algorithm: 'HS256',
          verify_expiration: true
        ).first
        @current_user = User.find(payload['user_id'])
        return
      end

      if user_signed_in?
        @current_user = warden.user(:user)
        return if @current_user
      end

      render json: { error: 'Unauthorized' }, status: :unauthorized
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    def current_user
      @current_user || super
    end
  end
end
