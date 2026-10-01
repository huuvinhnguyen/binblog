require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Social authentication API', type: :request do
  let(:verifier) { instance_double(SocialLogin::GoogleIdentityVerifier) }

  before do
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(verifier)
    allow(verifier).to receive(:call).and_return(verified('Google-Subject'))
  end

  def verified(uid, email = 'social@example.com')
    SocialLogin::VerifiedIdentity.from_verified_claims(
      provider: 'google', provider_uid: uid, verified_email: email
    )
  end

  def local_user(name, email = nil)
    User.create!(username: name, email: email || "#{name}@example.com", password: 'password123')
  end

  def bearer(user)
    { 'Authorization' => "Bearer #{SocialLogin::BinblogSession.token_for(user)}" }
  end

  def body
    JSON.parse(response.body)
  end

  def social_session(provider: 'google', credential: 'signed-google-token')
    post '/api/auth/social_sessions',
         params: { provider: provider, credential: credential }, as: :json
  end

  def with_client_ids(mobile:, web:)
    previous_mobile = ENV['GOOGLE_CLIENT_IDS']
    previous_web = ENV['GOOGLE_WEB_CLIENT_ID']
    ENV['GOOGLE_CLIENT_IDS'] = mobile
    ENV['GOOGLE_WEB_CLIENT_ID'] = web
    yield
  ensure
    ENV['GOOGLE_CLIENT_IDS'] = previous_mobile
    ENV['GOOGLE_WEB_CLIENT_ID'] = previous_web
  end

  def signed_audience_credential(audience, key)
    JWT.encode(
      { iss: 'https://accounts.google.com', aud: audience, exp: 10.minutes.from_now.to_i,
        sub: 'api-audience-subject', email: 'api-audience@gmail.com', email_verified: true },
      key, 'RS256', kid: 'api-audience-key'
    )
  end

  def use_real_google_verifier(key)
    jwk = JWT::JWK.new(key.public_key, { kid: 'api-audience-key', alg: 'RS256', use: 'sig' }).export
    keys = instance_double(SocialLogin::GoogleJwks, call: { 'keys' => [jwk] })
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_call_original
    allow(SocialLogin::GoogleJwks).to receive(:new).and_return(keys)
  end

  def link(user, provider: 'google', credential: 'signed-google-token', password: 'password123')
    post '/api/auth/social_identities',
         params: { provider: provider, credential: credential, current_password: password },
         headers: user ? bearer(user) : {}, as: :json
  end

  def unlink(user, provider: 'google', password: 'password123')
    delete "/api/auth/social_identities/#{provider}",
           params: { current_password: password },
           headers: user ? bearer(user) : {}, as: :json
  end

  it 'rejects an oversized social-session request before provider verification' do
    post '/api/auth/social_sessions', params: {
      provider: 'google', credential: 'signed-google-token'
    }, headers: { 'CONTENT_LENGTH' => (Api::AuthRequestSafety::MAX_BODY_BYTES + 1).to_s }, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(body).to eq('status' => 'error', 'code' => 'malformed_request')
    expect(verifier).not_to have_received(:call)
  end

  it 'filters provider credentials and reauthentication passwords from logs' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter('credential' => 'provider-secret', 'current_password' => 'local-secret'))
      .to eq('credential' => '[FILTERED]', 'current_password' => '[FILTERED]')
  end

  it 'keeps the mobile audience configured independently of the Web client ID' do
    key = OpenSSL::PKey::RSA.generate(2048)
    use_real_google_verifier(key)
    with_client_ids(mobile: 'mobile-client', web: 'web-client') do
      social_session(credential: signed_audience_credential('mobile-client', key))
      expect(response).to have_http_status(:ok)
      expect(body.keys).to match_array(%w[status token user])

      social_session(credential: signed_audience_credential('web-client', key))
      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq('status' => 'error', 'code' => 'invalid_provider_credential')
    end
  end

  it 'does not treat blank mobile client IDs as valid audiences' do
    key = OpenSSL::PKey::RSA.generate(2048)
    use_real_google_verifier(key)
    with_client_ids(mobile: ' , ', web: 'web-client') do
      social_session(credential: signed_audience_credential('web-client', key))
      expect(response).to have_http_status(:service_unavailable)
      expect(body).to eq('status' => 'error', 'code' => 'provider_unavailable')
    end
  end

  it 'uses the mobile audience boundary for API Link as well' do
    key = OpenSSL::PKey::RSA.generate(2048)
    use_real_google_verifier(key)
    principal = local_user('audience_link_principal')
    with_client_ids(mobile: 'mobile-client', web: 'web-client') do
      link(principal, credential: signed_audience_credential('web-client', key))
      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq('status' => 'error', 'code' => 'invalid_provider_credential')
      expect(principal.user_identities).to be_empty

      link(principal, credential: signed_audience_credential('mobile-client', key))
      expect(response).to have_http_status(:ok)
      expect(body).to eq('status' => 'success', 'code' => 'linked')
    end
  end

  it 'signs in the identity owner with the existing Binblog JWT shape' do
    owner = local_user('returning')
    owner.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
    social_session

    expect(response).to have_http_status(:ok)
    expect(body.keys).to match_array(%w[status token user])
    expect(body['user']).to eq('id' => owner.id, 'username' => owner.username, 'email' => owner.email)
    claims = JWT.decode(body.fetch('token'), Rails.application.secret_key_base, true, algorithm: 'HS256').first
    expect(claims['user_id']).to eq(owner.id)
    expect(claims['exp']).to be_within(10).of(7.days.from_now.to_i)
  end

  it 'does not sign in a locally disabled identity or create a replacement account' do
    owner = local_user('disabled_identity', 'social@example.com')
    owner.user_identities.create!(
      provider: 'google', provider_uid: 'Google-Subject', disabled_at: Time.current
    )

    expect { social_session }.not_to change(User, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(body).to eq('status' => 'error', 'code' => 'invalid_provider_credential')
  end

  it 'uses the social-session JWT for existing device authorization' do
    owner = local_user('device_owner')
    owner.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
    device = Device.create!(name: 'Owned device', chip_id: 'social_owned_device', device_info: '{}')
    owner.devices << device
    social_session
    token = body.fetch('token')

    get '/api/devices', headers: { 'Authorization' => "Bearer #{token}" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch('devices').map { |row| row.fetch('chip_id') })
      .to include('social_owned_device')
  end

  it 'creates a social account and identity before issuing its Binblog JWT' do
    social_session
    expect(response).to have_http_status(:ok)
    owner = User.find(body.fetch('user').fetch('id'))
    expect(owner.user_identities.pluck(:provider, :provider_uid)).to eq([['google', 'Google-Subject']])
    expect(JWT.decode(body.fetch('token'), Rails.application.secret_key_base, true, algorithm: 'HS256').first['user_id'])
      .to eq(owner.id)
  end

  it 'accepts the same valid Google ID token twice for the same persisted owner' do
    signing_key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(signing_key.public_key, { kid: 'repeat-key', alg: 'RS256', use: 'sig' }).export
    credential = JWT.encode(
      { iss: 'https://accounts.google.com', aud: 'request-client', exp: 10.minutes.from_now.to_i,
        sub: 'repeat-subject', email: 'repeat@gmail.com', email_verified: true },
      signing_key, 'RS256', kid: 'repeat-key'
    )
    keys = instance_double(SocialLogin::GoogleJwks)
    allow(keys).to receive(:call).and_return('keys' => [jwk])
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_call_original
    real_verifier = SocialLogin::GoogleIdentityVerifier.new(jwks: keys, audiences: ['request-client'])
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(real_verifier)

    expect { social_session(credential: credential) }.to change(User, :count).by(1)
      .and change(UserIdentity, :count).by(1)
    expect(response).to have_http_status(:ok)
    first_user_id = body.fetch('user').fetch('id')
    expect { social_session(credential: credential) }.to change(User, :count).by(0)
      .and change(UserIdentity, :count).by(0)
    expect(response).to have_http_status(:ok)
    expect(body.fetch('user').fetch('id')).to eq(first_user_id)
    expect(User.find(first_user_id).user_identities.pluck(:provider, :provider_uid))
      .to eq([['google', 'repeat-subject']])
  end

  it 'returns link_required without linking an existing email' do
    owner = local_user('existing_email', 'social@example.com')
    social_session

    expect(response).to have_http_status(:conflict)
    expect(body).to eq('status' => 'error', 'code' => 'link_required')
    expect(owner.user_identities.count).to eq(0)
  end

  it 'does not create an account for an invalid credential' do
    allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::InvalidCredential)
    expect { social_session }.not_to change(User, :count)
    expect(body).to eq('status' => 'error', 'code' => 'invalid_provider_credential')
    expect(response).to have_http_status(:unauthorized)
  end

  it 'reports unsupported provider and malformed request before verification' do
    social_session(provider: 'other')
    expect(body['code']).to eq('unsupported_provider')
    expect(response).to have_http_status(:unprocessable_entity)
    social_session(credential: '')
    expect(body['code']).to eq('malformed_request')
    expect(response).to have_http_status(:bad_request)
    expect(verifier).not_to have_received(:call)
  end

  it 'reports missing verified email and provider verification failure' do
    allow(verifier).to receive(:call).and_return(verified('without-email', nil))
    social_session
    expect(body['code']).to eq('email_verification_required')
    expect(response).to have_http_status(:unprocessable_entity)

    allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::Unavailable)
    social_session
    expect(body['code']).to eq('provider_unavailable')
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'returns provider_unavailable without creating an identity for malformed upstream keys' do
    signing_key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(signing_key.public_key, { kid: 'request-key' }).export
    credential = JWT.encode(
      { iss: 'https://accounts.google.com', aud: 'request-client', exp: 10.minutes.from_now.to_i,
        sub: 'request-subject', email: 'request@gmail.com', email_verified: true },
      signing_key, 'RS256', kid: 'request-key'
    )
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_call_original
    real_verifier = SocialLogin::GoogleIdentityVerifier.new(audiences: ['request-client'])
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(real_verifier)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    [jwk.merge(n: 123), jwk.merge(e: []), jwk.reject { |field, _| field == :n }].each do |bad_key|
      Rails.cache.clear
      stub_request(:get, SocialLogin::GoogleJwks::URL.to_s).to_return(
        status: 200, body: { keys: [bad_key] }.to_json
      )
      expect { social_session(credential: credential) }.not_to change(User, :count)
      expect(response).to have_http_status(:service_unavailable)
      expect(body).to eq('status' => 'error', 'code' => 'provider_unavailable')
      expect(UserIdentity.exists?(provider: 'google', provider_uid: 'request-subject')).to be(false)
    end
  end

  it 'returns provider_unavailable for an upstream HTTP protocol failure' do
    signing_key = OpenSSL::PKey::RSA.generate(2048)
    credential = JWT.encode(
      { iss: 'https://accounts.google.com', aud: 'request-client', exp: 10.minutes.from_now.to_i,
        sub: 'request-subject' }, signing_key, 'RS256', kid: 'request-key'
    )
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_call_original
    real_verifier = SocialLogin::GoogleIdentityVerifier.new(audiences: ['request-client'])
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(real_verifier)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    stub_request(:get, SocialLogin::GoogleJwks::URL.to_s)
      .to_raise(Net::HTTPBadResponse.new('invalid upstream protocol'))

    expect { social_session(credential: credential) }.not_to change(User, :count)
    expect(response).to have_http_status(:service_unavailable)
    expect(body).to eq('status' => 'error', 'code' => 'provider_unavailable')
    expect(UserIdentity.exists?(provider: 'google', provider_uid: 'request-subject')).to be(false)
  end

  it 'returns a stable internal error for account persistence failure' do
    allow_any_instance_of(SocialLogin::SignInResolver).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(User.new))
    social_session
    expect(response).to have_http_status(:internal_server_error)
    expect(body).to eq('status' => 'error', 'code' => 'internal_error')
  end

  it 'links an unused identity to authenticated A after password reauthentication' do
    principal = local_user('principal')
    link(principal)
    expect(body).to eq('status' => 'success', 'code' => 'linked')
    expect(principal.user_identities.find_by!(provider: 'google').provider_uid).to eq('Google-Subject')
  end

  it 'returns an idempotent result when A repeats Link with the same credential' do
    principal = local_user('principal')
    link(principal)
    expect(body).to eq('status' => 'success', 'code' => 'linked')
    link(principal)
    expect(body).to eq('status' => 'success', 'code' => 'already_linked')
    expect(principal.user_identities.count).to eq(1)
    expect(principal.user_identities.first.provider_uid).to eq('Google-Subject')
  end

  it 'rejects B-owned identity without switching A or exposing B' do
    principal = local_user('principal')
    other = local_user('other')
    identity = other.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
    link(principal)
    expect(response).to have_http_status(:conflict)
    expect(body).to eq('status' => 'error', 'code' => 'identity_conflict')
    expect(identity.reload.user).to eq(other)
    expect(principal.user_identities.count).to eq(0)
    expect(response.body).not_to include(other.email, other.username, 'token')
  end

  it 'rejects another Google identity for A with a stable conflict' do
    principal = local_user('principal')
    principal.user_identities.create!(provider: 'google', provider_uid: 'First-Subject')
    link(principal)
    expect(body['code']).to eq('provider_already_linked')
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects unauthenticated, expired, and unreauthenticated Link requests' do
    link(nil)
    expect(body['code']).to eq('authentication_required')
    expect(response).to have_http_status(:unauthorized)

    principal = local_user('principal')
    link(principal, password: 'wrong')
    expect(body['code']).to eq('reauthentication_required')
    expect(principal.user_identities.count).to eq(0)

    expired = JWT.encode({ user_id: principal.id, exp: 1.minute.ago.to_i }, Rails.application.secret_key_base)
    post '/api/auth/social_identities',
         params: { provider: 'google', credential: 'signed-google-token', current_password: 'password123' },
         headers: { 'Authorization' => "Bearer #{expired}" }, as: :json
    expect(body['code']).to eq('authentication_required')
    expect(principal.user_identities.count).to eq(0)
  end

  it 'rejects an invalid Google credential during Link without mutating ownership' do
    principal = local_user('principal')
    allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::InvalidCredential)
    link(principal)
    expect(response).to have_http_status(:unauthorized)
    expect(body).to eq('status' => 'error', 'code' => 'invalid_provider_credential')
    expect(principal.user_identities.count).to eq(0)
  end

  it 'unlinks an owned identity with another method and reports not_linked after retry' do
    principal = local_user('principal')
    principal.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
    unlink(principal)
    expect(body).to eq('status' => 'success', 'code' => 'unlinked')
    expect(principal.user_identities.count).to eq(0)
    unlink(principal)
    expect(body).to eq('status' => 'success', 'code' => 'not_linked')
  end

  it 'blocks removal of the final authentication method' do
    principal = SocialLogin::SignInResolver.new.call(verified_identity: verified('social-only')).user
    unlink(principal)
    expect(response).to have_http_status(:conflict)
    expect(body['code']).to eq('last_authentication_method')
    expect(principal.user_identities.count).to eq(1)
  end

  it 'holds a passwordless multi-provider unlink until a safe reauthentication path exists' do
    principal = SocialLogin::SignInResolver.new.call(verified_identity: verified('social-only')).user
    principal.user_identities.create!(provider: 'alternate', provider_uid: 'other-subject')
    allow(SocialLogin::ProviderPolicy).to receive(:enabled?).and_call_original
    allow(SocialLogin::ProviderPolicy).to receive(:enabled?).with('alternate').and_return(true)
    unlink(principal)
    expect(response).to have_http_status(:forbidden)
    expect(body['code']).to eq('reauthentication_required')
    expect(principal.user_identities.pluck(:provider)).to contain_exactly('google', 'alternate')
  end

  it 'cannot remove another user identity or expose its owner' do
    principal = local_user('principal')
    other = local_user('other')
    identity = other.user_identities.create!(provider: 'google', provider_uid: 'Other-Subject')
    unlink(principal)
    expect(body).to eq('status' => 'success', 'code' => 'not_linked')
    expect(identity.reload.user).to eq(other)
    expect(response.body).not_to include(other.username, other.email)
  end

  it 'requires authentication and recent password proof for Unlink' do
    unlink(nil)
    expect(body['code']).to eq('authentication_required')
    principal = local_user('principal')
    principal.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
    unlink(principal, password: 'wrong')
    expect(response).to have_http_status(:forbidden)
    expect(body['code']).to eq('reauthentication_required')
    expect(principal.user_identities.count).to eq(1)
  end
end
