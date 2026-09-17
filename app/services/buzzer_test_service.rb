class BuzzerTestService
  MIN_DURATION_MS = 100
  MAX_DURATION_MS = 10_000
  COOLDOWN_SECONDS = 3

  ConfigurationError = Class.new(StandardError)
  CooldownError = Class.new(StandardError)
  PublishError = Class.new(StandardError)

  Result = Struct.new(:relay_index, :longlast, keyword_init: true)

  def initialize(device:, user:, mqtt_client: MQTT::Client, cache: Rails.cache)
    @device = device
    @user = user
    @mqtt_client = mqtt_client
    @cache = cache
  end

  def call
    validate_buzzer!
    reserve_cooldown!

    client = nil
    begin
      client = @mqtt_client.connect(**mqtt_options)
      client.publish(topic, message.to_json, retain: false)
      record_requested_event!

      Result.new(relay_index: relay_index, longlast: longlast)
    rescue StandardError => e
      release_cooldown!
      Rails.logger.error("[BuzzerTest] device_id=#{@device.id} publish failed: #{e.class}: #{e.message}")
      raise PublishError, "Không thể gửi lệnh test Buzzer: #{e.message}"
    ensure
      client.disconnect if client
    end
  end

  private

  def validate_buzzer!
    raise ConfigurationError, 'Thiết bị không phải Buzzer.' unless @device.device_type == 'buzzer'
    raise ConfigurationError, 'Cấu hình Buzzer không hợp lệ.' unless relay_config.is_a?(Hash)

    value = relay_config['longlast']
    raise ConfigurationError, 'Thời lượng Buzzer phải là số nguyên.' unless value.to_s.match?(/\A\d+\z/)
    raise ConfigurationError, "Thời lượng Buzzer phải từ #{MIN_DURATION_MS} đến #{MAX_DURATION_MS} ms." unless longlast.between?(MIN_DURATION_MS, MAX_DURATION_MS)
  end

  def relay_config
    @relay_config ||= parsed_device_info.fetch('relays', []).first
  end

  def parsed_device_info
    return {} if @device.device_info.blank?

    value = JSON.parse(@device.device_info)
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError, TypeError
    {}
  end

  def relay_index
    0
  end

  def longlast
    relay_config['longlast'].to_i
  end

  def topic
    "#{@device.chip_id}/switchon"
  end

  def message
    {
      chip_id: @device.chip_id,
      relay_index: relay_index,
      longlast: longlast,
      sent_time: Time.current.strftime('%Y-%m-%d %H:%M:%S')
    }
  end

  def mqtt_options
    Rails.application.config_for(:mqtt).symbolize_keys.slice(:host, :port)
  end

  def cooldown_key
    "buzzer-test:#{@device.id}"
  end

  def reserve_cooldown!
    reserved = @cache.write(
      cooldown_key,
      true,
      expires_in: COOLDOWN_SECONDS,
      unless_exist: true
    )
    raise CooldownError, 'Vui lòng chờ vài giây trước khi test lại.' unless reserved
  end

  def release_cooldown!
    @cache.delete(cooldown_key)
  end

  def record_requested_event!
    @device.device_events.create!(
      event_type: 'buzzer_test_requested',
      occurred_at: Time.current,
      payload: {
        relay_index: relay_index,
        longlast: longlast,
        requested_by_user_id: @user.id
      }
    )
  end
end
