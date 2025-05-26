# app/jobs/reminder_cron_worker.rb
class ReminderCronWorker
    include Sidekiq::Worker
  
    def perform
      Rails.logger.info "[ReminderCronWorker] Running at: #{Time.zone.now} | Time.now: #{Time.now}"

      now = Time.current
      future_time = now + 5.minutes   
      Reminder.includes(:device).where(enabled: true).find_each do |reminder|
        
        next unless reminder.next_trigger_time.present? && reminder.relay_index.present?
  
        turn_on_at = reminder.next_trigger_time
        turn_off_at  = reminder.turn_off_time
  
        if reminder.should_turn_on?(now)
          reminder.schedule_next_job!
          puts "schedule_next_job"
        end
  
        if reminder.should_turn_off?(now)
          reminder.schedule_turn_off_job!
        end

      end
    end

end
  