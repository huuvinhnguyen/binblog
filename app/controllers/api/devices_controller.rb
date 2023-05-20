class Api::DevicesController < ApplicationController
    class Api::DevicesController < ApplicationController
        def create
          device = Device.new(device_params)
      
          if device.save
            render json: device, status: :created
          else
            render json: { errors: device.errors.full_messages }, status: :unprocessable_entity
          end
        end
      
        private
      
        def device_params
          params.require(:device).permit(:name, :serial_number, :status, :is_payment)
        end
      end
      
end
