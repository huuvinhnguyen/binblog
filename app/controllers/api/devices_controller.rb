module Api
  class Api::DevicesController < ApplicationController

    def receive_info
      # Receive and process data from ESP8266
      message = params.permit(
        :device_type,
        :topic_type,
        :device_id,
        :switch_value,
        :update_at,
        :longlast,
        :timetrigger,
        reminder: [
          :start_time,
          :duration,
          :repeat_type
        ],
       
        relays: [
          :switch_value,
          :longlast,
          :is_reminders_active,
        ]
      )

      puts "message received: #{message}"

      # Find the device by device_id, or create a new one if it doesn't exist
      device = Device.find_or_initialize_by(chip_id: message[:device_id])

      # Update the device_info column with the received message
      device.device_info = message.to_json

      # Save the device record
      if device.save
        # Broadcast the message to the MQTT channel
        ActionCable.server.broadcast('mqtt_channel', message)

        # Send a success response
        render json: { status: 'success', message: 'Device information received and saved' }, status: :ok
      else
        # Send an error response if saving fails
        render json: { status: 'error', message: device.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def add_reminder
      # Receive and process data from ESP8266
      message = params.permit(
        :device_type,
        :topic_type,
        :device_id,
        :switch_value,
        :update_at,
        :longlast,
        :timetrigger,
        reminder: [
          :start_time,
          :duration,
          :repeat_type
        ],
       
        relays: [
          :switch_value,
          :longlast,
          :is_reminders_active,
          reminders: [
            :start_time,
            :duration,
            :repeat_type
          ]
        ]
      )

      puts "message received: #{message}"

      # Find the device by device_id, or create a new one if it doesn't exist
      device = Device.find_or_initialize_by(chip_id: message[:device_id])

      # Update the device_info column with the received message
      device.device_info = message.to_json

      # Save the device record
      if device.save
        # Broadcast the message to the MQTT channel
        ActionCable.server.broadcast('mqtt_channel', message)

        # Send a success response
        render json: { status: 'success', message: 'Device information received and saved' }, status: :ok
      else
        # Send an error response if saving fails
        render json: { status: 'error', message: device.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def device_info
      # Find the device by device_id parameter
      device_id = params[:device_id]
      device = Device.find_by(chip_id: device_id.to_s)

      # Check if the device exists
      if device
        # Return the device_info
        device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
        render json: { status: 'success', device_info: device_info }, status: :ok
      else
        # Return an error if device is not found
        render json: { status: 'error', message: 'Device not found' }, status: :not_found
      end
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

  end
end
