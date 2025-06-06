class TurnOffRelayJob
    include Sidekiq::Worker
  
    def perform(device_id, relay_index, reminder_id = nil)

      device = Device.find_by(chip_id: device_id)
      return unless device&.device_info.present?
  
      device_info = JSON.parse(device.device_info)
      relays = device_info["relays"] || []
      return unless relay_index < relays.length
  
      relay = relays[relay_index]
      relay["switch_value"] = 0
      device_info["update_at"] = Time.zone.now.to_i
      device_info["relays"][relay_index] = relay

      # device.update!(device_info: device_info.to_json)
      success = device.update(device_info: device_info.to_json)

      unless success
        
        note = device.errors.full_messages.join(", ").to_s
        sleep 1
        success = device.update(device_info: device_info.to_json)

        unless success
          Rails.logger.error("❌ Retry cập nhật thiết bị #{device_id} cũng thất bại.")
          log = create_log(device_id, relay_index, nil, Time.current, nil, "Update thất bại, relay có thể không tắt #{note}")
          return
        end
        return
      end
      device.reload
  
      puts "TurnOffRelayJob: Đã tắt relay #{relay_index} của thiết bị #{device_id}"

      reminder = Reminder.find_by(id: reminder_id)
      if reminder.present? 

        turn_off_at = Time.current
        note = "Set relay OFF sau #{(reminder.duration / 1_000)} giây qua Reminder"
        log = create_log(device.id, relay_index, reminder.next_trigger_time, reminder.turn_off_time, nil, note)
        refresh(device_id, log.id)
        puts note

      else

        turn_off_at = Time.current
        refresh(device_id)
        note = "Turn off relay switch_relay #{device.device_info['relays'][relay_index]['switch_value']}"
        log = create_log(device.id, relay_index,nil, turn_off_at, nil, note)
        puts note

      end
      
    end

    private
    def create_log(device_id, relay_index, turn_on_at = nil, turn_off_at = nil, duration = nil, note = nil)

      log = RelayLog.create(
                device_id: device_id,
                relay_index: relay_index,
                turn_on_at: turn_on_at,
                turn_off_at: turn_off_at,
                triggered_by: "ReminderCronWorker",
                command_source: "reminder off",
                user_id: nil,
                note: note
              )
  
      unless log.persisted?
        Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
      end
      log
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
  
    def mqtt_client
      MQTT::Client.connect(
        host: "103.9.77.155",
        port: 1883
      )
    end

end