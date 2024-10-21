class FingersController < ApplicationController
    before_action :set_employee
    before_action :set_finger, only: [:show, :destroy]
  
    # GET /employees/:employee_id/fingers
    def index
        @device = User.find(1).devices.first
        @fingers = @employee.fingers
    end
  
    # GET /employees/:employee_id/fingers/:id
    def show
    end
  
    # GET /employees/:employee_id/fingers/new
    def new
      @finger = @employee.fingers.new
    end
  
    # POST /employees/:employee_id/fingers
    def create
      @finger = @employee.fingers.new(finger_params)
  
      if @finger.save
        redirect_to employee_finger_path(@employee, @finger), notice: 'Finger was successfully added.'
      else
        render :new
      end
    end
  
    # DELETE /employees/:employee_id/fingers/:id
    def destroy
      @finger.destroy
      redirect_to employee_fingers_path(@employee), notice: 'Finger was successfully deleted.'
    end
  
    private
  
      # Set employee
      def set_employee
        @employee = Employee.find(params[:employee_id])
      end
  
      # Set finger
      def set_finger
        @finger = @employee.fingers.find(params[:id])
      end
  
      # Strong params for finger
      def finger_params
        params.require(:finger).permit(:finger_id, :device_finger_id, :fingerprint_template)
      end
end
  
