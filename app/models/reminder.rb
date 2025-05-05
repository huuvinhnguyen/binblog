class Reminder < ActiveRecord::Base
    require 'sidekiq/api'
    belongs_to :device
  
    REPEAT_TYPES = %w[daily once weekly monthly].freeze
  
    validates :relay_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :start_time, presence: true
    validates :repeat_type, presence: true, inclusion: { in: REPEAT_TYPES }
    validates :duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
    before_save :parse_start_time_to_next_trigger
    before_destroy :cancel_scheduled_job!

    # after_commit :schedule_job, on: [:create, :update]
  
    def next_trigger_time
      return nil unless start_time.is_a?(Time) || start_time.is_a?(DateTime)
    
      hour = start_time.hour
      minute = start_time.min
      base_time = Time.zone.now.change(hour: hour, min: minute, sec: 0)
    
      case repeat_type
      when "daily"
        base_time < Time.zone.now ? base_time + 1.day : base_time
    
      when "weekly"
        # Dùng wday từ start_time thay vì created_at
        wday = start_time.wday
        current_wday = Time.zone.now.wday
        days_until = (wday - current_wday) % 7
        next_time = base_time + days_until.days
        next_time < Time.zone.now ? next_time + 7.days : next_time
    
      when "monthly"
        day = start_time.day
        base_time = Time.zone.now
        next_month = base_time.month + 1
        next_year = base_time.year
        if next_month > 12
          next_month = 1
          next_year += 1
        end
      
        if Date.valid_date?(next_year, next_month, day)
          Time.zone.local(next_year, next_month, day, hour, minute, 0)
        else
          nil
        end
    
      when "once"
        start_time
    
      else
        nil
      end
    end

    # Public
    def schedule_next_job!
      next_time = next_trigger_time
      return unless next_time

      jid = ActivateRelayJob.perform_at(next_time, id)
      update(job_jid: jid)
    end

    def cancel_scheduled_job!
      return unless job_jid.present?

      scheduled_set = Sidekiq::ScheduledSet.new
      scheduled_set.each do |job|
        if job.jid == job_jid
          job.delete
          puts "Đã huỷ job #{job_jid} cho reminder #{id}"
          break
        end
      end
      update(job_jid: nil)
    end

    
    private

    def schedule_job
        ReminderSchedulerService.new(self).schedule!
    end
  
    def parse_start_time_to_next_trigger
      return if repeat_type == "once"
  
      self.last_triggered_at = next_trigger_time
    end

  end
  