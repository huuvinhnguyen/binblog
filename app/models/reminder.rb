class Reminder < ActiveRecord::Base
    require 'sidekiq/api'
    belongs_to :device
  
    REPEAT_TYPES = %w[daily once weekly monthly].freeze
  
    validates :relay_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :start_time, presence: true
    validates :repeat_type, presence: true, inclusion: { in: REPEAT_TYPES }
    validates :duration, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  
    # after_create :schedule_immediate_job_if_soon
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
      return unless enabled?
    
      # Hủy job cũ nếu đã có
      scheduled_set = Sidekiq::ScheduledSet.new
      if job_jid.present?
        old_job = scheduled_set.find { |j| j.jid == job_jid }
        if old_job
          old_job.delete
          Rails.logger.info "Đã huỷ ActivateRelayJob cũ (#{job_jid}) cho reminder #{id}"
        end
      end
    
      next_time = next_trigger_time
      return unless next_time
    
      # Lên lịch job mới
      jid = ActivateRelayJob.perform_at(next_time, id)
      update(job_jid: jid)
    end    

    def cancel_scheduled_job!
      scheduled_set = Sidekiq::ScheduledSet.new

      if job_jid.present?
        job = scheduled_set.find { |j| j.jid == job_jid }
        if job
          job.delete
          Rails.logger.info "Đã huỷ ActivateRelayJob #{job_jid} cho reminder #{id}"
        else
          Rails.logger.warn "Không tìm thấy ActivateRelayJob #{job_jid} để huỷ cho reminder #{id}"
        end
      end

      if turn_off_jid.present?
        off_job = scheduled_set.find { |j| j.jid == turn_off_jid }
        if off_job
          off_job.delete
          Rails.logger.info "Đã huỷ TurnOffRelayJob #{turn_off_jid} cho reminder #{id}"
        else
          Rails.logger.warn "Không tìm thấy TurnOffRelayJob #{turn_off_jid} để huỷ cho reminder #{id}"
        end
      end
    end

    # def turn_off_time
    #   return nil if duration.blank? || duration <= 0
  
    #   trigger_time = next_trigger_time
    #   return nil unless trigger_time
  
    #   trigger_time + (duration / 1_000).seconds
    # end

    def turn_off_time
      return nil if duration.blank? || duration <= 0
    
      return nil unless last_triggered_at.present?
    
      last_triggered_at + (duration / 1_000).seconds
    end

    def schedule_immediate_job_if_soon
      
      if next_trigger_time.present? && next_trigger_time <= 5.minutes.from_now
        schedule_next_job!
        schedule_turn_off_job!
      end
    end
    
    def schedule_turn_off_job!
      # return if turn_off_jid.present? # Nếu đã có job ID thì không lên lịch lại

      off_time = turn_off_time
      # return if off_time < Time.zone.now

      jid = TurnOffRelayJob.perform_at(off_time, device.chip_id, relay_index, id)
      update(turn_off_jid: jid)
    end

  end
  