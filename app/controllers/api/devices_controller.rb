module Api
  class Api::DevicesController < ApplicationController

    def receive_info
      # Nhận và xử lý dữ liệu từ ESP8266
    message = params.permit(:device_type, :topic_type, :device_id, :switch_value, :update_at, :longlast, :timetrigger, reminder: {}, reminders: [])
    puts "message receive: #{message}"
    ActionCable.server.broadcast('mqtt_channel', message)

    render json: { status: 'success', message: 'Device information received' }, status: :ok

    end

  rescue => e
    render json: { status: 'error', message: e.message }, status: :unprocessable_entity
  end

end
