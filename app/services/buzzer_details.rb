class BuzzerDetails
  HISTORY_LIMIT = 20
  HISTORY_BATCH_SIZE = 200

  attr_reader :device, :linked_pirs, :events

  def initialize(device:, user:)
    @device = device
    @user = user
    # Trigger is stored as text JSON, so linked PIRs are filtered in Ruby (O(n)).
    # Keep this bounded to the user's accessible PIR set; denormalization is out of scope.
    @linked_pirs = @user.devices_for_current_user.where(device_type: 'pir').to_a.select do |pir|
      trigger_for(pir)['chip_id'] == @device.chip_id
    end
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
    parse_json(pir.trigger)
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
    source_ids = linked_pirs.map(&:id)
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

      matches.concat(batch.select { |event| event.parsed_payload['target_chip_id'] == device.chip_id })
      break if matches.size >= HISTORY_LIMIT || batch.size < HISTORY_BATCH_SIZE

      cursor = batch.last
    end
    matches.first(HISTORY_LIMIT)
  end
end
