class DeviceTriggerActionJob
  include Sidekiq::Worker

  sidekiq_options retry: false

  def perform(execution_id)
    claimed = false
    execution = DeviceTriggerActionExecution.find_by(id: execution_id)
    return unless execution
    return unless %w[pending_enqueue queued].include?(execution.status)

    catch(:device_trigger_duplicate) do
      error_code = preflight_error(execution)
      return mark_skipped(execution, error_code) if error_code

      publisher = DeviceTriggerCommandPublisher.new(execution: execution)
      publisher.call do
        execution.reload
        error_code = preflight_error(execution)
        if error_code
          mark_skipped(execution, error_code)
          throw :device_trigger_duplicate
        end
        claimed = claim_for_publish(execution)
        throw :device_trigger_duplicate unless claimed
      end
      mark_publish_returned(execution) if claimed
    end
  rescue DeviceTriggerCommandPublisher::PublishError, StandardError => e
    if execution
      code = claimed ? 'publish_outcome_unknown' : 'mqtt_connect_failed'
      mark_failed(execution, code, claimed: claimed)
    end
    Rails.logger.error("Device trigger execution #{execution_id} failed: #{e.class}")
  end

  private

  def preflight_error(execution)
    return unless execution.action_key.start_with?('action:')

    action = execution.device_trigger_action
    return 'action_missing' unless action
    return 'action_disabled' unless action.enabled?

    action.runtime_error_code
  end

  def mark_skipped(execution, code)
    now = Time.current
    execution.class.where(id: execution.id, status: %w[pending_enqueue queued]).update_all(
      status: 'skipped', failed_at: now, error_code: code, updated_at: now
    )
  end

  def claim_for_publish(execution)
    now = Time.current
    execution.class.where(id: execution.id, status: %w[pending_enqueue queued]).update_all(
      status: 'publish_attempted', publish_attempted_at: now, updated_at: now
    ) == 1
  end

  def mark_publish_returned(execution)
    now = Time.current
    execution.class.where(id: execution.id, status: 'publish_attempted').update_all(
      status: 'publish_returned', publish_returned_at: now, error_code: nil, updated_at: now
    )
  end

  def mark_failed(execution, code, claimed:)
    now = Time.current
    eligible_statuses = claimed ? ['publish_attempted'] : %w[pending_enqueue queued]
    execution.class.where(id: execution.id, status: eligible_statuses).update_all(
      status: 'failed', failed_at: now, error_code: code, updated_at: now
    )
  end
end
