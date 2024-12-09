class User < ActiveRecord::Base
  rolify
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         authentication_keys: [:username]

  validates :email, presence: false, allow_blank: true
  validates :username, presence: true, uniqueness: true

  has_and_belongs_to_many :devices
  has_and_belongs_to_many :employees
  
end
