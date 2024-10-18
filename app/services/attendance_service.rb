class AttendanceService

  def initialize(device_finger_id)
    @device_finger_id = device_finger_id
  end
  def checkin(employee_id)
    
    today = Date.current
    # Check if there's already an attendance record for today
    attendance = Attendance.find_or_initialize_by(employee_id: employee_id, date: today)

    if attendance.new_record?
      attendance.start_time = Time.current
      attendance.save!
    else
      # If the employee is already checked in, update other details if needed
      puts "Already checked in for today"
      checkout(employee_id)
    end
  end

  def find_employee
    finger = Finger.find_by(device_finger_id: @device_finger_id)
    return nil unless finger

    employee = finger.employee
    employee
  end

  private
  
  def checkout(employee_id)
    today = Date.current
    attendance = Attendance.find_by(employee_id: employee_id, date: today)

    if attendance
      attendance.end_time = Time.current
      attendance.save!
    else
      puts "No check-in found for today."
    end
  end

end