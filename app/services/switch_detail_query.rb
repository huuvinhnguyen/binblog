class SwitchDetailQuery
  def initialize(device:, user:)
    @device, @user = device, user
  end

  def call
    config = SwitchApi::Configuration.new(@device)
    {
      id: @device.id.to_s, chip_id: @device.chip_id, name: @device.name.to_s,
      device_type: 'switch', timezone: 'Asia/Ho_Chi_Minh', last_seen: last_seen,
      online: nil, state_source: 'server_snapshot', physical_state_verified: false,
      capabilities: {
        manual_switch: true, pulse: true, refresh: true, statistics: true,
        reminders: UserRelayFeature.feature_enabled?(@user, @device, 'reminder') && SwitchApi::Features.reminders_ready?
      },
      limits: { duration_min_ms: SwitchApi::Configuration::MIN_DURATION_MS,
                duration_max_ms: SwitchApi::Configuration::MAX_DURATION_MS, reminder_limit_per_relay: 100 },
      relays: config.relays.each_with_index.map do |relay, index|
        { index: index, switch_value: [0, 1].include?(relay['switch_value']) && relay['switch_value'].is_a?(Integer) ? relay['switch_value'] : nil,
          duration_ms: relay['longlast'].is_a?(Integer) ? relay['longlast'] : nil,
          reminders_active: [true, false].include?(relay['is_reminders_active']) ? relay['is_reminders_active'] : nil }
      end
    }
  end

  private

  def last_seen
    meta = @device.meta_info
    meta = JSON.parse(meta) if meta.is_a?(String)
    value = meta['last_seen'] if meta.is_a?(Hash)
    return unless value.is_a?(String)

    parsed = if /\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}\z/.match?(value)
               time = Time.strptime(value, '%Y-%m-%d %H:%M:%S %z')
               return unless time.strftime('%Y-%m-%d %H:%M:%S %z') == value

               time
             elsif /\A\d{4}-\d{2}-\d{2}T.+(?:Z|[+-]\d{2}:\d{2})\z/.match?(value)
               Time.iso8601(value)
             end
    parsed&.in_time_zone('Asia/Ho_Chi_Minh')&.iso8601
  rescue JSON::ParserError, ArgumentError, TypeError
    nil
  end
end
