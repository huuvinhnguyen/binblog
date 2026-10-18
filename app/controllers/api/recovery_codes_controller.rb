module Api
  class RecoveryCodesController < ApplicationController
    include BearerAuthentication
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!
    before_action :authenticate_bearer_user!

    def create
      token = params[:reauthentication_token]
      if params.key?(:reauthentication_token) && !bounded_string?(
        token, maximum: Reauthentication::Authorization::MAX_TOKEN_BYTES
      )
        return error(:malformed_request, :bad_request)
      end

      authorization = Reauthentication::Authorization.new(
        user: @authenticated_user,
        session_binding_digest: @session_binding_digest,
        purpose: 'rotate_recovery_codes',
        token: token
      )
      outcome = Authentication::RecoveryCodeRotator.new.call(
        user: @authenticated_user, authorization: authorization
      )
      if outcome.status == :recovery_codes_rotated
        render json: { status: 'success', code: 'recovery_codes_rotated', codes: outcome.codes }, status: :ok
      else
        error(:reauthentication_required, :forbidden)
      end
    rescue ActiveRecord::ActiveRecordError
      error(:internal_error, :internal_server_error)
    end

    private

    def error(code, http_status)
      render json: { status: 'error', code: code.to_s }, status: http_status
    end
  end
end
