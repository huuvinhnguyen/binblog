class SwitchReminderService
  def initialize(device:, user:, relay_index:)
    @device, @user = device, user
    @index = SwitchApi::Configuration.new(device).relay!(relay_index)
  end

  def list(after_id: nil, limit: nil)
    after = decimal!(after_id || '0', 0..9_223_372_036_854_775_807)
    count = decimal!(limit || '50', 1..100)
    rows = @device.reminders.where(relay_index: @index).where('id > ?', after).order(:id).limit(count + 1).to_a
    more = rows.length > count
    rows = rows.first(count)
    { status: 'success', reminders: rows.map { |row| serialize(row) }, next_after_id: more ? rows.last.id.to_s : nil }
  end

  def reject_write!
    unless UserRelayFeature.feature_enabled?(@user, @device, 'reminder')
      raise SwitchApi::Error.new('reminder_not_allowed', status: :forbidden)
    end

    # No write or scheduler is implemented until handoff section 8 is resolved.
    raise SwitchApi::Error.new('reminder_execution_unavailable', status: :service_unavailable, outcome: 'not_attempted')
  end

  private

  def decimal!(value, range)
    unless value.is_a?(String) && /\A(?:0|[1-9][0-9]{0,18})\z/.match?(value) && range.cover?(value.to_i)
      raise SwitchApi::Error.new('invalid_pagination')
    end

    value.to_i
  end

  def serialize(row)
    valid = row.start_time.present? && SwitchApi::Configuration.duration?(row.duration) &&
            Reminder::REPEAT_TYPES.include?(row.repeat_type)
    { id: row.id.to_s, device_id: @device.id.to_s, relay_index: @index,
      start_time: row.start_time&.in_time_zone('Asia/Ho_Chi_Minh')&.iso8601,
      duration_ms: row.duration, repeat_type: row.repeat_type.to_s,
      enabled: row.enabled?, configuration_valid: valid }
  end
end
