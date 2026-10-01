module Api
  class SocialSessionsController < ApplicationController
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!

    def create
      provider = params[:provider]
      credential = params[:credential]
      return error(:malformed_request, :bad_request) unless provider.is_a?(String) &&
        credential.is_a?(String) && credential.present? && credential.bytesize <= 8192
      return error(:unsupported_provider, :unprocessable_entity) unless provider.strip.downcase == 'google'

      identity = google_verifier.call(credential: credential)
      outcome = SocialLogin::SignInResolver.new.call(verified_identity: identity)
      case outcome.status
      when :existing_identity, :created_account
        render json: {
          status: 'success',
          token: SocialLogin::BinblogSession.token_for(outcome.user),
          user: SocialLogin::BinblogSession.user_json(outcome.user)
        }, status: :ok
      when :link_required
        error(:link_required, :conflict)
      when :email_verification_required
        error(:email_verification_required, :unprocessable_entity)
      when :username_unavailable
        error(:username_unavailable, :service_unavailable)
      when :identity_disabled
        error(:invalid_provider_credential, :unauthorized)
      else
        error(:internal_error, :internal_server_error)
      end
    rescue SocialLogin::GoogleIdentityVerifier::InvalidCredential
      error(:invalid_provider_credential, :unauthorized)
    rescue SocialLogin::GoogleIdentityVerifier::Unavailable
      error(:provider_unavailable, :service_unavailable)
    rescue ActiveRecord::ActiveRecordError
      error(:internal_error, :internal_server_error)
    end

    private

    def google_verifier
      SocialLogin::GoogleIdentityVerifier.new(audiences: ENV.fetch('GOOGLE_CLIENT_IDS', '').split(','))
    end

    def error(code, http_status)
      render json: { status: 'error', code: code.to_s }, status: http_status
    end
  end
end
