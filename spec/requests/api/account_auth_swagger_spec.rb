require 'swagger_helper'

RSpec.describe 'Account authentication management API documentation', type: :request do
  let(:user) { User.create!(username: 'auth_docs', email: 'auth_docs@example.com', password: 'password123') }
  let(:raw_jwt) { SocialLogin::BinblogSession.token_for(user) }
  let(:Authorization) { "Bearer #{raw_jwt}" }

  def passwordless_docs_user(username)
    User.build_for_verified_social_signup(
      username: username, email: "#{username}@example.com"
    ).tap(&:save!)
  end

  def reauthentication_token_for(user:, jwt:, purpose:)
    Reauthentication::GrantIssuer.new.call(
      user: user,
      session_binding_digest: Reauthentication::SessionBinding.for_bearer(jwt),
      purpose: purpose,
      method: 'google',
      provider: 'google'
    ).token
  end

  path '/api/auth/methods' do
    get 'List current user authentication methods' do
      tags 'Authentication'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Returns password usability, linked provider usability, advisory can_unlink, and recovery-code enrollment. It never returns provider UID or external account data.'

      response '200', 'authentication method projection' do
        schema type: :object, required: %w[status password providers recovery], properties: {
          status: { type: :string, enum: ['success'] },
          password: { type: :object, required: ['usable'], properties: { usable: { type: :boolean } } },
          providers: { type: :array, items: { type: :object, required: %w[provider usable can_unlink], properties: {
            provider: { type: :string }, usable: { type: :boolean }, can_unlink: { type: :boolean }
          } } },
          recovery: { type: :object, required: ['codes_enrolled'], properties: { codes_enrolled: { type: :boolean } } }
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
    end
  end

  path '/api/auth/reauthentications' do
    post 'Create a short-lived reauthentication grant' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Verifies the current password or a fresh credential for an enabled identity already owned by the current user. The returned grant is JWT-bound, purpose-bound, five-minute, and one-time.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: %w[purpose method], properties: {
          purpose: { type: :string, enum: ReauthenticationGrant::PURPOSES },
          method: { type: :string, enum: ReauthenticationGrant::METHODS },
          password: { type: :string, format: :password },
          credential: { type: :string }
        }
      }
      let(:payload) { { purpose: 'add_password', method: 'password', password: 'password123' } }

      response '200', 'reauthentication grant issued' do
        schema type: :object, required: %w[status reauthentication_token expires_at], properties: {
          status: { type: :string, enum: ['success'] },
          reauthentication_token: { type: :string }, expires_at: { type: :string, format: :'date-time' }
        }
        run_test!
      end

      response '403', 'reauthentication failed without disclosing provider ownership' do
        let(:payload) { { purpose: 'add_password', method: 'password', password: 'wrong' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['reauthentication_failed'] }
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

      response '422', 'unsupported reauthentication method or provider' do
        let(:payload) { { purpose: 'add_password', method: 'facebook', credential: 'provider-token' } }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] },
          code: { type: :string, enum: %w[unsupported_method unsupported_provider] }
        }
        run_test!
      end

      response '429', 'reauthentication attempts rate limited' do
        before { allow_any_instance_of(Authentication::RateLimiter).to receive(:allowed?).and_return(false) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['rate_limited'] }
        }
        run_test!
      end

      response '503', 'provider verification unavailable' do
        let(:payload) { { purpose: 'add_password', method: 'google', credential: 'provider-token' } }
        before do
          allow_any_instance_of(SocialLogin::GoogleIdentityVerifier).to receive(:call)
            .and_raise(SocialLogin::GoogleIdentityVerifier::Unavailable)
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['provider_unavailable'] }
        }
        run_test!
      end
    end
  end

  path '/api/auth/password' do
    put 'Establish the first usable password' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Only passwordless accounts may use this operation. It consumes an add_password grant and confirms or changes the username.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: %w[username password password_confirmation reauthentication_token], properties: {
          username: { type: :string }, password: { type: :string, format: :password },
          password_confirmation: { type: :string, format: :password }, reauthentication_token: { type: :string }
        }
      }
      let(:payload) { { username: user.username, password: 'newpassword123', password_confirmation: 'newpassword123', reauthentication_token: 'unused' } }

      response '200', 'first password established' do
        let(:user) { passwordless_docs_user('auth_docs_add_password') }
        let(:add_password_token) do
          reauthentication_token_for(user: user, jwt: raw_jwt, purpose: 'add_password')
        end
        let(:payload) do
          {
            username: 'auth_docs_add_password', password: 'newpassword123',
            password_confirmation: 'newpassword123', reauthentication_token: add_password_token
          }
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['success'] }, code: { type: :string, enum: ['password_added'] }
        }
        run_test!
      end

      response '409', 'account already has a usable password' do
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['password_already_set'] }
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

      response '403', 'fresh add_password reauthentication required' do
        let(:user) { passwordless_docs_user('auth_docs_missing_grant') }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['reauthentication_required'] }
        }
        run_test!
      end

      response '422', 'password policy or username validation failed' do
        let(:user) { passwordless_docs_user('auth_docs_invalid_password') }
        let(:add_password_token) do
          reauthentication_token_for(user: user, jwt: raw_jwt, purpose: 'add_password')
        end
        let(:payload) do
          {
            username: user.username, password: 'short', password_confirmation: 'short',
            reauthentication_token: add_password_token
          }
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] },
          code: { type: :string, enum: %w[invalid_password username_unavailable] }
        }
        run_test!
      end
    end
  end

  path '/api/auth/recovery_codes' do
    post 'Rotate one-time account recovery codes' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Consumes a rotate_recovery_codes grant, invalidates the prior set atomically, and returns new raw codes once.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: ['reauthentication_token'], properties: {
          reauthentication_token: { type: :string }
        }
      }
      let(:payload) { { reauthentication_token: 'invalid' } }

      response '200', 'recovery codes rotated and returned once' do
        let(:rotation_token) do
          reauthentication_token_for(user: user, jwt: raw_jwt, purpose: 'rotate_recovery_codes')
        end
        let(:payload) { { reauthentication_token: rotation_token } }
        schema type: :object, required: %w[status code codes], properties: {
          status: { type: :string, enum: ['success'] },
          code: { type: :string, enum: ['recovery_codes_rotated'] },
          codes: { type: :array, items: { type: :string } }
        }
        run_test!
      end

      response '403', 'fresh reauthentication required' do
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['reauthentication_required'] }
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
    end
  end

  path '/api/auth/password_recovery' do
    post 'Request password or social-only account recovery' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      description 'Always returns the same accepted response. Password accounts receive Devise reset instructions; eligible social-only accounts receive a challenge that also requires a saved recovery code.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: ['email'], properties: { email: { type: :string, format: :email } }
      }
      let(:payload) { { email: 'unknown@example.com' } }

      response '202', 'request accepted without account enumeration' do
        schema type: :object, required: ['status'], properties: {
          status: { type: :string, enum: ['accepted'] }
        }
        run_test!
      end
    end

    put 'Complete password or social-only recovery' do
      tags 'Authentication'
      consumes 'application/json'
      produces 'application/json'
      description 'Password accounts use their Devise reset token. Social-only accounts require an encrypted email challenge, one unused recovery code, username confirmation, and a new password. Success does not issue a JWT.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: %w[recovery_token password password_confirmation], properties: {
          recovery_token: { type: :string }, recovery_code: { type: :string }, username: { type: :string },
          password: { type: :string, format: :password }, password_confirmation: { type: :string, format: :password }
        }
      }
      let(:payload) { { recovery_token: 'invalid', password: 'newpassword123', password_confirmation: 'newpassword123' } }

      response '200', 'password updated; explicit sign-in remains required' do
        let(:recovery_user) do
          User.create!(username: 'auth_docs_recovery', email: 'auth_docs_recovery@example.com', password: 'password123')
        end
        let(:payload) do
          {
            recovery_token: recovery_user.send_reset_password_instructions,
            password: 'newpassword123', password_confirmation: 'newpassword123'
          }
        end
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['success'] }, code: { type: :string, enum: ['password_updated'] }
        }
        run_test!
      end

      response '422', 'invalid or expired recovery proof' do
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['invalid_or_expired_recovery'] }
        }
        run_test!
      end

      response '429', 'recovery completion attempts rate limited' do
        before { allow_any_instance_of(Authentication::RateLimiter).to receive(:allowed?).and_return(false) }
        schema type: :object, required: %w[status code], properties: {
          status: { type: :string, enum: ['error'] }, code: { type: :string, enum: ['rate_limited'] }
        }
        run_test!
      end
    end
  end
end
