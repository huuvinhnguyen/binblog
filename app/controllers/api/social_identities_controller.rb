module Api
  class SocialIdentitiesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_bearer_user!

    def create
      provider = params[:provider]
      credential = params[:credential]
      return error(:malformed_request, :bad_request) unless provider.is_a?(String) &&
        credential.is_a?(String) && credential.present? && credential.bytesize <= 8192
      return error(:unsupported_provider, :unprocessable_entity) unless provider.strip.downcase == 'google'
      return error(:reauthentication_required, :forbidden) unless valid_reauthentication?

      identity = google_verifier.call(credential: credential)
      outcome = SocialLogin::LinkIdentity.new.call(user: @authenticated_user, verified_identity: identity)
      case outcome.status
      when :linked, :already_linked
        render json: { status: 'success', code: outcome.status.to_s }, status: :ok
      when :identity_conflict
        error(:identity_conflict, :conflict)
      when :provider_already_linked
        error(:provider_already_linked, :conflict)
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

    def destroy
      provider = params[:provider]
      return error(:unsupported_provider, :unprocessable_entity) unless provider == 'google'

      existing = @authenticated_user.user_identities.find_by(provider: provider)
      return render json: { status: 'success', code: 'not_linked' }, status: :ok unless existing

      other_identity = @authenticated_user.user_identities.where.not(id: existing.id).exists?
      unless @authenticated_user.usable_password_authentication? || other_identity
        return error(:last_authentication_method, :conflict)
      end
      return error(:reauthentication_required, :forbidden) unless valid_reauthentication?

      outcome = SocialLogin::UnlinkIdentity.new.call(user: @authenticated_user, provider: provider)
      case outcome.status
      when :unlinked, :not_linked
        render json: { status: 'success', code: outcome.status.to_s }, status: :ok
      when :last_authentication_method
        error(:last_authentication_method, :conflict)
      else
        error(:internal_error, :internal_server_error)
      end
    rescue ActiveRecord::ActiveRecordError
      error(:internal_error, :internal_server_error)
    end

    private

    def authenticate_bearer_user!
      header = request.headers['Authorization'].to_s
      match = /\ABearer ([^\s]+)\z/.match(header)
      return error(:authentication_required, :unauthorized) unless match

      payload = JWT.decode(
        match[1], Rails.application.secret_key_base, true,
        algorithm: 'HS256', verify_expiration: true
      ).first
      @authenticated_user = User.find_by(id: payload['user_id'])
      error(:authentication_required, :unauthorized) unless @authenticated_user
    rescue JWT::DecodeError
      error(:authentication_required, :unauthorized)
    end

    def valid_reauthentication?
      password = params[:current_password]
      password.is_a?(String) && password.present? &&
        @authenticated_user.usable_password_authentication? &&
        @authenticated_user.valid_password?(password)
    end

    def google_verifier
      SocialLogin::GoogleIdentityVerifier.new(audiences: ENV.fetch('GOOGLE_CLIENT_IDS', '').split(','))
    end

    def error(code, http_status)
      render json: { status: 'error', code: code.to_s }, status: http_status
    end
  end
end
