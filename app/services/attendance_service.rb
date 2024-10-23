class AttendanceService
  def initialize(device_finger_id)
    @device_finger_id = device_finger_id
  end

  def handle_attendance(employee_id)
    today = Date.current
    last_attendance = Attendance.where(employee_id: employee_id, date: today).order(created_at: :desc).first

    if last_attendance.nil? || (last_attendance.end_time.present? && Time.current - last_attendance.end_time > 2.minutes)
      checkin(employee_id)
      { status: :checkin, message: "Checkin" }
    elsif last_attendance.end_time.present?
      checkout(last_attendance)
      { status: :checkout, message: "Checkout 1" }
    else
      checkin_time = last_attendance.start_time
      time_since_checkin = Time.current - checkin_time

      if time_since_checkin >= 2.minutes
        checkout(last_attendance)
        { status: :checkout, message: "Checkout 2" }
      else
        wait_time = (2.minutes - time_since_checkin).round
        { status: :checkin, message: "You already checked in. Please wait #{wait_time} seconds before checkout." }
      end
    end
  end

  def checkin(employee_id)
    today = Date.current
    attendance = Attendance.create!(employee_id: employee_id, date: today, start_time: Time.current)
    attendance
  end

  def checkout(attendance)
    attendance.update!(end_time: Time.current)
  end

  def find_employee
    finger = Finger.find_by(device_finger_id: @device_finger_id)
    finger&.employee
  end
end
