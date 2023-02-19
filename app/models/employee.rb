class Employee < ActiveRecord::Base
  has_many :attendances, dependent: :destroy
  def attendances
    Attendance.where(employee_id: id)
  end
end
