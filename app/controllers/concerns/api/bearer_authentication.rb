module Api
  module BearerAuthentication
    extend ActiveSupport::Concern

    private

    def authenticate_bearer_user!
      header = request.headers['Authorization'].to_s
      match = /\ABearer ([^\s]+)\z/.match(header)
      return authentication_error unless match

      raw_token = match[1]
      payload = JWT.decode(
        raw_token, Rails.application.secret_key_base, true,
        algorithm: 'HS256', verify_expiration: true
      ).first
      @authenticated_user = User.find_by(id: payload['user_id'])
      return authentication_error unless @authenticated_user

      @session_binding_digest = Reauthentication::SessionBinding.for_bearer(raw_token)
    rescue JWT::DecodeError
      authentication_error
    end

    def authentication_error
      render json: { status: 'error', code: 'authentication_required' }, status: :unauthorized
    end
  end
end
