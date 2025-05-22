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
        
        should_trigger = reminder.last_triggered_at.nil? || reminder.last_triggered_at < next_time
        if should_trigger && next_time.present? && next_time.between?(now - 5.minutes, future_time)
          reminder.update(last_triggered_at: next_time)
          reminder.schedule_next_job!

          puts "schedule_next_job "

        end

        # Tắt relay
        if off_time.present? && off_time.between?(now - 5.minutes, now + 5.minutes)
          reminder.schedule_turn_off_job!

        end

      end
    end

end
  