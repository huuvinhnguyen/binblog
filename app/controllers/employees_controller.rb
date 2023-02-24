class EmployeesController < ApplicationController
  before_action :set_employee, only: %i[ show edit update destroy ]

  # def export_xls
  # end

  # GET /employees or /employees.json
  def index
    @employees = Employee.all
  end

  # GET /employees/1 or /employees/1.json
  def show
  @attendance = Attendance.new
  end

  # GET /employees/new
  def new
    @employee = Employee.new
  end

  # GET /employees/1/edit
  def edit
  end

  # POST /employees or /employees.json
  def create
    @employee = Employee.new(employee_params)
    # byebug
    respond_to do |format|
      if @employee.save
        format.html { redirect_to employee_url(@employee), notice: "Employee was successfully created." }
        format.json { render :show, status: :created, location: @employee }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @employee.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /employees/1 or /employees/1.json
  def update
    respond_to do |format|
      if @employee.update(employee_params)
        format.html { redirect_to employee_url(@employee), notice: "Employee was successfully updated." }
        format.json { render :show, status: :ok, location: @employee }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @employee.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /employees/1 or /employees/1.json
  def destroy
    @employee.destroy

    respond_to do |format|
      format.html { redirect_to employees_url, notice: "Employee was successfully destroyed." }
      format.json { head :no_content }
    end
  end
  def destroy_attendance
    # byebug
    @employee = Employee.find(params[:employee_id])
    @attendance = @employee.attendances.find(params[:id])
    @attendance.destroy
    redirect_to request.referer, notice: 'Attendance was successfully deleted.'
  end
  
  def export_xls
    @employees = Employee.all

    # Tạo file excel từ danh sách employees
    p = Axlsx::Package.new
    wb = p.workbook
    wb.add_worksheet(name: "Employees") do |sheet|
      sheet.add_row ["Tên", "Email", "Điện thoại", "Lương / ngày"]
      @employees.each do |employee|
        sheet.add_row [employee.name, employee.email, employee.phone, employee.daily_salary]
      end
    end

    # Gửi file excel về cho người dùng
    send_data p.to_stream.read, filename: "nhan_cong.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end


  def generate_csv
    CSV.generate(headers: true) do |csv|
      csv << ["Name", "Email", "Phone", "Daily Salary"]
      @employees.each do |employee|
        csv << [employee.name, employee.email, employee.phone, employee.daily_salary]
      end
    end
  end



  private
    # Use callbacks to share common setup or constraints between actions.
    def set_employee
      @employee = Employee.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def employee_params
      params.require(:employee).permit(:name, :email, :phone, :daily_salary)
    end
end


