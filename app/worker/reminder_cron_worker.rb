# app/jobs/reminder_cron_worker.rb
class ReminderCronWorker
    include Sidekiq::Worker
  
    def perform
      now = Time.zone.now
      future_time = now + 5.minutes   
      Reminder.includes(:device).where(enabled: true).find_each do |reminder|
        
        next unless reminder.start_time.present? && reminder.relay_index.present?
  
        next_time = reminder.next_trigger_time
        off_time  = reminder.turn_off_time
        
  
        # Bật relay
        if next_time.present? && next_time.between?(now - 5.minutes, future_time)
          reminder.schedule_next_job!
          user_id = current_user&.id rescue nil

          log = RelayLog.create(
              device_id: reminder.device.id,
              relay_index: reminder.relay_index,
              turn_on_at: next_time,
              turn_off_at: nil,
              triggered_by: "ReminderCronWorker",
              command_source: "reminder",
              user_id: user_id,
              note: "Set relay ON trong #{(reminder.duration / 1_000)} giây qua Reminder"
            )

          unless log.persisted?
            Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
          end
          refresh(reminder.device.chip_id, log.id)

        end

        # Tắt relay
        if off_time.present? && off_time.between?(now - 5.minutes, now + 5.minutes)
          reminder.schedule_turn_off_job!
          user_id = current_user&.id rescue nil

          log = RelayLog.create(
              device_id: reminder.device.id,
              relay_index: reminder.relay_index,
              turn_on_at: nil,
              turn_off_at: off_time,
              triggered_by: "ReminderCronWorker",
              command_source: "reminder",
              user_id: user_id,
              note: "Set relay ON trong #{(reminder.duration / 1_000)} giây qua Reminder"
            )

          unless log.persisted?
            Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
          end
          refresh(reminder.device.chip_id, log.id)

        end

      end
    end

    private

    def refresh_device(reminder)

      user_id = current_user&.id rescue nil

        log = RelayLog.create(
            device_id: reminder.device.id,
            relay_index: reminder.relay_index,
            turn_on_at: next_time,
            turn_off_at: off_time,
            triggered_by: "ReminderCronWorker",
            command_source: "reminder",
            user_id: user_id,
            note: "Set relay ON trong #{(reminder.duration / 1_000)} giây qua Reminder"
          )

        unless log.persisted?
          Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
        end
        refresh(reminder.device.chip_id, log.id)

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
  