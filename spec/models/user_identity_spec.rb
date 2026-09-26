require 'rails_helper'

RSpec.describe UserIdentity, type: :model do
  def user(name)
    User.create!(username: name, email: "#{name}@example.com", password: 'password123')
  end

  it 'belongs to a user and cascades when the user is destroyed' do
    owner = user('identity_owner')
    identity = owner.user_identities.create!(provider: 'google', provider_uid: 'subject-1')

    expect(identity.user).to eq(owner)
    owner.destroy!
    expect(UserIdentity.exists?(identity.id)).to be(false)
  end

  it 'stores the provider UID as a binary key with both unique indexes' do
    expect(UserIdentity.columns_hash.fetch('provider_uid').type).to eq(:binary)
    unique_indexes = UserIdentity.connection.indexes(:user_identities).select(&:unique).map(&:columns)
    expect(unique_indexes).to include(['provider', 'provider_uid'], ['user_id', 'provider'])
  end

  it 'rejects a UID larger than the binary column can store' do
    identity = user('uid_limit').user_identities.build(provider: 'google', provider_uid: 'x' * 1025)
    expect(identity).not_to be_valid
    expect(identity.errors[:provider_uid]).to include('is too long')
  end

  it 'validates both identity uniqueness and one identity per provider per user' do
    owner = user('identity_one')
    other = user('identity_two')
    owner.user_identities.create!(provider: 'google', provider_uid: 'subject-1')

    expect(other.user_identities.build(provider: 'google', provider_uid: 'subject-1')).not_to be_valid
    expect(owner.user_identities.build(provider: 'google', provider_uid: 'subject-2')).not_to be_valid
  end

  it 'enforces provider and UID uniqueness in the database' do
    owner = user('db_one')
    other = user('db_two')
    owner.user_identities.create!(provider: 'google', provider_uid: 'subject-1')

    expect do
      UserIdentity.insert_all!([
        { user_id: other.id, provider: 'google', provider_uid: 'subject-1',
          created_at: Time.current, updated_at: Time.current }
      ])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'enforces user and provider uniqueness in the database' do
    owner = user('db_provider')
    owner.user_identities.create!(provider: 'google', provider_uid: 'subject-1')

    expect do
      UserIdentity.insert_all!([
        { user_id: owner.id, provider: 'google', provider_uid: 'subject-2',
          created_at: Time.current, updated_at: Time.current }
      ])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
