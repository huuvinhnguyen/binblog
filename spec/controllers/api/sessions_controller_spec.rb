require 'rails_helper'

RSpec.describe Api::SessionsController, type: :controller do
  it 'keeps the current username/password token contract' do
    user = User.create!(username: 'login_user', email: 'login@example.com', password: 'password123')
    post :create, params: { username: 'login_user', password: 'password123' }, format: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['status']).to eq('success')
    expect(body['user']).to include('id' => user.id, 'username' => 'login_user', 'email' => 'login@example.com')
    expect(JWT.decode(body.fetch('token'), Rails.application.secret_key_base, true, algorithm: 'HS256').first['user_id']).to eq(user.id)
  end

  it 'rejects password login for a social-only account' do
    user = SocialLogin::SignInResolver.new.call(
      verified_identity: SocialLogin::VerifiedIdentity.from_verified_claims(
        provider: 'google', provider_uid: 'social-subject', verified_email: 'social@example.com'
      )
    ).user
    post :create, params: { username: user.username, password: 'password123' }, format: :json

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['status']).to eq('error')
  end
end
