class SocialAuthenticationController < ApplicationController
  protect_from_forgery with: :exception
  before_action :authenticate_user!

  def show
    @google_identity = current_user.user_identities.find_by(provider: 'google')
    @has_local_password = current_user.usable_password_authentication?
  end

  def destroy
    provider = params[:provider].to_s
    return redirect_with_alert('This sign-in method is not supported.') unless provider == 'google'

    identity = current_user.user_identities.find_by(provider: provider)
    return redirect_with_notice('Google is not linked to this account.') unless identity
    unless current_user.usable_password_authentication?
      other_identity = current_user.user_identities.where.not(id: identity.id).exists?
      return redirect_with_alert('Add another sign-in method before unlinking Google.') unless other_identity
      return redirect_with_alert('Set a local password before managing linked sign-in methods.')
    end
    return redirect_with_alert('Enter your current password to confirm this change.') unless valid_current_password?

    authorization = Reauthentication::Authorization.new(
      user: current_user,
      session_binding_digest: nil,
      purpose: 'unlink_identity',
      current_password: params[:current_password]
    )
    outcome = SocialLogin::UnlinkIdentity.new.call(
      user: current_user, provider: provider, authorization: authorization
    )
    case outcome.status
    when :unlinked, :not_linked
      redirect_with_notice('Google was unlinked from this account.')
    when :last_authentication_method
      redirect_with_alert('Add another sign-in method before unlinking Google.')
    else
      redirect_with_alert('Google could not be unlinked. Please try again.')
    end
  rescue ActiveRecord::ActiveRecordError
    redirect_with_alert('Google could not be unlinked. Please try again.')
  end

  private

  def valid_current_password?
    password = params[:current_password]
    password.is_a?(String) && password.present? && current_user.usable_password_authentication? &&
      current_user.valid_password?(password)
  end

  def redirect_with_notice(message)
    redirect_to account_authentication_path, notice: message
  end

  def redirect_with_alert(message)
    redirect_to account_authentication_path, alert: message
  end
end
