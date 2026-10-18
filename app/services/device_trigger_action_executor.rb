class DeviceTriggerActionExecutor
  ELIGIBLE_STATUSES = %w[pending_publish pending_enqueue queued].freeze

  def initialize(execution: nil, execution_id: nil)
    @execution = execution
    @execution_id = execution_id || execution&.id
  end

  def call
    claimed = false
    execution = @execution || DeviceTriggerActionExecution.find_by(id: @execution_id)
    return unless execution
    execution.reload
    return unless ELIGIBLE_STATUSES.include?(execution.status)

    error_code = preflight_error(execution)
    return mark_skipped(execution, error_code) if error_code
    claimed = claim_for_publish(execution)
    return unless claimed

    DeviceTriggerCommandPublisher.new(execution: execution).call
    mark_publish_returned(execution)
  rescue DeviceTriggerCommandPublisher::ConnectError => e
    mark_failed(execution, 'mqtt_connect_failed', claimed: true) if execution
    log_failure(execution, e)
  rescue DeviceTriggerCommandPublisher::PublishError => e
    mark_failed(execution, 'publish_outcome_unknown', claimed: true) if execution
    log_failure(execution, e)
  rescue StandardError => e
    code = claimed ? 'publish_outcome_unknown' : 'execution_failed'
    mark_failed(execution, code, claimed: claimed) if execution
    log_failure(execution, e)
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
    execution.class.where(id: execution.id, status: ELIGIBLE_STATUSES).update_all(
      status: 'skipped', failed_at: now, error_code: code, updated_at: now
    )
  end

  def claim_for_publish(execution)
    now = Time.current
    execution.class.where(id: execution.id, status: ELIGIBLE_STATUSES).update_all(
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
    eligible_statuses = claimed ? ['publish_attempted'] : ELIGIBLE_STATUSES
    execution.class.where(id: execution.id, status: eligible_statuses).update_all(
      status: 'failed', failed_at: now, error_code: code, updated_at: now
    )
  end

  def log_failure(execution, error)
    Rails.logger.error("Device trigger execution #{execution&.id || @execution_id} failed: #{error.class}")
  end
end
