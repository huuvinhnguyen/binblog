module Api
  class Api::DevicesController < ApplicationController
    before_action :authenticate_api_user!, only: [:index, :motion_stats, :motion_heatmap, :buzzer, :buzzer_linked_pirs, :buzzer_history, :buzzer_test]
    before_action :reject_failed_api_authentication, only: [:index, :motion_stats, :motion_heatmap, :buzzer, :buzzer_linked_pirs, :buzzer_history, :buzzer_test]
    before_action :accessible_buzzer, only: [:buzzer, :buzzer_linked_pirs, :buzzer_history, :buzzer_test]

    def buzzer
      details = BuzzerDetails.new(device: @buzzer, user: current_user)
      render json: {
        status: 'success',
        buzzer: {
          id: @buzzer.id, name: @buzzer.name, chip_id: @buzzer.chip_id,
          device_type: @buzzer.device_type, online: details.online?,
          last_seen: details.last_seen, linked_pir_count: details.linked_pirs.size,
          last_triggered_at: details.last_triggered_at
        }
      }
    end

    def buzzer_linked_pirs
      details = BuzzerDetails.new(device: @buzzer, user: current_user)
      render json: { status: 'success', linked_pirs: details.linked_pirs.map do |pir|
        trigger = details.trigger_for(pir)
        { id: pir.id, name: pir.name, chip_id: pir.chip_id,
          relay_index: trigger['relay_index'] || 0, longlast: trigger['longlast'] }
      end }
    end

    def buzzer_history
      details = BuzzerDetails.new(device: @buzzer, user: current_user)
      render json: { status: 'success', events: details.events.map do |event|
        payload = event.parsed_payload
        { id: event.id, event_type: event.event_type, occurred_at: event.occurred_at.iso8601,
          pir: { id: event.device.id, name: event.device.name, chip_id: event.device.chip_id },
          relay_index: payload['relay_index'], longlast: payload['longlast'] }
      end }
    end

    def buzzer_test
      result = BuzzerTestService.new(device: @buzzer, user: current_user).call
      render json: { status: 'success', message: 'Command sent to MQTT broker',
                     relay_index: result.relay_index, longlast: result.longlast }
    rescue BuzzerTestService::ConfigurationError => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    rescue BuzzerTestService::CooldownError => e
      render json: { status: 'error', message: e.message }, status: :too_many_requests
    rescue BuzzerTestService::PublishError => e
      render json: { status: 'error', message: e.message }, status: :service_unavailable
    end

    def index
      devices = current_user.present? ? current_user.devices_for_current_user : Device.all

      render json: {
        status: 'success',
        count: devices.count,
        devices: devices.map do |device|
          {
            id: device.id,
            name: device.name,
            chip_id: device.chip_id,
            device_type: device.device_type,
            status: device.status,
            is_payment: device.is_payment,
            note: device.note,
            url_firmware: device.url_firmware,
            device_info: safe_parse_json(device.device_info),
            meta_info: device.parsed_meta_info,
            created_at: device.created_at&.iso8601,
            updated_at: device.updated_at&.iso8601
          }
        end
      }, status: :ok
    rescue => e
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end

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
      device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      relays = device_info["relays"] || []
      relay_index = params[:relay_index].to_i
      is_reminders_active = relays[relay_index]["is_reminders_active"] == true ? 1 : 0

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
        repeat_type: params[:repeat_type],
        enabled: is_reminders_active
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

    def motion_stats
      device = accessible_pir_device
      return unless device

      date = Date.iso8601(params[:date].presence || Time.zone.today.to_s)
      day_start = Time.zone.local(date.year, date.month, date.day).beginning_of_day
      day_end = day_start.end_of_day
      counts_by_hour = motion_events_for(device, day_start..day_end)
                        .group_by { |event| event.occurred_at.in_time_zone(Time.zone).hour }

      values = 24.times.map { |hour| counts_by_hour.fetch(hour, []).count }

      render json: {
        status: 'success',
        date: date.iso8601,
        labels: 24.times.map { |hour| format('%02d:00', hour) },
        values: values,
        total: values.sum,
        recent_events: device.device_events.where(event_type: 'motion_detected')
                             .order(occurred_at: :desc, id: :desc).limit(20).map do |event|
          { id: event.id, event_type: event.event_type, occurred_at: event.occurred_at.iso8601 }
        end
      }
    rescue Date::Error
      render json: { status: 'error', message: 'Invalid date. Use YYYY-MM-DD.' }, status: :unprocessable_entity
    end

    def motion_heatmap
      device = accessible_pir_device
      return unless device

      days = params[:days].to_i
      days = 30 if days.zero?
      days = days.clamp(1, 90)

      start_date = Time.zone.today - (days - 1)
      start_at = start_date.beginning_of_day
      counts_by_date = motion_events_for(device, start_at..Time.current.end_of_day)
                       .group_by { |event| event.occurred_at.in_time_zone(Time.zone).to_date }

      data = days.times.map do |offset|
        date = start_date + offset.days
        { date: date.iso8601, count: counts_by_date.fetch(date, []).count }
      end

      render json: {
        status: 'success',
        from: start_date.iso8601,
        to: Time.zone.today.iso8601,
        max_count: data.map { |entry| entry[:count] }.max || 0,
        data: data
      }
    end

    def trigger
      # Lấy JSON từ body của request
      # raw_body = request.body.read

      begin

        device = Device.find_by(chip_id: params[:chip_id])

        unless device
          return render json: { status: 'error', message: 'Device not found' }, status: :not_found
        end

        # `chip_id` identifies the PIR that detected motion. Its trigger config
        # identifies the target device that receives the existing MQTT command.
        trigger_config = JSON.parse(device.trigger)

        # Log motion detection on the PIR while retaining the target metadata so
        # the Buzzer UI can later show which PIR caused a command.
        device.device_events.create!(
          event_type: 'motion_detected',
          occurred_at: Time.current,
          payload: {
            triggered_from: request.remote_ip,
            user_agent: request.user_agent,
            target_chip_id: trigger_config['chip_id'],
            relay_index: trigger_config['relay_index'],
            longlast: trigger_config['longlast']
          }
        )

        # Execute existing relay trigger via MQTT
        trigger_device device, trigger_config

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
     
      success = SwitchOnDurationService.new(
        message[:device_id],
        longlast: message[:longlast]&.to_i,
        relay_index: message[:relay_index]&.to_i
      ).call
    
      if success
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
      # render json: { status: 'ok', message: 'Refresh command sent', topic: "#{chip_id}/refresh_device" }
      device = Device.find_by(chip_id: chip_id)

      respond_to do |format|
        format.json do
          if device
            render json: {
              status: "ok",
              message: "Refresh command sent",
              topic: "#{chip_id}/refresh_device"
            }, status: :ok
          else
            render json: {
              status: "error",
              message: "Device not found"
            }, status: :not_found
          end
        end

        format.html do
            if device
              redirect_back fallback_location: device_path(device),
                            notice: "Đã làm mới thiết bị."
            else
              redirect_back fallback_location: root_path,
                            alert: "Không tìm thấy thiết bị."
            end
        end
      end   
    end
    
    def time
      # Plain text – cực nhẹ cho ESP
      self.response.headers["Content-Type"] = "text/plain"
      render plain: Time.current.to_i
    end
  
    private

    def mqtt_client
      MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
    end
    
    def trigger_device(device, trigger_config = nil)
      json_params = trigger_config || JSON.parse(device.trigger)
    
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

    def safe_parse_json(value)
      return {} if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError, TypeError
      {}
    end

    def accessible_pir_device
      device = current_user.devices_for_current_user.find_by(chip_id: params[:chip_id])

      unless device&.device_type == 'pir'
        render json: { status: 'error', message: 'PIR device not found' }, status: :not_found
        return nil
      end

      device
    end

    def accessible_buzzer
      return if performed?

      @buzzer = current_user.devices_for_current_user.find_by(id: params[:id], device_type: 'buzzer')
      render json: { status: 'error', message: 'Buzzer device not found' }, status: :not_found unless @buzzer
    end

    def motion_events_for(device, period)
      device.device_events.where(event_type: 'motion_detected', occurred_at: period)
    end

    def authenticate_api_user!
      auth_header = request.headers['Authorization']
      token = auth_header&.split(' ')&.last

      if token.present?
        payload = JWT.decode(
          token,
          Rails.application.secret_key_base,
          true,
          algorithm: 'HS256',
          verify_expiration: true
        ).first
        @current_user = User.find(payload['user_id'])
        return
      end

      if user_signed_in? && current_user.present?
        @current_user = current_user
        return
      end

      return render json: { error: 'Unauthorized' }, status: :unauthorized
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      @api_authentication_failed = true
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    def reject_failed_api_authentication
      return unless @api_authentication_failed

      render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    def current_user
      @current_user || super
    end
  end
end
