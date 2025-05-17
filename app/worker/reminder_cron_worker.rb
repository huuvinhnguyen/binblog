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
          refresh(reminder.device.chip_id)
        end

        # Tắt relay
        if off_time.present? && off_time.between?(now - 5.minutes, now + 5.minutes)
          reminder.schedule_turn_off_job!
          refresh(reminder.device.chip_id)
        end
      end
    end

    private

  def refresh(chip_id)
    topic = "#{chip_id}/refresh"
    client = mqtt_client

    message = {
      action: "refresh",
      sent_time: Time.current.strftime('%Y-%m-%d %H:%M:%S')
    }.to_json

    client.publish(topic, message) if topic.present?
    client.disconnect
  end

  def mqtt_client
    MQTT::Client.connect(
      host: "103.9.77.155",
      port: 1883
    )
  end
end
  