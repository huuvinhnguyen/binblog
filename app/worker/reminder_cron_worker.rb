# app/jobs/reminder_cron_worker.rb
class ReminderCronWorker
    include Sidekiq::Worker
  
    def perform
      now = Time.zone.now
      future_time = now + 5.minutes   
      Reminder.includes(:device).where(enabled: true).find_each do |reminder|
        
        next unless reminder.next_trigger_time.present? && reminder.relay_index.present?
  
        turn_on_at = reminder.next_trigger_time
        turn_off_at  = reminder.turn_off_time
  
        # Bật relay
        
        should_trigger = reminder.last_triggered_at.nil? || reminder.last_triggered_at < turn_on_at
        if should_trigger && turn_on_at.between?(now - 5.minutes, future_time)
          reminder.schedule_next_job!
          puts "schedule_next_job "

        end

        # Tắt relay
        if turn_off_at.present? && turn_off_at.between?(now - 5.minutes, now + 5.minutes)
          reminder.schedule_turn_off_job!
        end

      end
    end

end
  