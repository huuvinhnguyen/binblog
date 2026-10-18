require 'swagger_helper'

RSpec.describe 'Social authentication API documentation', type: :request do
  let(:verifier) { instance_double(SocialLogin::GoogleIdentityVerifier) }
  let(:identity) do
    SocialLogin::VerifiedIdentity.from_verified_claims(
      provider: 'google', provider_uid: 'Google-Subject', verified_email: 'owner@example.com'
    )
  end
  let(:user) { User.create!(username: 'social_docs', email: 'social_docs@example.com', password: 'password123') }
  let(:Authorization) { "Bearer #{SocialLogin::BinblogSession.token_for(user)}" }

  before do
    allow(SocialLogin::GoogleIdentityVerifier).to receive(:new).and_return(verifier)
    allow(verifier).to receive(:call).and_return(identity)
  end

  path '/api/auth/social_sessions' do
    post 'Exchange a verified provider credential for a Binblog session' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      description 'Google ID token is verified server-side. Client email, UID, and verified flags are ignored. Returning and newly created accounts receive the normal Binblog JWT.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: %w[provider credential], properties: {
          provider: { type: :string, enum: ['google'] },
          credential: { type: :string, description: 'Google-issued ID token.' }
        }
      }
      let(:payload) { { provider: 'google', credential: 'signed-google-token' } }

      response '400', 'malformed request' do
        let(:payload) { { provider: 'google', credential: '' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['malformed_request'] }
        }
        run_test!
      end
      response '200', 'existing or newly created Binblog session' do
        schema type: :object, required: %w[status token user], properties: {
          status: { type: :string, enum: ['success'] }, token: { type: :string },
          user: { type: :object, required: %w[id username email], properties: {
            id: { type: :integer }, username: { type: :string }, email: { type: :string }
          } }
        }
        run_test!
      end
      response '401', 'invalid or expired provider credential' do
        before { allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::InvalidCredential) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] },
          code: { type: :string, enum: ['invalid_provider_credential'] }
        }
        run_test!
      end
      response '409', 'verified email matches an existing account; explicit Link required' do
        before { User.create!(username: 'email_owner', email: 'owner@example.com', password: 'password123') }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['link_required'] }
        }
        run_test!
      end
      response '422', 'verified contact email unavailable for signup' do
        let(:identity) do
          SocialLogin::VerifiedIdentity.from_verified_claims(
            provider: 'google', provider_uid: 'No-Email', verified_email: nil
          )
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] },
          code: { type: :string, enum: ['email_verification_required', 'unsupported_provider'] }
        }
        run_test!
      end
      response '500', 'identity persistence failure' do
        before { allow_any_instance_of(SocialLogin::SignInResolver).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(User.new)) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['internal_error'] }
        }
        run_test!
      end
      response '503', 'provider verification unavailable or username allocation failed' do
        before { allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::Unavailable) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] },
          code: { type: :string, enum: ['provider_unavailable', 'username_unavailable'] }
        }
        run_test!
      end
    end
  end

  path '/api/auth/social_identities' do
    post 'Link a Google identity to the authenticated Binblog user' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Requires a Binblog Bearer JWT plus either a purpose-bound reauthentication token or the legacy current_password compatibility field. Link preserves the authenticated principal.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: %w[provider credential], properties: {
          provider: { type: :string, enum: ['google'] },
          credential: { type: :string, description: 'Valid, unexpired Google ID token verified by the server for this request.' },
          reauthentication_token: { type: :string, description: 'Preferred one-time link_identity grant.' },
          current_password: { type: :string, format: :password, description: 'Legacy compatibility reauthentication.' }
        }
      }
      let(:payload) { { provider: 'google', credential: 'signed-google-token', current_password: 'password123' } }

      response '400', 'malformed request' do
        let(:payload) { { provider: 'google', credential: '', current_password: 'password123' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['malformed_request'] }
        }
        run_test!
      end
      response '200', 'linked or already linked to the same user' do
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['success'] },
          code: { type: :string, enum: ['linked', 'already_linked'] }
        }
        run_test!
      end
      response '401', 'Binblog authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['authentication_required', 'invalid_provider_credential'] }
        }
        run_test!
      end
      response '403', 'fresh local-password proof required' do
        let(:payload) { { provider: 'google', credential: 'signed-google-token', current_password: 'wrong' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['reauthentication_required'] }
        }
        run_test!
      end
      response '422', 'unsupported provider' do
        let(:payload) { { provider: 'other', credential: 'signed-google-token', current_password: 'password123' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['unsupported_provider'] }
        }
        run_test!
      end
      response '500', 'identity persistence failure' do
        before { allow_any_instance_of(SocialLogin::LinkIdentity).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(UserIdentity.new)) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['internal_error'] }
        }
        run_test!
      end
      response '503', 'provider verification unavailable' do
        before { allow(verifier).to receive(:call).and_raise(SocialLogin::GoogleIdentityVerifier::Unavailable) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['provider_unavailable'] }
        }
        run_test!
      end
      response '409', 'identity belongs to another user or provider already linked' do
        before do
          owner = User.create!(username: 'other_owner', email: 'other_owner@example.com', password: 'password123')
          owner.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] },
          code: { type: :string, enum: ['identity_conflict', 'provider_already_linked'] }
        }
        run_test!
      end
    end
  end

  path '/api/auth/social_identities/{provider}' do
    delete 'Unlink an owned Google identity' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Requires a Binblog Bearer JWT plus either a purpose-bound reauthentication token or legacy current_password. Already absent identity returns not_linked. The server rechecks the final usable method under lock.'
      parameter name: :provider, in: :path, type: :string, required: true, enum: ['google']
      parameter name: :payload, in: :body, required: false, schema: {
        type: :object, properties: {
          reauthentication_token: { type: :string, description: 'Preferred one-time unlink_identity grant.' },
          current_password: { type: :string, format: :password, description: 'Legacy compatibility reauthentication.' }
        }
      }
      let(:provider) { 'google' }
      let(:payload) { { current_password: 'password123' } }

      response '422', 'unsupported provider' do
        let(:provider) { 'other' }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['unsupported_provider'] }
        }
        run_test!
      end
      response '200', 'unlinked or already absent' do
        before { user.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject') }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['success'] }, code: { type: :string, enum: ['unlinked', 'not_linked'] }
        }
        run_test!
      end
      response '401', 'Binblog authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['authentication_required'] }
        }
        run_test!
      end
      response '403', 'fresh local-password proof required' do
        before { user.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject') }
        let(:payload) { { current_password: 'wrong' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['reauthentication_required'] }
        }
        run_test!
      end
      response '500', 'identity persistence failure' do
        before do
          user.user_identities.create!(provider: 'google', provider_uid: 'Google-Subject')
          allow_any_instance_of(SocialLogin::UnlinkIdentity).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(UserIdentity.new))
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['internal_error'] }
        }
        run_test!
      end
      response '409', 'cannot remove the final authentication method' do
        let(:user) do
          SocialLogin::SignInResolver.new.call(verified_identity: identity).user
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['last_authentication_method'] }
        }
        run_test!
      end
    end
  end
end
