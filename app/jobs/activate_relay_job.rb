class ActivateRelayJob
  include Sidekiq::Worker

  def perform(reminder_id)
    puts "ActivateRelayJob perform"

    reminder = Reminder.find_by(id: reminder_id)
    return unless reminder

    device = reminder.device
    relay_index = reminder.relay_index
    return unless device&.device_info.present?

    device_info = JSON.parse(device.device_info)
    relays = device_info["relays"] || []
    return unless relay_index < relays.length

    relay = relays[relay_index]
    relay["switch_value"] = 1
    device_info["relays"][relay_index] = relay
    device_info["update_at"] = Time.zone.now.to_i
    updated = device.update(device_info: device_info.to_json)
    if updated
      # 👉 Chỉ update reminder và tạo log nếu update device thành công
      reminder.update(last_triggered_at: Time.current)
      log = create_log(reminder)
      refresh(device.chip_id, log.id)
    else
      Rails.logger.error("[ActivateRelayJob] Failed to update device_info for device #{device.id}")
    end

  end

  private

  def create_log reminder
    log = RelayLog.create(
              device_id: reminder.device.id,
              relay_index: reminder.relay_index,
              turn_on_at: reminder.next_trigger_time,
              turn_off_at: nil,
              triggered_by: "ReminderCronWorker",
              command_source: "reminder",
              user_id: nil,
              note: "Set relay ON trong #{(reminder.duration / 1_000)} giây qua Reminder"
            )

    unless log.persisted?
      Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
    end
    log
  end

  def refresh(chip_id, log_id = nil)
    # topic = "#{chip_id}/refresh"

    # client = mqtt_client
    # message = {
    #     "action": "refresh",
    #     "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
    #  }

    # message[:log_id] = log_id if log_id.present?
    # client.publish(topic, message.to_json) if topic.present?
    # client.disconnect()
  end

  def mqtt_client
    MQTT::Client.connect(
      host: "103.9.77.155",
      port: 1883
    )
  end
end
