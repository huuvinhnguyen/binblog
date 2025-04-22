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
        relays: [
          :switch_value,
          :longlast,
          :is_reminders_active,
          reminders: [
            :start_time,
            :duration,
            :repeat_type
          ]
        ],
        device: [
          :device_type
        ]

      )
    
      puts "message received: #{message}"
    
      # Find the device by device_id, or create a new one if it doesn't exist
      device = Device.find_or_initialize_by(chip_id: message[:device_id])
    
      # Parse current device_info to retain existing reminders
      current_device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      current_relays = current_device_info["relays"] || []
    
      # Merge new relays while keeping old reminders
      updated_relays = message[:relays].map.with_index do |relay, index|
        old_relay = current_relays[index] || {}
        {
          switch_value: relay[:switch_value] || old_relay["switch_value"],
          longlast: relay[:longlast] || old_relay["longlast"],
          is_reminders_active: relay[:is_reminders_active] || old_relay["is_reminders_active"],
          reminders: old_relay["reminders"] || [] # Keep old reminders if no new reminders provided
        }
      end
    
      # Update device_info with merged data
      device.device_info = {
        device_type: message[:device_type],
        topic_type: message[:topic_type],
        device_id: message[:device_id],
        switch_value: message[:switch_value],
        update_at: message[:update_at],
        longlast: message[:longlast],
        timetrigger: message[:timetrigger],
        relays: updated_relays
      }.to_json
    
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
      # Cho phép các params cần thiết
      message = params.permit(
        :device_id,
        :relay_index,
        reminder: [
          :start_time,
          :duration,
          :repeat_type
        ]
      )
    
      puts "message received: #{message}"
    
      # Tìm thiết bị theo chip_id
      device = Device.find_by(chip_id: message[:device_id])
    
      unless device
        return render json: { status: 'error', message: 'Device not found' }, status: :not_found
      end
    
      # Parse device_info JSON hiện tại
      device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      relays = device_info["relays"] || []
    
      # Xác định chỉ số relay cần cập nhật
      relay_index = message[:relay_index].to_i
      reminder_data = message[:reminder].to_h
    
      # Kiểm tra index tồn tại
      if relay_index >= relays.length
        return render json: { status: 'error', message: "Invalid relay index: #{relay_index}" }, status: :bad_request
      end
    
      # Thêm reminder mới vào relay tương ứng
      relays[relay_index]["reminders"] ||= []
      relays[relay_index]["reminders"] << reminder_data
    
      # Gán lại relays vào device_info và cập nhật lại
      device_info["relays"] = relays
      device.device_info = device_info.to_json
    
      if device.save
        # ActionCable.server.broadcast('mqtt_channel', device_info)
        refresh message[:device_id]
        redirect_to device_path(device), notice: "Updated successfully."

        # render json: { status: 'success', message: 'Reminder added successfully' }, status: :ok
      else
        render json: { status: 'error', message: device.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def remove_reminder
      message = params.permit(:device_id, :relay_index, :reminder_index)
    
      device = Device.find_by(chip_id: message[:device_id])
      unless device
        return render json: { status: 'error', message: 'Device not found' }, status: :not_found
      end
    
      device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      relays = device_info["relays"] || []
    
      relay_index = message[:relay_index].to_i
      reminder_index = message[:reminder_index].to_i
    
      if relay_index >= relays.length
        return render json: { status: 'error', message: "Invalid relay index: #{relay_index}" }, status: :bad_request
      end
    
      reminders = relays[relay_index]["reminders"] || []
    
      if reminder_index >= reminders.length
        return render json: { status: 'error', message: "Invalid reminder index: #{reminder_index}" }, status: :bad_request
      end
    
      # Xóa reminder
      reminders.delete_at(reminder_index)
      relays[relay_index]["reminders"] = reminders
      device_info["relays"] = relays
      device.device_info = device_info.to_json
    
      if device.save
        refresh message[:device_id]
        redirect_to device_path(device), notice: "Reminder removed successfully."
        # render json: { status: 'success', message: 'Reminder removed successfully' }, status: :ok
      else
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

    def trigger
      # Lấy JSON từ body của request
      # raw_body = request.body.read
    
      begin

        device = Device.find_by(chip_id: params[:chip_id])
        trigger_device device
        
        render json: { status: 'success', message: 'Message sent successfully' }, status: :ok
      rescue JSON::ParserError
        render json: { status: 'error', message: 'Invalid JSON format' }, status: :unprocessable_entity
      rescue StandardError => e
        render json: { status: 'error', message: e.message }, status: :internal_server_error
      end
    end

    def switchon
      message = params.permit(:device_id, :switch_value, :relay_index)
    
      success = SwitchOnService.new(
        message[:device_id],
        switch_value: message[:switch_value].to_i,
        relay_index: message[:relay_index].present? ? message[:relay_index].to_i : nil
      ).call
    
      if success
        refresh message[:device_id]
        render json: { status: 'success', message: 'Switched successfully' }, status: :ok
      else
        render json: { status: 'error', message: 'Failed to switch' }, status: :unprocessable_entity
      end
    end    

    private
    def trigger_device device
      raw_message_trigger = device.trigger
      json_params = JSON.parse(raw_message_trigger)
  
      # Tạo topic từ chip_id
      topic = "#{json_params['chip_id']}/switchon"
      raise "chip_id is missing" unless json_params['chip_id'].present?
  
      # Gửi raw JSON (message) qua MQTT
      client = MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
      
      client.publish(topic, raw_message_trigger, retain: false) if topic.present?
      client.disconnect

    end

    def refresh chip_id
      topic = "#{chip_id}/refresh"
  
      client = MQTT::Client.connect(
          host: '103.9.77.155',
          port: 1883,
      )

      message = {
          "action": "ping",
          "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
       }.to_json
  
      client.publish(topic, message) if topic.present?
      client.disconnect()
  
    end
  end
end
