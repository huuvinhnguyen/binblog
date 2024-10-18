class AttendanceService
    def checkin(employee)
      today = Date.current
      # Check if there's already an attendance record for today
      attendance = Attendance.find_or_initialize_by(employee_id: employee.id, date: today)
  
      if attendance.new_record?
        attendance.start_time = Time.current
        attendance.save!
      else
        # If the employee is already checked in, update other details if needed
        puts "Already checked in for today"
      end
    end
  
    private
    
    def checkout(employee)
      today = Date.current
      attendance = Attendance.find_by(employee_id: employee.id, date: today)
  
      if attendance
        attendance.end_time = Time.current
        attendance.save!
      else
        puts "No check-in found for today."
      end
    end
end