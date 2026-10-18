module Api
  class PasswordsController < ApplicationController
    include BearerAuthentication
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!
    before_action :authenticate_bearer_user!

    def update
      return error(:malformed_request, :bad_request) unless valid_parameters?

      authorization = reauthentication_authorization(:add_password)
      outcome = Authentication::AddPassword.new.call(
        user: @authenticated_user,
        username: params[:username],
        password: params[:password],
        password_confirmation: params[:password_confirmation],
        authorization: authorization
      )
      case outcome.status
      when :password_added
        render json: { status: 'success', code: 'password_added' }, status: :ok
      when :password_already_set
        error(:password_already_set, :conflict)
      when :reauthentication_required
        error(:reauthentication_required, :forbidden)
      when :username_unavailable
        error(:username_unavailable, :unprocessable_entity)
      else
        error(:invalid_password, :unprocessable_entity)
      end
    rescue ActiveRecord::ActiveRecordError
      error(:internal_error, :internal_server_error)
    end

    private

    def valid_parameters?
      bounded_string?(params[:username], maximum: 255) &&
        bounded_string?(params[:password], maximum: 128) &&
        bounded_string?(params[:password_confirmation], maximum: 128) &&
        valid_optional_reauthentication_token?
    end

    def valid_optional_reauthentication_token?
      return true unless params.key?(:reauthentication_token)

      bounded_string?(
        params[:reauthentication_token], maximum: Reauthentication::Authorization::MAX_TOKEN_BYTES
      )
    end

    def reauthentication_authorization(purpose)
      Reauthentication::Authorization.new(
        user: @authenticated_user,
        session_binding_digest: @session_binding_digest,
        purpose: purpose.to_s,
        token: params[:reauthentication_token]
      )
    end

    def error(code, http_status)
      render json: { status: 'error', code: code.to_s }, status: http_status
    end
  end
end
