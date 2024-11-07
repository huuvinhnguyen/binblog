module Api
  class Api::DevicesController < ApplicationController

    def receive_info
      # Lấy dữ liệu từ request
      device_id = params[:device_id]
      device_type = params[:device_type]
      switch_value = params[:switch_value]
      update_at = params[:update_at]
      reminders = params[:reminders] # Dữ liệu reminders là một array

      render json: { status: 'success', message: 'Device information received' }, status: :ok

    end

  rescue => e
    render json: { status: 'error', message: e.message }, status: :unprocessable_entity
  end

    private    
  end
end
