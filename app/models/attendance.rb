class Attendance < ActiveRecord::Base

  belongs_to :employee
  enum status: { present: 0, absent: 1, late: 2 }
end
