class BuzzerDetails
  HISTORY_LIMIT = 20
  HISTORY_BATCH_SIZE = 200

  attr_reader :device, :linked_pirs, :events

  def initialize(device:, user:)
    @device = device
    @user = user
    @source_scope = @user.devices_for_current_user.where(device_type: 'pir')
    @relationships = DeviceTriggerConfigurationResolver.relationships_for_target(
      target_device: @device,
      source_scope: @source_scope
    )
    @relationship_by_source_id = @relationships.index_by { |relationship| relationship.source_device.id }
    @linked_pirs = @relationships.map(&:source_device).uniq
    @events = load_events
  end

  def online?
    device_info['update_at'].to_i > 5.minutes.ago.to_i
  end

  def last_seen
    value = device.parsed_meta_info['last_seen']
    Time.zone.parse(value.to_s)&.iso8601 if value.present?
  rescue ArgumentError, TypeError
    nil
  end

  def last_triggered_at
    events.first&.occurred_at&.iso8601
  end

  def trigger_for(pir)
    relationship = @relationship_by_source_id[pir.id]
    return {} unless relationship

    {
      'chip_id' => device.chip_id,
      'relay_index' => relationship.relay_index,
      'longlast' => relationship.duration_ms,
      'configuration_mode' => relationship.origin
    }
  end

  def event_payload(event)
    execution = @execution_by_event_id[event.id]
    return event.parsed_payload unless execution

    event.parsed_payload.merge(
      'target_chip_id' => execution.target_chip_id,
      'relay_index' => execution.relay_index,
      'longlast' => execution.duration_ms,
      'execution_status' => execution.status,
      'error_code' => execution.error_code
    )
  end

  private

  def device_info
    @device_info ||= parse_json(device.device_info)
  end

  def parse_json(value)
    parsed = value.is_a?(Hash) ? value : JSON.parse(value.presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, TypeError
    {}
  end

  def load_events
    accessible_source_ids = @source_scope.pluck(:id)
    new_executions = DeviceTriggerActionExecution
                     .includes(device_event: :device)
                     .joins(:device_event)
                     .where(target_device_id: device.id, device_events: { device_id: accessible_source_ids })
                     .order('device_events.occurred_at DESC, device_events.id DESC')
                     .limit(HISTORY_LIMIT)
                     .to_a
    @execution_by_event_id = new_executions.index_by(&:device_event_id)

    source_ids = linked_pirs.map(&:id)
    legacy_matches = load_legacy_events(source_ids)
    events = (new_executions.map(&:device_event) + legacy_matches).uniq(&:id)
    events.sort_by { |event| [event.occurred_at, event.id] }.reverse.first(HISTORY_LIMIT)
  end

  def load_legacy_events(source_ids)
    return [] if source_ids.empty?

    matches = []
    cursor = nil
    loop do
      scope = DeviceEvent.includes(:device).where(device_id: source_ids, event_type: 'motion_detected')
      if cursor
        scope = scope.where('occurred_at < ? OR (occurred_at = ? AND id < ?)', cursor.occurred_at, cursor.occurred_at, cursor.id)
      end
      batch = scope.order(occurred_at: :desc, id: :desc).limit(HISTORY_BATCH_SIZE).to_a
      break if batch.empty?

      matches.concat(batch.select do |event|
        !@execution_by_event_id.key?(event.id) && event.parsed_payload['target_chip_id'] == device.chip_id
      end)
      break if matches.size >= HISTORY_LIMIT || batch.size < HISTORY_BATCH_SIZE

      cursor = batch.last
    end
    matches.first(HISTORY_LIMIT)
  end
end
