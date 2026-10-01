class SocialLoginsController < ApplicationController
  # ApplicationController's conditional JSON forgery strategy is null_session.
  # Keep browser social mutations on Rails' rejecting HTML strategy.
  protect_from_forgery with: :exception

  def create
    intent = params[:intent].to_s
    return render_result(:malformed_request, :bad_request) unless %w[sign_in sign_up link].include?(intent)
    return render_result(:authentication_required, :unauthorized) if intent == 'link' && !user_signed_in?
    return render_result(:malformed_request, :bad_request) unless valid_credential_parameter?

    if intent == 'link'
      return render_result(:reauthentication_required, :forbidden) unless valid_current_password?

      link_identity
    else
      sign_in_with_google
    end
  rescue SocialLogin::GoogleIdentityVerifier::InvalidCredential
    render_result(:invalid_provider_credential, :unauthorized)
  rescue SocialLogin::GoogleIdentityVerifier::Unavailable
    render_result(:provider_unavailable, :service_unavailable)
  rescue ActiveRecord::ActiveRecordError
    render_result(:internal_error, :internal_server_error)
  end

  private

  def valid_credential_parameter?
    params[:credential].is_a?(String) && params[:credential].present? && params[:credential].bytesize <= 8192
  end

  def valid_current_password?
    password = params[:current_password]
    password.is_a?(String) && password.present? && current_user.usable_password_authentication? &&
      current_user.valid_password?(password)
  end

  def link_identity
    verified_identity = google_verifier.call(credential: params[:credential])
    authorization = Reauthentication::Authorization.new(
      user: current_user,
      session_binding_digest: nil,
      purpose: 'link_identity',
      current_password: params[:current_password]
    )
    outcome = SocialLogin::LinkIdentity.new.call(
      user: current_user, verified_identity: verified_identity, authorization: authorization
    )
    case outcome.status
    when :linked, :already_linked
      render json: { status: 'success', code: outcome.status.to_s }, status: :ok
    when :identity_conflict
      render_result(:identity_conflict, :conflict)
    when :provider_already_linked
      render_result(:provider_already_linked, :conflict)
    when :unsupported_provider
      render_result(:unsupported_provider, :unprocessable_entity)
    else
      render_result(:internal_error, :internal_server_error)
    end
  end

  def sign_in_with_google
    verified_identity = google_verifier.call(credential: params[:credential])
    outcome = SocialLogin::SignInResolver.new.call(verified_identity: verified_identity)
    case outcome.status
    when :existing_identity, :created_account
      establish_web_session(outcome.user)
    when :link_required
      render_result(:link_required, :conflict)
    when :email_verification_required
      render_result(:email_verification_required, :unprocessable_entity)
    when :username_unavailable
      render_result(:username_unavailable, :service_unavailable)
    when :identity_disabled
      render_result(:invalid_provider_credential, :unauthorized)
    else
      render_result(:internal_error, :internal_server_error)
    end
  end

  def establish_web_session(user)
    destination = stored_location_for(:user) || after_sign_in_path_for(user)
    sign_out(:user) if user_signed_in?
    reset_session
    sign_in(:user, user)
    render json: { status: 'success', redirect_url: destination }, status: :ok
  end

  def google_verifier
    SocialLogin::GoogleIdentityVerifier.new(audiences: [ENV.fetch('GOOGLE_WEB_CLIENT_ID', '')])
  end

  def render_result(code, status)
    render json: { status: 'error', code: code.to_s }, status: status
  end
end
