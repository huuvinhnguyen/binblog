class User < ActiveRecord::Base
  rolify

  def devices_for_current_user
    has_role?(:admin) ? Device.all : devices
  end
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         authentication_keys: [:username]

  validates :email, presence: false, allow_blank: true
  validates :username, presence: true, uniqueness: true

  has_many :user_identities, dependent: :destroy

  # The caller must have a VerifiedIdentity before using this builder.
  # A blank encrypted_password means no usable local password login.
  def self.build_for_verified_social_signup(username:, email:)
    new(username: username, email: email).tap do |user|
      user.instance_variable_set(:@allow_passwordless_social_creation, true)
    end
  end

  def usable_password_authentication?
    return false unless persisted? && username.present? && encrypted_password.present?

    BCrypt::Password.new(encrypted_password)
    true
  rescue BCrypt::Errors::InvalidHash
    false
  end

  has_and_belongs_to_many :devices
  has_and_belongs_to_many :employees
  
  def admin?
    has_role?(:admin)
  end

  protected

  def password_required?
    return false if new_record? && @allow_passwordless_social_creation &&
                    encrypted_password.blank? && password.nil? && password_confirmation.nil?

    super
  end
  
end
