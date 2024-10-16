class CheckinsController < ApplicationController
    def create
      device_finger_id = params[:device_finger_id]
  
      employee = EmployeeFingerprintService.new(device_finger_id).find_employee
  
      if employee
        # Perform the check-in logic, such as recording the time
        render json: { message: "Check-in successful for #{employee.name}" }, status: :ok
      else
        render json: { error: "Employee not found" }, status: :not_found
      end
    end
end
  