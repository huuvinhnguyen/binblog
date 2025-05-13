# app/jobs/reminder_cron_worker.rb
class ReminderCronWorker
    include Sidekiq::Worker
  
    def perform
      now = Time.zone.now
      from_time = now - 5.minutes
  
      Reminder.includes(:device).where(enabled: true).find_each do |reminder|

        next unless reminder.start_time.present? && reminder.relay_index.present?
  
        next_time = reminder.next_trigger_time
        off_time  = reminder.turn_off_time
  
        # Bật relay
        if next_time.present? && next_time.between?(from_time, now)
          reminder.schedule_next_job!
        end
  
        # Tắt relay
        if off_time.present? && off_time.between?(from_time, now)
          TurnOffRelayJob.perform_at(off_time, reminder.device.chip_id, reminder.relay_index)
        end
      end
    end
  end
  