class EmployeesController < ApplicationController
  # before_action :authenticate_user!, except: [:enroll_fingerprint, :delete_fingerprint]
  before_action :initialize_mqtt_client
  before_action :set_employee, only: %i[ show edit update destroy ]

  # GET /employees or /employees.json
  def index
    # @employees = current_user.employees

    @employees = Employee.all
    @attendances = Attendance.all

    if params[:daterange].present?
      start_date, end_date = params[:daterange].split(' - ').map{ |date| Date.parse(date) }
      @employees = @employees.joins(:attendances).where(attendances: { date: start_date..end_date }).distinct
      @attendances = @attendances.where(["start_time BETWEEN ? AND ?", start_date, end_date])
    end
    if params[:project_id].present?
      @employees = @employees.joins(:attendances).where(attendances: { project_id:  params[:project_id]}).distinct
      @attendances = @attendances.where({project_id: params[:project_id]}).distinct
    end

  end

  def initialize_mqtt_client  
    @client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
    )

  end

  # GET /employees/1 or /employees/1.json
  def show
    @device = User.find(1).devices.first
    session[:employee_id] = @employee.id # lưu trữ thông tin employee vào session

    @attendances = @employee.attendances
    @rewards_penalties = @employee.rewards_penalties

    if params[:daterange].present? 
      start_date, end_date = params[:daterange].split(' - ').map{ |date| Date.parse(date) }
      @attendances = @employee.attendances.where("start_time BETWEEN ? AND ?", start_date, end_date)
      @rewards_penalties = @employee.rewards_penalties.where(["date BETWEEN ? AND ?", start_date, end_date])
    end

     if params[:project_id].present?
      @attendances = @attendances.where({project_id: params[:project_id]}).distinct
    end
  
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
    # @employee = current_user.employees.build(employee_params)
    # byebug
    respond_to do |format|
      if @employee.save
        current_user.employees << @employee
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
  
    # Create Excel file from employee data
    p = Axlsx::Package.new
    wb = p.workbook
    wb.add_worksheet(name: "Employees") do |sheet|
      sheet.add_row ["Tên", "Email", "Điện thoại", "Lương / Giờ", "Tổng giờ", "Thưởng", "Phạt", "Tổng lương"]
  
      @employees.each do |employee|
        total_hours = 0.0
        total_salary = 0.0
  
        employee.attendances.each do |attendance|
          if attendance.start_time.present? && attendance.end_time.present?
            hours_worked = ((attendance.end_time - attendance.start_time) / 1.hour).round(2)
            total_hours += hours_worked
  
            salary = if attendance.hourly_wage.present? && attendance.hourly_wage > 0
                       attendance.hourly_wage
                     else
                       employee.daily_salary || 0.0
                     end
  
            total_salary += salary.to_f * hours_worked
          end
        end
  
        total_rewards = employee.rewards_penalties.where(penalty: false).sum(:amount).round(0)
        total_penalties = employee.rewards_penalties.where(penalty: true).sum(:amount).round(0)
        total_salary = total_salary + total_rewards - total_penalties
  
        sheet.add_row [employee.name, employee.email, employee.phone, employee.daily_salary, total_hours, total_rewards, total_penalties, total_salary]
      end
    end
  
    send_data p.to_stream.read, filename: "nhan_cong.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end
  

  def export_csv
    @employees = Employee.all
  
    csv_data = CSV.generate(headers: true) do |csv|
      # Thêm tiêu đề
      csv << ["Tên", "Email", "Điện thoại", "Lương / Giờ", "Tổng giờ", "Thưởng", "Phạt", "Tổng lương"]
  
      # Duyệt qua từng employee và tính toán các thông số
      @employees.each do |employee|
        total_hours = employee.attendances.sum do |attendance|
          if attendance.start_time.present? && attendance.end_time.present?
            ((attendance.end_time - attendance.start_time) / 1.hour).round(2)
          else
            0
          end
        end
  
        total_rewards = employee.rewards_penalties.where(penalty: false).sum(:amount).round(0)
        total_penalties = employee.rewards_penalties.where(penalty: true).sum(:amount).round(0)
        total_salary = (employee.daily_salary.to_f * total_hours) + total_rewards - total_penalties
  
        # Thêm dòng dữ liệu cho employee vào CSV
        csv << [employee.name, employee.email, employee.phone, employee.daily_salary, total_hours, total_rewards, total_penalties, total_salary]
      end
    end
  
    # Gửi file CSV về cho người dùng
    send_data csv_data, filename: "nhan_cong.csv", type: "text/csv"
  end
  
  
  def export_attendance_xls
    employee = Employee.find(params[:employee_id])
  
    attendances = employee.attendances
    rewards_penalties = employee.rewards_penalties
  
    if params[:daterange].present? 
      start_date, end_date = params[:daterange].split(' - ').map{ |date| Date.parse(date) }
      attendances = employee.attendances.where("start_time BETWEEN ? AND ?", start_date, end_date)
      rewards_penalties = employee.rewards_penalties.where(["date BETWEEN ? AND ?", start_date, end_date])
    end
  
    total_attendance_amount = 0
    total_rewards = 0
    total_penalties = 0
  
    # Tạo file excel từ danh sách employees
    p = Axlsx::Package.new
    wb = p.workbook
    wb.add_worksheet(name: "Bảng lương nhân viên") do |sheet|
      sheet.add_row ["Tên:", employee.name ]
      sheet.add_row ["Email", employee.email]
      sheet.add_row ["Điện thoại", employee.phone]
      sheet.add_row ["Lương / Giờ", employee.daily_salary]
      sheet.add_row []
      sheet.add_row [params[:daterange]]
      sheet.add_row []

      # Thêm danh sách thưởng/phạt
      sheet.add_row ["Danh sách Thưởng/Phạt"]
      sheet.add_row ["Thời gian", "Mô tả", "Thưởng/Phạt", "Số tiền"]
      rewards_penalties.order(date: :desc).each do |rewards_penalty|
        start_date = I18n.l(rewards_penalty.date.in_time_zone('Asia/Ho_Chi_Minh'), format: :short)
        sheet.add_row [start_date, rewards_penalty.description, rewards_penalty.penalty ? "Phạt" : "Thưởng", rewards_penalty.amount]
        total_rewards += rewards_penalty.amount unless rewards_penalty.penalty
        total_penalties += rewards_penalty.amount if rewards_penalty.penalty
      end
  
      sheet.add_row []
  
      # Thêm danh sách chấm công
      sheet.add_row ["Danh sách chấm công"]
      sheet.add_row ["Bắt đầu", "Kết thúc", "Số giờ", "Lương/giờ", "Thành tiền"]
      attendances.order(date: :desc).each do |attendance|
        if attendance.start_time.present? && attendance.end_time.present?
          working_hours = ((attendance.end_time - attendance.start_time) / 1.hour).round(2)
        else
          working_hours = 0.0
        end
  
        salary = 0.0
        if attendance.hourly_wage.present? && attendance.hourly_wage > 0 
          salary = attendance.hourly_wage ? attendance.hourly_wage : 0.0
        else 
          salary = employee.daily_salary ? employee.daily_salary : 0.0
        end
      
        amount = salary.to_f * working_hours.to_f
        total_attendance_amount += amount
        start_time = I18n.l(attendance.start_time.in_time_zone('Asia/Ho_Chi_Minh'), format: :short)
        end_time = I18n.l(attendance.end_time.in_time_zone('Asia/Ho_Chi_Minh'), format: :short)
        sheet.add_row [start_time, end_time, working_hours, salary.to_f, amount]
      end
  
      # Tính tổng lương
      total_salary = total_attendance_amount + total_rewards - total_penalties
  
      sheet.add_row []
      sheet.add_row ["Tổng lương:", "", "", "", total_salary]
    end
  
    # Gửi file excel về cho người dùng
    send_data p.to_stream.read, filename: "bang_luong_nhan_vien.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end
  

  def activate_adding_finger
    chip_id = params[:chip_id]
    topic = chip_id + "/fingerprint"
    message = {
      "action": "enroll",
      "active": true,
      "enrollment_mode": true,
      "device_id": chip_id.to_s,
      "employee_id": params[:employee_id]
    }.to_json

    client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
    )

    # message = { action: "enroll", enrollment_mode: true }

    # ActionCable.server.broadcast('fingerprints_channel', message)

    client.publish(topic, message) if topic.present?
    
    client.disconnect()

    subscribe_topic topic

  end

  #POST 
  def enroll_fingerprint

    employee = Employee.find(params[:employee_id])
    service = AddFingerService.new(
      employee: employee,
      finger_id: params[:finger_id],
      fingerprint_template: params[:fingerprint_template],
      device_finger_id: params[:device_finger_id]
    )

    if service.call
      render json: { message: 'Finger added successfully' }, status: :created
      # message = { action: "enroll", enrollment_mode: false }
      # ActionCable.server.broadcast('fingerprints_channel', message)


    else
      render json: { error: 'Failed to add finger' }, status: :unprocessable_entity
    end

  end

  #MQTT
  def cancel_enrollment
    
    topic = "12394568" + "/fingerprint"
    message = {
      "action": "enroll",
      "enrollment_mode": false,
      "device_id": 12394568,
      "employee_id": 1
    }.to_json

    client = MQTT::Client.connect(
      host: '103.9.77.155',
      port: 1883,
    )

    client.publish(topic, message) if topic.present?
    client.disconnect()

  end


  #DELETE
  def delete_fingerprint

    service = DeleteFingerService.new(device_finger_id: params[:device_finger_id])

    if service.call
      render json: { message: 'Finger deleted successfully' }, status: :ok
    else
      render json: { error: 'Failed to delete finger' }, status: :unprocessable_entity
    end

  end

  def subscribe_topic topic

    json_message = nil

    Thread.new do
      @client.subscribe(topic)
      @client.get(topic, timeout: 2) do |rs_topic, message|
        current_message = JSON.generate(message)

        if json_message.to_s != current_message.to_s
          ActionCable.server.broadcast('fingerprints_channel', current_message)

        end
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


