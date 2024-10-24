class AttendancesController < ApplicationController
  def create
    @employee = Employee.find(params[:employee_id])
    @attendance = @employee.attendances.build(attendance_params)

    if @attendance.save
      redirect_to employee_path(@employee), notice: 'Đã thêm attendance thành công'
    else
      render :new
    end
  end

  def edit
    # Hiển thị form chỉnh sửa attendance
    @employee = Employee.find(params[:employee_id])
    @attendance = @employee.attendances.find(params[:id])
  end

  def update
    @employee = Employee.find(params[:employee_id])
    @attendance = @employee.attendances.find(params[:id])

    if @attendance.update(attendance_params)
      redirect_to employee_path(@employee), notice: 'Cập nhật thành công.'
    else
      render :edit
    end
  end

  def destroy
    redirect_to request.referer, notice: 'Attendance was successfully deleted.'
  end

  def checkin
    device_finger_id = params[:device_finger_id]
  
    attendance_service = AttendanceService.new(device_finger_id)
    employee = attendance_service.find_employee
  
    if employee
      result = attendance_service.handle_attendance(employee.id)
      message = result[:message] || ""
      case result[:status]
      when :checkin
        notify(employee, message)
        render json: { message: "Check-in successful for #{employee.name}" }, status: :ok
      when :checkout
        notify(employee, message)
        render json: { message: "Checkout successful for #{employee.name}" }, status: :ok
      when :wait
        notify(employee, message)
        render json: { message: result[:message] }, status: :forbidden
      end
    else
      render json: { error: "Employee not found" }, status: :not_found
    end
  end
  
  

  private

  def attendance_params
    params.require(:attendance).permit(:date, :weight, :start_time, :end_time, :project_id, :hourly_wage)
  end

  def notify(employee, message)
    managers = employee.users # Assuming `employee.users` returns all managers for the employee
  
    if managers.any?
      managers.each do |manager|
        webhook_url = manager.webhook_url # Assuming each manager has a webhook_url field
  
        if webhook_url.present?
          notifier = Slack::Notifier.new webhook_url do
            defaults channel: "farming#",
                     username: "khuonvien"
          end
          
          slack_message = "Xin chào bạn #{employee.name}\n" + message
          notifier.ping slack_message
        else
          Rails.logger.error "Slack Webhook URL is missing for manager #{manager.email}"
        end
      end
    else
      Rails.logger.error "No managers found for employee #{employee.name}"
    end
  end
  
end

