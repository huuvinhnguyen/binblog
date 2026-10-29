class SwitchRelayStatisticsQuery
  def initialize(device:, relay_index:, from: nil, to: nil)
    @device = device
    @index = SwitchApi::Configuration.new(device).relay!(relay_index)
    today = Time.current.in_time_zone('Asia/Ho_Chi_Minh').to_date
    if from.nil? && to.nil?
      @from, @to = today - 6, today
    else
      @from, @to = strict_date(from), strict_date(to)
    end
    unless @from && @to && @from <= @to && @to <= today && (@to - @from).to_i < 31
      raise SwitchApi::Error.new('invalid_date_range')
    end
  end

  def call
    zone = ActiveSupport::TimeZone['Asia/Ho_Chi_Minh']
    scope = @device.relay_logs.where(relay_index: @index)
    # At most 31 indexed COUNT queries; no unbounded row materialization or
    # database-session timezone assumptions from DATE(created_at).
    days = (@from..@to).map do |date|
      start_at = zone.local(date.year, date.month, date.day)
      next_date = date + 1
      end_at = zone.local(next_date.year, next_date.month, next_date.day)
      { date: date.iso8601, count: scope.where(created_at: start_at...end_at).count }
    end
    { status: 'success', timezone: zone.name, from: @from.iso8601, to: @to.iso8601,
      metric: 'log_records', total_records: days.sum { |day| day[:count] }, days: days,
      physical_runtime_seconds: nil, physical_runtime_verified: false }
  end

  private

  def strict_date(value)
    return unless value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value)

    Date.iso8601(value)
  rescue Date::Error
    nil
  end
end
