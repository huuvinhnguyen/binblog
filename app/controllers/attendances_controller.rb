class AttendancesController < ApplicationController
  def create
    # byebug
    @employee = Employee.find(params[:employee_id])
    @attendance = @employee.attendances.build(attendance_params)
    @attendance.status = :present

    if @attendance.save
      redirect_to employee_path(@employee), notice: 'Đã thêm attendance thành công'
    else
      render :new
    end
  end
  def destroy
    redirect_to request.referer, notice: 'Attendance was successfully deleted.'

  end
 

  private

  def attendance_params
    params.require(:attendance).permit(:date, :weight, :status)
  end
end

