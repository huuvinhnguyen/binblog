module Api
  class Api::DevicesController < ApplicationController
    
    def set_reminders_active
      message = params.permit(:device_id, :relay_index, :is_reminders_active)
    
      device = Device.find_by(chip_id: message[:device_id])
      unless device
        return render json: { status: 'error', message: 'Device not found' }, status: :not_found
      end
    
      # Parse device_info hiện tại
      device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      relays = device_info["relays"] || []
    
      relay_index = message[:relay_index].to_i
    
      # Kiểm tra index hợp lệ
      if relay_index >= relays.length
        return render json: { status: 'error', message: "Invalid relay index: #{relay_index}" }, status: :bad_request
      end
    
      # Cập nhật is_reminders_active
      is_active = ActiveModel::Type::Boolean.new.cast(message[:is_reminders_active])
      relays[relay_index]["is_reminders_active"] = is_active
    
      # Lưu lại device_info mới
      device_info["relays"] = relays
      device.device_info = device_info.to_json
    
      if device.save
        # Cập nhật reminders
        device.reminders.where(relay_index: relay_index).find_each do |reminder|
          if is_active
            unless reminder.enabled?
              reminder.update(enabled: true)
              reminder.schedule_next_job! unless reminder.job_jid.present?
              reminder.schedule_turn_off_job!
            end
          else
            reminder.cancel_scheduled_job!
            reminder.update(enabled: false)
          end
        end
    
        refresh message[:device_id]
        render json: { status: 'success', message: 'is_reminders_active updated successfully' }, status: :ok
      else
        render json: { status: 'error', message: device.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end
    
    def add_reminder
      device = Device.find_by(chip_id: params[:device_id])
      unless device
        return render json: { error: "Device not found" }, status: :not_found
      end

      # Phân tích start_time theo múi giờ của ứng dụng
      
      start_time = Time.zone.parse(params[:start_time]) rescue nil
      unless start_time
        return render json: { error: "Invalid start_time format" }, status: :unprocessable_entity
      end

      reminder = Reminder.new(
        device: device,
        relay_index: params[:relay_index],
        start_time: start_time,
        duration: params[:duration],
        repeat_type: params[:repeat_type]
      )

      if reminder.save

        user_id = current_user&.id rescue nil

        log = RelayLog.create(
            device_id: device.id,
            relay_index: params[:relay_index].to_i,
            turn_on_at: Time.current,
            turn_off_at: nil,
            triggered_by: "reminder_1st",
            command_source: "add_reminder",
            user_id: user_id,
            note: "Set relay ON trong #{(params[:duration].to_i / 1_000)} giây qua API"
            
          )

        unless log.persisted?
          Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
        end

        reminder.schedule_immediate_job_if_soon
        refresh(params[:device_id], log.id)
        redirect_to device_path(device), notice: "Updated successfully."
      else
        render json: { errors: reminder.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def remove_reminder
      device = Device.find_by(chip_id: params[:device_id])
      unless device
        return render json: { error: "Device not found" }, status: :not_found
      end
    
      reminder = Reminder.find_by(
        device: device,
        relay_index: params[:relay_index],
        start_time: params[:start_time]
      )
    
      unless reminder
        return render json: { error: "Reminder not found" }, status: :not_found
      end
    
      if reminder.destroy
        # render json: { message: "Reminder deleted successfully" }, status: :ok
        refresh params[:device_id]
        redirect_to device_path(device), notice: "Reminder removed successfully."
      else
        render json: { error: "Failed to delete reminder" }, status: :unprocessable_entity
      end
    end
    
    def device_info
      device_id = params[:device_id]
      device = Device.find_by(chip_id: device_id.to_s)
    
      if device
        device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
        device_info['update_url'] = device.url_firmware
        if device_info['relays'].present?
          device_info['relays'].each_with_index do |relay, index|
            reminders = Reminder.where(device_id: device.id, relay_index: index).map do |reminder|
              {
                start_time: reminder.start_time&.in_time_zone('Asia/Ho_Chi_Minh')&.iso8601,
                duration: reminder.duration,
                repeat_type: reminder.repeat_type
              }
            end
    
            # Gắn danh sách reminders mới lấy từ DB vào relay tương ứng
            relay['reminders'] = reminders
          end
        end
        
        render json: {
          status: 'success',          
          server_time: Time.current.strftime('%Y-%m-%dT%H:%M:%S'),
          device_info: device_info
        }, status: :ok

      else
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
        user_id = current_user&.id rescue nil
   
        device_id = Device.id_from_chip(message[:device_id])

        log = RelayLog.create(
            device_id: device_id,
            relay_index: message[:relay_index].to_i,
            turn_on_at: Time.current,
            turn_off_at: nil,
            triggered_by: "manual",
            command_source: "switchon",
            user_id: user_id,
            note: "Set relay ON forever"
          )

        unless log.persisted?
          Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
        end

        refresh(message[:device_id], log.id)
        render json: { status: 'success', message: 'Switched successfully' }, status: :ok
      else
        render json: { status: 'error', message: 'Failed to switch' }, status: :unprocessable_entity
      end
    end
    
    def set_longlast
      message = params.permit(:device_id, :longlast, :relay_index)

      topic = "#{message[:device_id]}/switchon"
      message_hash = {}
    
      # Kiểm tra và thêm các tham số vào hash
      message_hash["relay_index"] = message[:relay_index] if message[:relay_index].present?
      message_hash["longlast"] = message[:longlast].to_i if message[:longlast].present?
      message_hash["sent_time"] = Time.current.strftime('%Y-%m-%d %H:%M:%S')
      # Chuyển đổi hash thành JSON
      message_json = message_hash.to_json
      puts "#message json: #{message}"
    
      client = MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
    
      client.publish(topic, message_json, retain: false) if topic.present?
      client.disconnect()
      
      success = SwitchOnDurationService.new(
        message[:device_id],
        longlast: message[:longlast]&.to_i,
        relay_index: message[:relay_index].present? ? message[:relay_index].to_i : nil
      ).call
    
      if success
        # user_id = current_user&.id rescue nil
   
        # device_id = Device.id_from_chip(message[:device_id])

        # log = RelayLog.create(
        #     device_id: device_id,
        #     relay_index: message[:relay_index].to_i,
        #     turn_on_at: Time.current,
        #     turn_off_at: message[:longlast].present? ? Time.current + message[:longlast].to_i.seconds : nil,
        #     triggered_by: "api",
        #     command_source: "set_longlast",
        #     user_id: user_id,
        #     note: "Set relay ON trong #{(message[:longlast].to_i / 1_000)} giây qua API"
        #   )

        # unless log.persisted?
        #   Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
        # end
        # refresh(message[:device_id], log.id)
        render json: { status: 'success', message: 'Longlast set successfully' }, status: :ok
      else
        render json: { status: 'error', message: 'Failed to set longlast' }, status: :unprocessable_entity
      end
    end

    def restart
      topic = "#{params[:chip_id]}/restart"
      client = mqtt_client
      message = {
          "action": "restart",
          "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
       }.to_json
  
      client.publish(topic, message) if topic.present?
      client.disconnect()
      render json: { status: 'ok', message: 'Restart command sent' }
    end

    def update_last_seen
      device = Device.find_by(chip_id: params[:chip_id])
    
      unless device
        return render json: { status: 'error', message: 'Device not found' }, status: :not_found
      end
    
      # Cập nhật trường updated_at để đánh dấu "last seen"
      device.touch

      meta = device.parsed_meta_info
      meta["last_seen"] = Time.current.to_s
      meta["local_ip"] = params[:local_ip] || ""
      meta["build_version"] = params[:build_version] || 0
      meta["app_version"] = params[:app_version] || ""

      device.update(meta_info: meta.to_json)

      render json: {
        status: 'success',
        message: 'Device last seen time updated',
        last_seen: device.updated_at.strftime('%Y-%m-%d %H:%M:%S')
      }, status: :ok
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

    def update_version
      topic = "#{params[:chip_id]}/update_version"
      client = mqtt_client
      message = {
          "action": "update_version",
          "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
       }.to_json
  
      client.publish(topic, message) if topic.present?
      client.disconnect()
      render json: { status: 'ok', message: 'Update version command sent', topic: topic, message: message }
      
    end

    def reset_wifi 
      chip_id = params[:chip_id]
      topic = "#{chip_id}/reset_wifi"
  
      client = mqtt_client
      message = {
          "action": "reset_wifi",
          "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
       }

      client.publish(topic, message.to_json) if topic.present?
      client.disconnect()
      render json: { status: 'ok', message: 'Reset wifi command sent', topic: topic, message: message }

    end

    def refresh_device
      chip_id = params[:chip_id]
      refresh chip_id
      render json: { status: 'ok', message: 'Refresh command sent', topic: "#{chip_id}/refresh_device" }
    end
  
    private

    def mqtt_client
      MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
    end
    
    def trigger_device device
      raw_message_trigger = device.trigger
      json_params = JSON.parse(raw_message_trigger)
    
      # Tạo topic từ chip_id
      topic = "#{json_params['chip_id']}/switchon"
      raise "chip_id is missing" unless json_params['chip_id'].present?
    
      # Thêm sent_time
      json_params["sent_time"] = Time.current.strftime('%Y-%m-%d %H:%M:%S')
      message_with_timestamp = json_params.to_json
    
      # Gửi raw JSON (message) qua MQTT
      client = mqtt_client
    
      client.publish(topic, message_with_timestamp, retain: false) if topic.present?
      client.disconnect
    end

    def refresh(chip_id, log_id = nil)
      topic = "#{chip_id}/refresh"
  
      client = mqtt_client
      message = {
          "action": "refresh",
          "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
       }

      message[:log_id] = log_id if log_id.present?

      client.publish(topic, message.to_json) if topic.present?
      client.disconnect()
    end
  end
end
