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

  def destroy
    redirect_to request.referer, notice: 'Attendance was successfully deleted.'
  end

  def checkin
    AttendanceService.new.checkin(@employee)
    render json: { message: "Check-in successful for #{@employee.name}" }, status: :ok
  end

  private

  def attendance_params
    params.require(:attendance).permit(:date, :weight, :status, :project_id)
  end

  def find_employee
    @employee = Employee.find_by(device_finger_id: params[:device_finger_id])
    render json: { error: "Employee not found" }, status: :not_found unless @employee
  end
end

