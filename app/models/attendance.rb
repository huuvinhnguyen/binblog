class Attendance < ActiveRecord::Base

  belongs_to :employee
  # belongs_to :project
  enum status: { present: 0, absent: 1, late: 2 }, _prefix: true
  after_initialize :set_default_status
  validate :end_time_after_start_time


  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    if end_time <= start_time
      errors.add(:end_time, 'must be greater than start time')
    end
  end

  def set_default_status
    self.status ||= :present
  end
end
