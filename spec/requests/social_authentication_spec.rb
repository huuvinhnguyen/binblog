require 'rails_helper'

RSpec.describe 'Google Web authentication', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:signing_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:google_jwks) do
    key = JWT::JWK.new(signing_key.public_key, { kid: 'web-test-key', alg: 'RS256', use: 'sig' }).export
    instance_double(SocialLogin::GoogleJwks, call: { 'keys' => [key] })
  end

  def signed_credential(audience)
    JWT.encode(
      { iss: 'https://accounts.google.com', aud: audience, exp: 10.minutes.from_now.to_i,
        sub: 'web-audience-subject', email: 'web-audience@gmail.com', email_verified: true },
      signing_key, 'RS256', kid: 'web-test-key'
    )
  end

  def with_web_client_id(client_id)
    previous = ENV['GOOGLE_WEB_CLIENT_ID']
    ENV['GOOGLE_WEB_CLIENT_ID'] = client_id
    yield
  ensure
    ENV['GOOGLE_WEB_CLIENT_ID'] = previous
  end

  def use_real_google_verifier
    allow(SocialLogin::GoogleJwks).to receive(:new).and_return(google_jwks)
  end

  def local_user(username, email = nil)
    User.create!(username: username, email: email || "#{username}@example.com", password: 'password123')
  end

  def verified(uid, email = 'social@gmail.com')
    SocialLogin::VerifiedIdentity.from_verified_claims(
      provider: 'google', provider_uid: uid, verified_email: email
    )
  end

  def use_identity(identity)
    verifier = instance_double(SocialLogin::GoogleIdentityVerifier, call: identity)
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(verifier)
  end

  def google_auth(intent: 'sign_in', credential: 'google-id-token', password: nil)
    post google_authentication_path,
         params: { intent: intent, credential: credential, current_password: password }
  end

  def response_body
    JSON.parse(response.body)
  end

  it 'accepts only the configured Web audience for Web sign-in' do
    use_real_google_verifier
    with_web_client_id('web-client') do
      google_auth(credential: signed_credential('web-client'))
      expect(response).to have_http_status(:ok)
      expect(response_body).to eq('status' => 'success', 'redirect_url' => root_path)
    end
  end

  it 'rejects a mobile-only audience even when the mobile client is configured' do
    use_real_google_verifier
    previous = ENV['GOOGLE_CLIENT_IDS']
    ENV['GOOGLE_CLIENT_IDS'] = 'mobile-client'
    with_web_client_id('web-client') do
      expect { google_auth(credential: signed_credential('mobile-client')) }.not_to change(User, :count)
      expect(response).to have_http_status(:unauthorized)
      expect(response_body.fetch('code')).to eq('invalid_provider_credential')
    end
  ensure
    ENV['GOOGLE_CLIENT_IDS'] = previous
  end

  it 'fails closed when the Web client ID is missing or blank' do
    use_real_google_verifier
    [nil, '', '  '].each do |client_id|
      with_web_client_id(client_id) do
        expect { google_auth(credential: signed_credential('mobile-client')) }.not_to change(User, :count)
        expect(response).to have_http_status(:service_unavailable)
        expect(response_body.fetch('code')).to eq('provider_unavailable')
      end
    end
  end

  it 'authenticates a returning identity through Devise without returning a JWT' do
    owner = local_user('google_returning')
    owner.user_identities.create!(provider: 'google', provider_uid: 'google-subject')
    use_identity(verified('google-subject'))

    google_auth

    expect(response).to have_http_status(:ok)
    expect(response_body).to eq('status' => 'success', 'redirect_url' => root_path)
    expect(response.body).not_to include('token')
    get account_authentication_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(owner.username)
  end

  it 'creates a verified-email account then establishes its Devise session' do
    use_identity(verified('new-google-subject'))

    expect { google_auth }.to change(User, :count).by(1).and change(UserIdentity, :count).by(1)

    expect(response).to have_http_status(:ok)
    owner = User.find_by!(email: 'social@gmail.com')
    expect(owner.user_identities.find_by!(provider: 'google').provider_uid).to eq('new-google-subject')
    get account_authentication_path
    expect(response.body).to include(owner.username)
  end

  it 'returns a generic link-required outcome for a verified email collision' do
    local_user('email_collision', 'social@gmail.com')
    use_identity(verified('unlinked-google-subject'))

    expect { google_auth }.not_to change(User, :count)
    expect(response).to have_http_status(:conflict)
    expect(response_body).to eq('status' => 'error', 'code' => 'link_required')
  end

  it 'does not create accounts for invalid credentials or an unavailable provider' do
    verifier = instance_double(SocialLogin::GoogleIdentityVerifier)
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(verifier)
    allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::InvalidCredential)
    expect { google_auth }.not_to change(User, :count)
    expect(response_body.fetch('code')).to eq('invalid_provider_credential')

    allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::Unavailable)
    google_auth
    expect(response).to have_http_status(:service_unavailable)
    expect(response_body.fetch('code')).to eq('provider_unavailable')
  end

  it 'offers Google signup from Devise registration without replacing the existing form' do
    get new_user_registration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="user[password]"')
    expect(response.body).to include('data-intent="sign_up"')
  end

  it 'does not establish a Web session for an unverified-email identity' do
    use_identity(verified('no-email', nil))
    expect { google_auth }.not_to change(User, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response_body.fetch('code')).to eq('email_verification_required')
    get account_authentication_path
    expect(response).to be_redirect
  end

  it 'rejects a browser callback without the Rails authenticity token' do
    allow_any_instance_of(SocialLoginsController).to receive(:protect_against_forgery?).and_return(true)
    use_identity(verified('csrf-subject'))

    expect { google_auth }.to raise_error(ActionController::InvalidAuthenticityToken)
  end

  it 'links to A, is idempotent, and keeps A authenticated after a conflict with B' do
    principal = local_user('web_link_a')
    other = local_user('web_link_b')
    sign_in principal
    use_identity(verified('link-subject'))

    google_auth(intent: 'link', password: 'password123')
    expect(response_body).to eq('status' => 'success', 'code' => 'linked')
    expect(principal.user_identities.find_by!(provider: 'google').provider_uid).to eq('link-subject')

    google_auth(intent: 'link', password: 'password123')
    expect(response_body.fetch('code')).to eq('already_linked')

    principal.user_identities.destroy_all
    other.user_identities.create!(provider: 'google', provider_uid: 'link-subject')
    google_auth(intent: 'link', password: 'password123')
    expect(response).to have_http_status(:conflict)
    expect(response_body).to eq('status' => 'error', 'code' => 'identity_conflict')
    expect(response.body).not_to include(other.username, other.email, 'token')
    get account_authentication_path
    expect(response.body).to include(principal.username)
    expect(response.body).not_to include(other.username)
  end

  it 'requires fresh password proof before linking' do
    principal = local_user('web_link_reauth')
    sign_in principal
    use_identity(verified('reauth-subject'))

    google_auth(intent: 'link', password: 'incorrect')

    expect(response).to have_http_status(:forbidden)
    expect(response_body.fetch('code')).to eq('reauthentication_required')
    expect(principal.user_identities).to be_empty
  end

  it 'returns authentication_required for an expired Link session and exposes the sign-in route in the UI' do
    principal = local_user('web_expired_link')
    sign_in principal
    get account_authentication_path
    expect(response.body).to include("data-sign-in-url=\"#{new_user_session_path}\"")

    sign_out principal
    google_auth(intent: 'link', password: 'password123')
    expect(response).to have_http_status(:unauthorized)
    expect(response_body).to eq('status' => 'error', 'code' => 'authentication_required')
    expect(principal.user_identities).to be_empty
  end

  it 'keeps the current account when unlink reauthentication fails' do
    principal = local_user('web_unlink_reauth')
    identity = principal.user_identities.create!(provider: 'google', provider_uid: 'reauth-subject')
    sign_in principal

    delete account_social_identity_path(provider: 'google'), params: { current_password: 'incorrect' }

    expect(response).to be_redirect
    expect(identity.reload.user).to eq(principal)
    follow_redirect!
    expect(response.body).to include('Enter your current password')
  end

  it 'rejects unlinking the final Google authentication method' do
    principal = SocialLogin::SignInResolver.new.call(verified_identity: verified('last-method')).user
    sign_in principal

    delete account_social_identity_path(provider: 'google')

    expect(response).to be_redirect
    expect(principal.user_identities.pluck(:provider)).to eq(['google'])
    follow_redirect!
    expect(response.body).to include('Add another sign-in method')
  end

  it 'unlinks only the current user identity and reports an absent identity safely' do
    principal = local_user('web_unlink_a')
    other = local_user('web_unlink_b')
    other_identity = other.user_identities.create!(provider: 'google', provider_uid: 'other-subject')
    principal.user_identities.create!(provider: 'google', provider_uid: 'principal-subject')
    sign_in principal

    delete account_social_identity_path(provider: 'google'), params: { current_password: 'password123' }
    expect(response).to be_redirect
    expect(principal.user_identities).to be_empty
    expect(other_identity.reload.user).to eq(other)

    delete account_social_identity_path(provider: 'google'), params: { current_password: 'password123' }
    follow_redirect!
    expect(response.body).to include('Google is not linked')
  end

  it 'preserves password login and logout session behavior' do
    user = local_user('web_password_login')
    post user_session_path, params: { user: { username: user.username, password: 'password123' } }
    expect(response).to be_redirect
    get account_authentication_path
    expect(response.body).to include(user.username)

    delete destroy_user_session_path
    expect(response).to be_redirect
    get account_authentication_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'switches the Devise principal only after a successful Google sign-in' do
    previous_user = local_user('web_previous_user')
    google_user = local_user('web_google_user')
    google_user.user_identities.create!(provider: 'google', provider_uid: 'switch-subject')
    sign_in previous_user
    use_identity(verified('switch-subject'))

    google_auth
    get account_authentication_path

    expect(response.body).to include(google_user.username)
    expect(response.body).not_to include(previous_user.username)
  end
end
