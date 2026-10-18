module Api
  class SocialIdentitiesController < ApplicationController
    include BearerAuthentication
    include AuthRequestSafety

    skip_before_action :verify_authenticity_token
    before_action :reject_oversized_auth_request!
    before_action :authenticate_bearer_user!

    def create
      provider = params[:provider]
      credential = params[:credential]
      return error(:malformed_request, :bad_request) unless provider.is_a?(String) &&
        credential.is_a?(String) && credential.present? && credential.bytesize <= 8192
      return error(:unsupported_provider, :unprocessable_entity) unless provider.strip.downcase == 'google'
      authorization = reauthentication_authorization(:link_identity)
      return error(:reauthentication_required, :forbidden) unless authorization.preflight_valid?

      identity = google_verifier.call(credential: credential)
      outcome = SocialLogin::LinkIdentity.new.call(
        user: @authenticated_user, verified_identity: identity, authorization: authorization
      )
      case outcome.status
      when :linked, :already_linked
        render json: { status: 'success', code: outcome.status.to_s }, status: :ok
      when :identity_conflict
        error(:identity_conflict, :conflict)
      when :provider_already_linked
        error(:provider_already_linked, :conflict)
      when :unsupported_provider
        error(:unsupported_provider, :unprocessable_entity)
      when :reauthentication_required
        error(:reauthentication_required, :forbidden)
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

      methods = Authentication::MethodsProjection.new(user: @authenticated_user)
      unless methods.usable_method_count(excluding: existing).positive?
        return error(:last_authentication_method, :conflict)
      end

      outcome = SocialLogin::UnlinkIdentity.new.call(
        user: @authenticated_user,
        provider: provider,
        authorization: reauthentication_authorization(:unlink_identity)
      )
      case outcome.status
      when :unlinked, :not_linked
        render json: { status: 'success', code: outcome.status.to_s }, status: :ok
      when :last_authentication_method
        error(:last_authentication_method, :conflict)
      when :reauthentication_required
        error(:reauthentication_required, :forbidden)
      else
        error(:internal_error, :internal_server_error)
      end
    rescue ActiveRecord::ActiveRecordError
      error(:internal_error, :internal_server_error)
    end

    private

    def reauthentication_authorization(purpose)
      Reauthentication::Authorization.new(
        user: @authenticated_user,
        session_binding_digest: @session_binding_digest,
        purpose: purpose.to_s,
        token: params[:reauthentication_token],
        current_password: params[:current_password]
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
