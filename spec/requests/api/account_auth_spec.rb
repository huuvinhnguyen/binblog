require 'rails_helper'

RSpec.describe 'Account authentication management API', type: :request do
  let(:verifier) { instance_double(SocialLogin::GoogleIdentityVerifier) }

  before do
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(verifier)
    allow(verifier).to receive(:call).and_return(verified('Google-Subject'))
    ActionMailer::Base.deliveries.clear
  end

  def verified(uid, email: 'social@gmail.com', issued_at: Time.current)
    SocialLogin::VerifiedIdentity.from_verified_claims(
      provider: 'google', provider_uid: uid, verified_email: email, issued_at: issued_at
    )
  end

  def password_user(name = 'password_user')
    User.create!(username: name, email: "#{name}@example.com", password: 'password123')
  end

  def social_user(uid = 'social-subject', email: 'social@gmail.com')
    SocialLogin::SignInResolver.new.call(verified_identity: verified(uid, email: email)).user
  end

  def bearer_token(user)
    SocialLogin::BinblogSession.token_for(user)
  end

  def headers(token)
    { 'Authorization' => "Bearer #{token}" }
  end

  def body
    JSON.parse(response.body)
  end

  def issue_grant(user:, token:, purpose:, method: 'password', provider: nil, expires_at: nil)
    result = Reauthentication::GrantIssuer.new.call(
      user: user,
      session_binding_digest: Reauthentication::SessionBinding.for_bearer(token),
      purpose: purpose,
      method: method,
      provider: provider
    )
    grant = user.reauthentication_grants.order(:id).last
    grant.update_column(:expires_at, expires_at) if expires_at
    [result.token, grant]
  end

  describe 'GET /api/auth/methods' do
    it 'returns only the current user usable-method projection' do
      user = social_user
      identity = user.user_identities.first
      user.user_recovery_codes.create!(
        code_digest: Authentication::SecretDigest.call('a' * 32, purpose: 'user-recovery-code')
      )

      get '/api/auth/methods', headers: headers(bearer_token(user)), as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to eq(
        'status' => 'success',
        'password' => { 'usable' => false },
        'providers' => [{ 'provider' => 'google', 'usable' => true, 'can_unlink' => false }],
        'recovery' => { 'codes_enrolled' => true }
      )
      expect(response.body).not_to include(identity.provider_uid, user.email)
    end

    it 'marks a locally disabled identity unusable and requires a valid JWT' do
      user = social_user
      user.user_identities.first.update!(disabled_at: Time.current)

      get '/api/auth/methods', headers: headers(bearer_token(user)), as: :json
      expect(body.dig('providers', 0)).to include('usable' => false, 'can_unlink' => false)

      get '/api/auth/methods', headers: headers('invalid'), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(body).to eq('status' => 'error', 'code' => 'authentication_required')
    end
  end

  describe 'POST /api/auth/reauthentications' do
    it 'issues a five-minute, digest-only, JWT-bound password grant' do
      user = password_user
      token = bearer_token(user)

      post '/api/auth/reauthentications', params: {
        purpose: 'unlink_identity', method: 'password', password: 'password123'
      }, headers: headers(token), as: :json

      expect(response).to have_http_status(:ok)
      raw_grant = body.fetch('reauthentication_token')
      grant = user.reauthentication_grants.last
      expect(grant.token_digest).to eq(
        Authentication::SecretDigest.call(raw_grant, purpose: 'reauthentication-grant')
      )
      expect(grant.session_binding_digest).to eq(Reauthentication::SessionBinding.for_bearer(token))
      expect(grant.expires_at).to be_within(5.seconds).of(5.minutes.from_now)
      expect(grant.consumed_at).to be_nil
      expect(grant.attributes.values).not_to include(raw_grant, 'password123')
    end

    it 'rejects wrong password and arbitrary purposes without creating a grant' do
      user = password_user
      token = bearer_token(user)

      post '/api/auth/reauthentications', params: {
        purpose: 'unlink_identity', method: 'password', password: 'wrong'
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(body['code']).to eq('reauthentication_failed')

      post '/api/auth/reauthentications', params: {
        purpose: 'arbitrary', method: 'password', password: 'password123'
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:bad_request)
      expect(user.reauthentication_grants).to be_empty
    end

    it 'accepts only a fresh credential for an enabled identity owned by the current user' do
      user = social_user('owned-subject')
      token = bearer_token(user)
      allow(verifier).to receive(:call).and_return(verified('owned-subject'))

      post '/api/auth/reauthentications', params: {
        purpose: 'add_password', method: 'google', credential: 'fresh-token'
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reauthentication_grants.last).to have_attributes(method: 'google', provider: 'google')

      allow(verifier).to receive(:call).and_return(verified('owned-subject', issued_at: 10.minutes.ago))
      post '/api/auth/reauthentications', params: {
        purpose: 'add_password', method: 'google', credential: 'stale-token'
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)

      user.user_identities.first.update!(disabled_at: Time.current)
      allow(verifier).to receive(:call).and_return(verified('owned-subject'))
      post '/api/auth/reauthentications', params: {
        purpose: 'add_password', method: 'google', credential: 'fresh-token'
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(body).to eq('status' => 'error', 'code' => 'reauthentication_failed')
    end

    it 'fails generically when the provider identity belongs to another account' do
      user = social_user('current-subject', email: 'current@gmail.com')
      other = password_user('other_owner')
      other.user_identities.create!(provider: 'google', provider_uid: 'other-subject')
      allow(verifier).to receive(:call).and_return(verified('other-subject'))

      post '/api/auth/reauthentications', params: {
        purpose: 'add_password', method: 'google', credential: 'other-token'
      }, headers: headers(bearer_token(user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(body).to eq('status' => 'error', 'code' => 'reauthentication_failed')
      expect(response.body).not_to include(other.username, other.email)
    end
  end

  describe 'PUT /api/auth/password' do
    it 'requires a reauthentication grant when the token is omitted' do
      user = social_user('missing-add-password-grant')
      token = bearer_token(user)

      put '/api/auth/password', params: {
        username: 'missing_grant', password: 'newpassword123',
        password_confirmation: 'newpassword123'
      }, headers: headers(token), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(body).to eq('status' => 'error', 'code' => 'reauthentication_required')
      expect(user.reload.usable_password_authentication?).to be(false)
    end

    it 'adds the first password and consumes the matching grant atomically' do
      user = social_user
      token = bearer_token(user)
      raw_grant, grant = issue_grant(user: user, token: token, purpose: 'add_password', method: 'google', provider: 'google')

      put '/api/auth/password', params: {
        username: 'chosen_username', password: 'newpassword123',
        password_confirmation: 'newpassword123', reauthentication_token: raw_grant
      }, headers: headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to eq('status' => 'success', 'code' => 'password_added')
      expect(user.reload).to have_attributes(username: 'chosen_username')
      expect(user.valid_password?('newpassword123')).to be(true)
      expect(grant.reload.consumed_at).to be_present
    end

    it 'rejects existing passwords, expired/consumed/wrong-purpose grants, and another JWT' do
      existing = password_user('already_password')
      existing_token = bearer_token(existing)
      raw, = issue_grant(user: existing, token: existing_token, purpose: 'add_password')
      put '/api/auth/password', params: {
        username: existing.username, password: 'replacement123', password_confirmation: 'replacement123',
        reauthentication_token: raw
      }, headers: headers(existing_token), as: :json
      expect(response).to have_http_status(:conflict)
      expect(existing.reload.valid_password?('password123')).to be(true)

      user = social_user('grant-cases', email: 'grant-cases@gmail.com')
      token = bearer_token(user)
      other_token = JWT.encode(
        { user_id: user.id, exp: 6.days.from_now.to_i }, Rails.application.secret_key_base, 'HS256'
      )
      raw, grant = issue_grant(user: user, token: token, purpose: 'add_password')
      put '/api/auth/password', params: {
        username: 'grant_cases', password: 'newpassword123', password_confirmation: 'newpassword123',
        reauthentication_token: raw
      }, headers: headers(other_token), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(grant.reload.consumed_at).to be_nil

      grant.update!(expires_at: 1.minute.ago)
      put '/api/auth/password', params: {
        username: 'grant_cases', password: 'newpassword123', password_confirmation: 'newpassword123',
        reauthentication_token: raw
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)

      wrong_raw, = issue_grant(user: user, token: token, purpose: 'unlink_identity')
      put '/api/auth/password', params: {
        username: 'grant_cases', password: 'newpassword123', password_confirmation: 'newpassword123',
        reauthentication_token: wrong_raw
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'rolls back grant consumption when username or password validation fails' do
      password_user('taken_username')
      user = social_user('validation-case', email: 'validation-case@gmail.com')
      token = bearer_token(user)
      raw, grant = issue_grant(user: user, token: token, purpose: 'add_password')

      put '/api/auth/password', params: {
        username: 'taken_username', password: 'short', password_confirmation: 'short',
        reauthentication_token: raw
      }, headers: headers(token), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['code']).to eq('username_unavailable')
      expect(grant.reload.consumed_at).to be_nil
      expect(user.reload.usable_password_authentication?).to be(false)
    end
  end

  describe 'POST /api/auth/recovery_codes' do
    it 'requires a reauthentication grant when the token is omitted' do
      user = password_user('missing-recovery-grant')
      token = bearer_token(user)

      post '/api/auth/recovery_codes', headers: headers(token), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(body).to eq('status' => 'error', 'code' => 'reauthentication_required')
      expect(user.user_recovery_codes).to be_empty
    end

    it 'returns high-entropy codes once and atomically invalidates the old set' do
      user = password_user('recovery_owner')
      token = bearer_token(user)
      raw, first_grant = issue_grant(user: user, token: token, purpose: 'rotate_recovery_codes')

      post '/api/auth/recovery_codes', params: { reauthentication_token: raw },
           headers: headers(token), as: :json
      expect(response).to have_http_status(:ok)
      first_codes = body.fetch('codes')
      expect(first_codes.length).to eq(10)
      expect(first_codes.uniq.length).to eq(10)
      expect(user.user_recovery_codes.unused.count).to eq(10)
      expect(first_grant.reload.consumed_at).to be_present
      expect(user.user_recovery_codes.pluck(:code_digest).map(&:to_s)).not_to include(*first_codes)

      second_raw, = issue_grant(user: user, token: token, purpose: 'rotate_recovery_codes')
      post '/api/auth/recovery_codes', params: { reauthentication_token: second_raw },
           headers: headers(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(user.user_recovery_codes.unused.count).to eq(10)
      expect(user.user_recovery_codes.where.not(used_at: nil).count).to eq(10)

      post '/api/auth/recovery_codes', params: { reauthentication_token: second_raw },
           headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'password recovery policy' do
    it 'returns the same accepted response without enumerating account type' do
      password_account = password_user('reset_password')
      social_without_codes = social_user('no-codes', email: 'no-codes@gmail.com')
      social_with_codes = social_user('with-codes', email: 'with-codes@gmail.com')
      social_with_codes.user_recovery_codes.create!(
        code_digest: Authentication::SecretDigest.call('b' * 32, purpose: 'user-recovery-code')
      )

      [
        'unknown@example.com', password_account.email,
        social_without_codes.email, social_with_codes.email
      ].each do |email|
        post '/api/auth/password_recovery', params: { email: email }, as: :json
        expect(response).to have_http_status(:accepted)
        expect(body).to eq('status' => 'accepted')
      end

      expect(password_account.reload.reset_password_token).to be_present
      expect(social_without_codes.reload.reset_password_token).to be_nil
      expect(social_with_codes.reload.reset_password_token).to be_nil
      expect(ActionMailer::Base.deliveries.length).to eq(2)
    end

    it 'preserves password-account reset and its provider identity' do
      user = password_user('mixed_reset')
      user.user_identities.create!(provider: 'google', provider_uid: 'mixed-subject')
      raw_token = user.send_reset_password_instructions

      put '/api/auth/password_recovery', params: {
        recovery_token: raw_token,
        password: 'resetpassword123', password_confirmation: 'resetpassword123'
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to eq('status' => 'success', 'code' => 'password_updated')
      expect(user.reload.valid_password?('resetpassword123')).to be(true)
      expect(user.user_identities.pluck(:provider_uid)).to eq(['mixed-subject'])
      expect(response.body).not_to include('token')
    end

    it 'requires email challenge plus an unused recovery code for a social-only account' do
      user = social_user('recover-social', email: 'recover-social@gmail.com')
      raw_code = SecureRandom.hex(16).scan(/.{4}/).join('-')
      digest = Authentication::SecretDigest.call(
        UserRecoveryCode.normalize(raw_code), purpose: 'user-recovery-code'
      )
      user.user_recovery_codes.create!(code_digest: digest)
      token = Authentication::SocialRecoveryChallenge.new.issue(user)

      put '/api/auth/password_recovery', params: {
        recovery_token: token, username: 'recovered_user',
        password: 'recovered123', password_confirmation: 'recovered123'
      }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['code']).to eq('invalid_or_expired_recovery')

      put '/api/auth/password_recovery', params: {
        recovery_token: token, recovery_code: raw_code, username: 'recovered_user',
        password: 'recovered123', password_confirmation: 'recovered123'
      }, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reload.valid_password?('recovered123')).to be(true)
      expect(user.user_identities.pluck(:provider_uid)).to eq(['recover-social'])
      expect(user.user_recovery_codes.unused).to be_empty
      expect(response.body).not_to include('token')

      put '/api/auth/password_recovery', params: {
        recovery_token: token, recovery_code: raw_code, username: 'recovered_user',
        password: 'another123', password_confirmation: 'another123'
      }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to eq('status' => 'error', 'code' => 'invalid_or_expired_recovery')
    end

    it 'blocks ordinary Devise reset issuance and stale-token completion for social-only users' do
      user = social_user('devise-guard', email: 'devise-guard@gmail.com')
      expect(user.send_reset_password_instructions).to be_nil
      expect(user.reload.reset_password_token).to be_nil

      stale_raw_token = user.send(:set_reset_password_token)
      recovered = User.reset_password_by_token(
        reset_password_token: stale_raw_token,
        password: 'unsafe123', password_confirmation: 'unsafe123'
      )
      expect(recovered.errors[:reset_password_token]).to be_present
      expect(user.reload.usable_password_authentication?).to be(false)
    end
  end

  describe 'preferred Link and Unlink grants' do
    it 'links idempotently with one-time grants and never changes the principal' do
      user = password_user('grant_link')
      token = bearer_token(user)
      raw, grant = issue_grant(user: user, token: token, purpose: 'link_identity')

      post '/api/auth/social_identities', params: {
        provider: 'google', credential: 'target-token', reauthentication_token: raw
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(body['code']).to eq('linked')
      expect(user.user_identities.first.provider_uid).to eq('Google-Subject')
      expect(grant.reload.consumed_at).to be_present

      post '/api/auth/social_identities', params: {
        provider: 'google', credential: 'target-token', reauthentication_token: raw
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:forbidden)

      retry_raw, = issue_grant(user: user, token: token, purpose: 'link_identity')
      post '/api/auth/social_identities', params: {
        provider: 'google', credential: 'target-token', reauthentication_token: retry_raw
      }, headers: headers(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(body['code']).to eq('already_linked')
      expect(user.user_identities.count).to eq(1)
    end

    it 'unlinks with a grant while recomputing the final method before consumption' do
      user = password_user('grant_unlink')
      user.user_identities.create!(provider: 'google', provider_uid: 'unlink-subject')
      token = bearer_token(user)
      raw, grant = issue_grant(user: user, token: token, purpose: 'unlink_identity')

      delete '/api/auth/social_identities/google', params: { reauthentication_token: raw },
             headers: headers(token), as: :json
      expect(response).to have_http_status(:ok)
      expect(body['code']).to eq('unlinked')
      expect(grant.reload.consumed_at).to be_present

      social = social_user('last-provider', email: 'last-provider@gmail.com')
      social_token = bearer_token(social)
      last_raw, last_grant = issue_grant(user: social, token: social_token, purpose: 'unlink_identity')
      delete '/api/auth/social_identities/google', params: { reauthentication_token: last_raw },
             headers: headers(social_token), as: :json
      expect(response).to have_http_status(:conflict)
      expect(body['code']).to eq('last_authentication_method')
      expect(last_grant.reload.consumed_at).to be_nil
    end
  end
end
