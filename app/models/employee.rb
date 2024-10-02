class Employee < ActiveRecord::Base
  has_many :attendances, dependent: :destroy
  has_many :fingers, dependent: :destroy
  has_and_belongs_to_many :users
  # has_many :projects, through: :attendances 
  
  def attendances
    Attendance.where(employee_id: id)
  end

  def fingers
    Finger.where(employee_id: id)
  end
end
