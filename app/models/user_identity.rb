class UserIdentity < ActiveRecord::Base
  MAX_PROVIDER_UID_BYTES = 1024

  belongs_to :user

  validates :provider, presence: true, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :provider_uid, presence: true
  validate :provider_uid_fits_binary_column
  validates :provider_uid, uniqueness: { scope: :provider }
  validates :provider, uniqueness: { scope: :user_id }
  private

  def provider_uid_fits_binary_column
    return if provider_uid.nil? || provider_uid.bytesize <= MAX_PROVIDER_UID_BYTES

    errors.add(:provider_uid, 'is too long')
  end
end
