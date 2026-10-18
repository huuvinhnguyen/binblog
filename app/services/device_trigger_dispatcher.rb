class DeviceTriggerDispatcher
  InvalidConfiguration = Class.new(StandardError)

  def initialize(source_device:, request_metadata: {})
    @source_device = source_device
    @request_metadata = request_metadata
  end

  def call
    resolver = DeviceTriggerConfigurationResolver.new(source_device: @source_device)
    mode = resolver.mode
    raise InvalidConfiguration, 'Invalid or missing trigger configuration' if %w[none invalid_legacy].include?(mode)

    event, executions = ActiveRecord::Base.transaction do
      @source_device.lock!
      mode = DeviceTriggerConfigurationResolver.new(source_device: @source_device).mode
      raise InvalidConfiguration, 'Invalid or missing trigger configuration' if %w[none invalid_legacy].include?(mode)

      event = create_event(mode)
      executions = if mode == 'actions'
                     build_action_executions(event)
                   else
                     [build_legacy_execution(event)]
                   end
      [event, executions]
    end

    executions.each { |execution| execute(execution) }
    event
  end

  private

  def create_event(mode)
    selected = if mode == 'actions'
                 DeviceTriggerFeature.enabled? ? @source_device.trigger_actions.usable.count : 0
               else
                 1
               end
    legacy_metadata = if mode == 'legacy'
                        payload = DeviceTriggerConfigurationResolver.new(source_device: @source_device).legacy_payload
                        {
                          'target_chip_id' => payload['chip_id'],
                          'relay_index' => payload['relay_index'],
                          'longlast' => payload['longlast']
                        }
                      else
                        {}
                      end
    @source_device.device_events.create!(
      event_type: 'motion_detected',
      occurred_at: Time.current,
      payload: @request_metadata.merge(legacy_metadata).merge(
        'configuration_mode' => mode,
        'selected_action_count' => selected
      )
    )
  end

  def build_action_executions(event)
    return [] unless DeviceTriggerFeature.enabled?

    @source_device.trigger_actions.usable.runtime_order.includes(:target_device).map do |action|
      error_code = action.runtime_error_code
      event.trigger_action_executions.create!(
        device_trigger_action: action,
        target_device: action.target_device,
        action_key: "action:#{action.id}",
        target_chip_id: action.target_device&.chip_id || 'missing',
        action_type: action.action_type,
        relay_index: action.relay_index,
        duration_ms: action.duration_ms,
        delay_ms: action.delay_ms,
        configured_position: action.position,
        command_payload: action_command_payload(action),
        status: error_code ? 'skipped' : 'pending_publish',
        scheduled_for: Time.current + (action.delay_ms / 1000.0),
        failed_at: error_code ? Time.current : nil,
        error_code: error_code
      )
    end
  end

  def build_legacy_execution(event)
    payload = DeviceTriggerConfigurationResolver.new(source_device: @source_device).legacy_payload
    raise InvalidConfiguration, 'Invalid or missing trigger configuration' unless payload

    target = Device.find_by(chip_id: payload['chip_id'])
    event.trigger_action_executions.create!(
      target_device: target,
      action_key: 'legacy',
      target_chip_id: payload.fetch('chip_id'),
      action_type: 'relay_pulse',
      relay_index: integer_or_nil(payload['relay_index']),
      duration_ms: integer_or_nil(payload['longlast']),
      delay_ms: 0,
      configured_position: 0,
      command_payload: payload,
      status: 'pending_publish',
      scheduled_for: Time.current
    )
  end

  def action_command_payload(action)
    {
      'chip_id' => action.target_device&.chip_id,
      'relay_index' => action.relay_index,
      'longlast' => action.duration_ms
    }
  end

  def integer_or_nil(value)
    value.is_a?(Integer) ? value : nil
  end

  def execute(execution)
    return unless execution.status == 'pending_publish'

    DeviceTriggerActionExecutor.new(execution: execution).call
  rescue StandardError => e
    Rails.logger.error("Device trigger execution #{execution.id} dispatch failed: #{e.class}")
  end
end
