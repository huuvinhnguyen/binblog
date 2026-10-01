class ReauthenticationGrant < ActiveRecord::Base
  PURPOSES = %w[
    link_identity
    unlink_identity
    add_password
    rotate_recovery_codes
  ].freeze
  METHODS = %w[password google].freeze

  belongs_to :user

  validates :token_digest, :session_binding_digest, :expires_at, presence: true
  validates :token_digest, uniqueness: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :method, inclusion: { in: METHODS }
  validates :provider, format: { with: /\A[a-z][a-z0-9_]*\z/ }, allow_nil: true
  validate :provider_matches_method

  private

  def provider_matches_method
    if method == 'password' && provider.present?
      errors.add(:provider, 'must be blank for password reauthentication')
    elsif method != 'password' && provider != method
      errors.add(:provider, 'must match the provider method')
    end
  end
end
