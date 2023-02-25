class Attendance < ActiveRecord::Base

  belongs_to :employee
  enum status: { present: 0, absent: 1, late: 2 }, _prefix: true
  after_initialize :set_default_status

  private

  def set_default_status
    self.status ||= :present
  end
end
