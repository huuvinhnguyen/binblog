require 'rails_helper'

RSpec.describe 'Account authentication services' do
  def password_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: 'password123')
  end

  def social_user(name, disabled: false)
    user = User.build_for_verified_social_signup(username: name, email: "#{name}@example.com")
    user.save!
    user.user_identities.create!(
      provider: 'google', provider_uid: "#{name}-subject",
      disabled_at: disabled ? Time.current : nil
    )
    user
  end

  it 'identifies but never repairs a passwordless account with no enabled provider' do
    password_user('audit_password')
    social_user('audit_social')
    broken = social_user('audit_broken', disabled: true)

    audited = Authentication::AccountAudit.new.each_broken_account.to_a
    expect(audited).to contain_exactly(broken)
    expect(broken.reload.encrypted_password).to be_blank
    expect(broken.user_identities.first.disabled_at).to be_present
  end

  it 'enforces recovery-code format without storing raw codes' do
    expect(UserRecoveryCode.normalize('aaaa-bbbb-cccc-dddd-eeee-ffff-0000-1111'))
      .to eq('aaaabbbbccccddddeeeeffff00001111')
    expect(UserRecoveryCode.normalize('not-a-code')).to be_nil
  end

  it 'rate limits a repeated discriminator through the configured cache' do
    limiter = Authentication::RateLimiter.new(cache: ActiveSupport::Cache::MemoryStore.new)
    expect(limiter.allowed?(scope: 'test', discriminator: 'same', limit: 2, period: 1.minute)).to be(true)
    expect(limiter.allowed?(scope: 'test', discriminator: 'same', limit: 2, period: 1.minute)).to be(true)
    expect(limiter.allowed?(scope: 'test', discriminator: 'same', limit: 2, period: 1.minute)).to be(false)
    expect(limiter.allowed?(scope: 'test', discriminator: 'other', limit: 2, period: 1.minute)).to be(true)
  end

  it 'filters every new authentication secret parameter' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      'Authorization' => 'Bearer jwt',
      'password' => 'password',
      'password_confirmation' => 'password',
      'current_password' => 'password',
      'credential' => 'google-token',
      'reauthentication_token' => 'grant',
      'recovery_token' => 'challenge',
      'recovery_code' => 'code'
    )
    expect(filtered.values).to all(eq('[FILTERED]'))
  end
end
