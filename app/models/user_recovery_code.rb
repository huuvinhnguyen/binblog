class UserRecoveryCode < ActiveRecord::Base
  RAW_HEX_LENGTH = 32

  belongs_to :user

  scope :unused, -> { where(used_at: nil) }

  validates :code_digest, presence: true, uniqueness: true

  def self.normalize(raw_code)
    compact = raw_code.to_s.strip.downcase.delete('-')
    return unless compact.match?(/\A[0-9a-f]{#{RAW_HEX_LENGTH}}\z/)

    compact
  end
end
