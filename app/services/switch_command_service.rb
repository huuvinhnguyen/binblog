class SwitchCommandService
  def initialize(device:, user:, request_id:, publisher: SwitchApi::Publisher.new)
    @device, @user, @request_id, @publisher = device, user, request_id, publisher
  end

  def call(operation:, relay_index: nil, switch_value: nil, duration_ms: nil)
    event = nil
    @device.with_lock do
      unless @user.devices_for_current_user.where(id: @device.id, device_type: 'switch').exists?
        raise SwitchApi::Error.new('switch_not_found', status: :not_found)
      end
      config = SwitchApi::Configuration.new(@device)
      chip_id = @device.chip_id
      unless chip_id.is_a?(String) && /\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/.match?(chip_id)
        raise SwitchApi::Error.new('invalid_configuration')
      end
      payload = { sent_time: Time.current.strftime('%Y-%m-%d %H:%M:%S') }
      if operation == 'refresh'
        topic = "#{chip_id}/refresh"
        payload[:action] = 'refresh'
      else
        index = config.relay!(relay_index)
        topic = "#{chip_id}/switchon"
        payload[:relay_index] = index
        case operation
        when 'state'
          unless switch_value.is_a?(Integer) && [0, 1].include?(switch_value)
            raise SwitchApi::Error.new('invalid_switch_value')
          end
          payload[:switch_value] = switch_value
        when 'pulse'
          raise SwitchApi::Error.new('invalid_duration') unless SwitchApi::Configuration.duration?(duration_ms)

          payload[:longlast] = duration_ms
        else
          raise SwitchApi::Error.new('invalid_operation')
        end
      end
      event = @device.device_events.create!(
        event_type: 'switch_command_requested', occurred_at: Time.current,
        payload: { operation: operation, relay_index: payload[:relay_index], switch_value: switch_value,
                   duration_ms: duration_ms, request_id: @request_id, user_id: @user.id }
      )
      @topic, @payload = topic, payload
    end

    @publisher.call(topic: @topic, payload: @payload)
    record_result(event, 'publish_returned')
    { status: 'accepted', outcome: 'publish_returned', acknowledgement: 'none',
      request_id: @request_id, event_id: event.id.to_s }
  rescue SwitchApi::Publisher::Unavailable
    record_failed_result(event, 'not_attempted') if event
    raise SwitchApi::Error.new('command_unavailable', status: :service_unavailable, outcome: 'not_attempted')
  rescue SwitchApi::Publisher::OutcomeUnknown
    record_failed_result(event, 'unknown') if event
    raise SwitchApi::Error.new('command_outcome_unknown', status: :bad_gateway, outcome: 'unknown')
  rescue ActiveRecord::ActiveRecordError
    raise SwitchApi::Error.new(event ? 'command_outcome_unknown' : 'audit_unavailable',
                               status: event ? :bad_gateway : :service_unavailable,
                               outcome: event ? 'unknown' : 'not_attempted')
  end

  private

  def record_failed_result(event, outcome)
    record_result(event, outcome)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("Switch command result audit unavailable: #{e.class}")
  end

  def record_result(event, outcome)
    @device.device_events.create!(event_type: 'switch_command_result', occurred_at: Time.current,
                                  payload: { requested_event_id: event.id.to_s, request_id: @request_id, outcome: outcome })
  end
end
