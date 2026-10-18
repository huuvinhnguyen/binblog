module Api
  class ReauthenticationsController < ApplicationController
    include BearerAuthentication
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!
    before_action :authenticate_bearer_user!

    def create
      return error(:malformed_request, :bad_request) unless valid_common_parameters?
      return error(:rate_limited, :too_many_requests) unless rate_limit_allowed?

      method = params[:method].strip.downcase
      verified = method == 'password' ? verify_password : verify_provider(method)
      return error(:unsupported_method, :unprocessable_entity) if verified == :unsupported_method
      return error(:unsupported_provider, :unprocessable_entity) if verified == :unsupported_provider
      return error(:reauthentication_failed, :forbidden) unless verified

      result = Reauthentication::GrantIssuer.new.call(
        user: @authenticated_user,
        session_binding_digest: @session_binding_digest,
        purpose: params[:purpose],
        method: method,
        provider: method == 'password' ? nil : method
      )
      render json: {
        status: 'success',
        reauthentication_token: result.token,
        expires_at: result.expires_at.iso8601
      }, status: :ok
    rescue SocialLogin::GoogleIdentityVerifier::Unavailable
      error(:provider_unavailable, :service_unavailable)
    rescue SocialLogin::GoogleIdentityVerifier::InvalidCredential
      error(:reauthentication_failed, :forbidden)
    rescue ActiveRecord::ActiveRecordError
      error(:internal_error, :internal_server_error)
    end

    private

    def valid_common_parameters?
      bounded_string?(params[:purpose], maximum: 64) &&
        ReauthenticationGrant::PURPOSES.include?(params[:purpose]) &&
        bounded_string?(params[:method], maximum: 32)
    end

    def verify_password
      return false unless bounded_string?(params[:password], maximum: 128)

      @authenticated_user.usable_password_authentication? &&
        @authenticated_user.valid_password?(params[:password])
    end

    def verify_provider(method)
      return :unsupported_method unless ReauthenticationGrant::METHODS.include?(method)
      return :unsupported_provider unless method == 'google'
      return false unless bounded_string?(params[:credential], maximum: 8192)

      Reauthentication::ProviderVerifier.new.call(
        user: @authenticated_user,
        provider: method,
        credential: params[:credential],
        verifier: google_verifier
      )
    end

    def rate_limit_allowed?
      Authentication::RateLimiter.new.allowed?(
        scope: 'reauthentication',
        discriminator: "#{@authenticated_user.id}:#{request.remote_ip}",
        limit: 10,
        period: 5.minutes
      )
    end

    def google_verifier
      SocialLogin::GoogleIdentityVerifier.new(audiences: ENV.fetch('GOOGLE_CLIENT_IDS', '').split(','))
    end

    def error(code, http_status)
      render json: { status: 'error', code: code.to_s }, status: http_status
    end
  end
end
