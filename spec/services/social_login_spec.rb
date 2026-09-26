require 'rails_helper'

RSpec.describe 'SocialLogin identity foundation' do
  def verified(uid, email = 'social@example.com', provider: 'google')
    SocialLogin::VerifiedIdentity.from_verified_claims(
      provider: provider, provider_uid: uid, verified_email: email
    )
  end

  def local_user(name, email = nil)
    User.create!(username: name, email: email || "#{name}@example.com", password: 'password123')
  end

  describe SocialLogin::VerifiedIdentity do
    it 'normalizes trusted claims and rejects empty keys' do
      identity = verified('Subject-1', ' SOCIAL@Example.com ', provider: ' Google ')
      expect([identity.provider, identity.provider_uid, identity.verified_email]).to eq(
        ['google', 'Subject-1', 'social@example.com']
      )
      expect { verified(' ') }.to raise_error(ArgumentError)
      expect { verified('x' * 1025) }.to raise_error(ArgumentError, 'Provider UID too long')
    end
  end

  describe SocialLogin::SignInResolver do
    it 'resolves an existing identity to its owner' do
      owner = local_user('existing')
      owner.user_identities.create!(provider: 'google', provider_uid: 'subject-1')
      outcome = described_class.new.call(verified_identity: verified('subject-1', 'other@example.com'))

      expect(outcome.status).to eq(:existing_identity)
      expect(outcome.user).to eq(owner)
    end

    it 'does not resolve a case-variant provider UID to the existing owner' do
      owner = local_user('case_owner')
      owner.user_identities.create!(provider: 'google', provider_uid: 'Subject-A')
      outcome = described_class.new.call(
        verified_identity: verified('subject-a', 'case_other@example.com')
      )

      expect(outcome.status).to eq(:created_account)
      expect(outcome.user).not_to eq(owner)
      expect(UserIdentity.where(provider: 'google').pluck(:provider_uid))
        .to contain_exactly('Subject-A', 'subject-a')
    end

    it 'creates a passwordless user and identity atomically with a username' do
      outcome = described_class.new.call(verified_identity: verified('new-subject'))

      expect(outcome.status).to eq(:created_account)
      expect(outcome.user.username).to match(/\Asocial_[0-9a-f]{20}\z/)
      expect(outcome.user.user_identities.pluck(:provider, :provider_uid)).to eq([['google', 'new-subject']])
      expect(outcome.user.usable_password_authentication?).to be(false)
      expect(outcome.user.valid_password?('password123')).to be(false)
    end

    it 'requires explicit linking for an existing email without an identity' do
      owner = local_user('local', 'social@example.com')
      outcome = described_class.new.call(verified_identity: verified('unknown'))

      expect(outcome.status).to eq(:link_required)
      expect(outcome.user).to be_nil
      expect(owner.user_identities.count).to eq(0)
    end

    it 'requires a verified usable email for signup' do
      expect(described_class.new.call(verified_identity: verified('no-email', nil)).status).to eq(:email_verification_required)
      expect(described_class.new.call(verified_identity: verified('bad-email', 'bad')).status).to eq(:email_verification_required)
    end

    it 'retries a username collision with a bounded generator' do
      local_user('social_collision')
      generator = ->(attempt) { attempt == 1 ? 'social_collision' : 'social_available' }
      outcome = described_class.new(username_generator: generator).call(verified_identity: verified('collision-subject'))

      expect(outcome.status).to eq(:created_account)
      expect(outcome.user.username).to eq('social_available')
    end

    it 'returns an explicit outcome after bounded username collisions' do
      local_user('social_collision')
      generator = ->(_attempt) { 'social_collision' }
      outcome = described_class.new(username_generator: generator).call(verified_identity: verified('collision-subject'))

      expect(outcome.status).to eq(:username_unavailable)
      expect(UserIdentity.exists?(provider_uid: 'collision-subject')).to be(false)
    end

    it 'rolls back user creation if identity creation fails' do
      allow_any_instance_of(UserIdentity).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(UserIdentity.new)
      )

      expect do
        expect { described_class.new.call(verified_identity: verified('failed-subject')) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end.not_to change(User, :count)
    end
  end

  describe SocialLogin::LinkIdentity do
    it 'links an unused identity to the authenticated principal' do
      principal = local_user('principal')
      outcome = described_class.new.call(user: principal, verified_identity: verified('new-link'))

      expect(outcome.status).to eq(:linked)
      expect(outcome.user).to eq(principal)
      expect(principal.user_identities.find_by!(provider: 'google').provider_uid).to eq('new-link')
    end

    it 'is idempotent when the principal already owns the identity' do
      principal = local_user('principal')
      principal.user_identities.create!(provider: 'google', provider_uid: 'owned')
      outcome = described_class.new.call(user: principal, verified_identity: verified('owned'))

      expect(outcome.status).to eq(:already_linked)
      expect(outcome.user).to eq(principal)
      expect(principal.user_identities.count).to eq(1)
    end

    it 'rejects another owner without disclosing or transferring that owner' do
      principal = local_user('principal')
      other = local_user('other')
      identity = other.user_identities.create!(provider: 'google', provider_uid: 'owned')
      outcome = described_class.new.call(user: principal, verified_identity: verified('owned'))

      expect(outcome.status).to eq(:identity_conflict)
      expect(outcome.user).to eq(principal)
      expect(identity.reload.user).to eq(other)
      expect(principal.user_identities.count).to eq(0)
    end

    it 'rejects a different identity for the same provider' do
      principal = local_user('principal')
      principal.user_identities.create!(provider: 'google', provider_uid: 'first')
      outcome = described_class.new.call(user: principal, verified_identity: verified('second'))

      expect(outcome.status).to eq(:provider_already_linked)
      expect(outcome.user).to eq(principal)
    end
  end

  describe SocialLogin::UnlinkIdentity do
    it 'removes an identity when local password auth remains usable' do
      principal = local_user('principal')
      principal.user_identities.create!(provider: 'google', provider_uid: 'subject')
      outcome = described_class.new.call(user: principal, provider: 'google')

      expect(outcome.status).to eq(:unlinked)
      expect(principal.user_identities.count).to eq(0)
    end

    it 'cannot remove the final authentication method' do
      principal = SocialLogin::SignInResolver.new.call(verified_identity: verified('subject')).user
      outcome = described_class.new.call(user: principal, provider: 'google')

      expect(outcome.status).to eq(:last_authentication_method)
      expect(principal.user_identities.count).to eq(1)
    end

    it 'can remove one identity while another identity remains' do
      principal = SocialLogin::SignInResolver.new.call(verified_identity: verified('subject')).user
      principal.user_identities.create!(provider: 'alternate', provider_uid: 'alternate-subject')
      outcome = described_class.new.call(user: principal, provider: 'google')

      expect(outcome.status).to eq(:unlinked)
      expect(principal.user_identities.pluck(:provider)).to eq(['alternate'])
    end

    it 'blocks unlink for a legacy user with a hash but no usable username' do
      principal = local_user('legacy_user')
      principal.user_identities.create!(provider: 'google', provider_uid: 'legacy-subject')
      principal.update_column(:username, nil)

      expect(principal.usable_password_authentication?).to be(false)
      outcome = described_class.new.call(user: principal, provider: 'google')
      expect(outcome.status).to eq(:last_authentication_method)
      expect(principal.user_identities.count).to eq(1)

      principal.update_column(:username, '   ')
      expect(principal.usable_password_authentication?).to be(false)
      expect(described_class.new.call(user: principal, provider: 'google').status)
        .to eq(:last_authentication_method)
    end

    it 'does not treat malformed password hashes as usable local authentication' do
      principal = SocialLogin::SignInResolver.new.call(verified_identity: verified('subject')).user
      principal.update_column(:encrypted_password, 'broken-hash')
      outcome = described_class.new.call(user: principal, provider: 'google')

      expect(outcome.status).to eq(:last_authentication_method)
      expect(principal.user_identities.count).to eq(1)
    end
  end

  it 'preserves existing username and password login' do
    principal = local_user('password_user')
    expect(principal.valid_password?('password123')).to be(true)
    expect(principal.valid_password?('incorrect')).to be(false)
    expect(principal.usable_password_authentication?).to be(true)
  end
end
