class Employee < ActiveRecord::Base
  has_many :attendances
  def attendances
    Attendance.where(employee_id: id)
  end
end
