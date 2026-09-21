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
    log_info "START user_id=#{@user&.id}"
    log_info "device chip_id=#{@device.chip_id.inspect} type=#{@device.device_type.inspect}"
    log_info "cache_store=#{@cache.class.name}"
    log_info "device_info=#{@device.device_info.inspect}"

    validate_buzzer!

    log_info(
      "configuration OK relay_index=#{relay_index} " \
      "longlast=#{longlast}ms topic=#{topic.inspect}"
    )

    reserve_cooldown!

    client = nil

    begin
      options = mqtt_options

      log_info(
        "MQTT connecting host=#{options[:host].inspect} " \
        "port=#{options[:port].inspect}"
      )

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      client = @mqtt_client.connect(**options)

      connect_duration = elapsed_ms(started_at)

      log_info "MQTT connected duration=#{connect_duration}ms"

      payload = message.to_json

      log_info(
        "MQTT publishing topic=#{topic.inspect} " \
        "retain=false payload=#{payload}"
      )

      publish_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      client.publish(
        topic,
        payload,
        retain: false
      )

      publish_duration = elapsed_ms(publish_started_at)

      log_info "MQTT publish SUCCESS duration=#{publish_duration}ms"

      event = record_requested_event!

      log_info(
        "device_event CREATED id=#{event.id} " \
        "event_type=#{event.event_type}"
      )

      result = Result.new(
        relay_index: relay_index,
        longlast: longlast
      )

      log_info(
        "SUCCESS relay_index=#{result.relay_index} " \
        "longlast=#{result.longlast}"
      )

      result

    rescue StandardError => e
      log_error(
        "FAILED error=#{e.class.name} " \
        "message=#{e.message.inspect}"
      )

      log_error "backtrace=#{e.backtrace&.first(10)&.join(' | ')}"

      release_cooldown!

      raise PublishError,
            "Không thể gửi lệnh test Buzzer: #{e.message}"

    ensure
      if client
        begin
          client.disconnect
          log_info "MQTT disconnected"
        rescue StandardError => e
          log_error(
            "MQTT disconnect failed " \
            "error=#{e.class.name} message=#{e.message.inspect}"
          )
        end
      end

      log_info "END"
    end

  rescue ConfigurationError, CooldownError => e
    log_warn(
      "SKIPPED error=#{e.class.name} " \
      "message=#{e.message.inspect}"
    )
    raise
  end

  private

  def validate_buzzer!
    log_info "validating buzzer"

    unless @device.device_type == 'buzzer'
      log_warn "invalid device_type=#{@device.device_type.inspect}"
      raise ConfigurationError, 'Thiết bị không phải Buzzer.'
    end

    log_info "parsed_device_info=#{parsed_device_info.inspect}"
    log_info "relay_config=#{relay_config.inspect}"

    unless relay_config.is_a?(Hash)
      raise ConfigurationError, 'Cấu hình Buzzer không hợp lệ.'
    end

    value = relay_config['longlast']

    log_info(
      "validating longlast raw=#{value.inspect} " \
      "converted=#{value.to_i}"
    )

    unless value.to_s.match?(/\A\d+\z/)
      raise ConfigurationError,
            'Thời lượng Buzzer phải là số nguyên.'
    end

    unless longlast.between?(MIN_DURATION_MS, MAX_DURATION_MS)
      raise ConfigurationError,
            "Thời lượng Buzzer phải từ " \
            "#{MIN_DURATION_MS} đến #{MAX_DURATION_MS} ms."
    end
  end

  def relay_config
    @relay_config ||= parsed_device_info.fetch('relays', []).first
  end

  def parsed_device_info
    return {} if @device.device_info.blank?

    value = JSON.parse(@device.device_info)

    value.is_a?(Hash) ? value : {}

  rescue JSON::ParserError, TypeError => e
    log_error(
      "device_info JSON parse failed " \
      "error=#{e.class.name} message=#{e.message.inspect}"
    )

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
    Rails.application
         .config_for(:mqtt)
         .symbolize_keys
         .slice(:host, :port)
  end

  def cooldown_key
    "buzzer-test:#{@device.id}"
  end

  def reserve_cooldown!
    log_info(
      "cooldown CHECK key=#{cooldown_key.inspect} " \
      "ttl=#{COOLDOWN_SECONDS}s"
    )

    existing = @cache.read(cooldown_key)

    log_info(
      "cooldown BEFORE existing=#{existing.inspect}"
    )

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    reserved = @cache.write(
      cooldown_key,
      true,
      expires_in: COOLDOWN_SECONDS,
      unless_exist: true
    )

    duration = elapsed_ms(started_at)

    log_info(
      "cooldown RESULT reserved=#{reserved.inspect} " \
      "duration=#{duration}ms"
    )

    unless reserved
      log_warn(
        "cooldown BLOCKED key=#{cooldown_key.inspect} " \
        "existing=#{@cache.read(cooldown_key).inspect}"
      )

      raise CooldownError,
            'Vui lòng chờ vài giây trước khi test lại.'
    end

    log_info "cooldown RESERVED"
  end

  def release_cooldown!
    result = @cache.delete(cooldown_key)

    log_info(
      "cooldown RELEASE key=#{cooldown_key.inspect} " \
      "result=#{result.inspect}"
    )
  end

  def record_requested_event!
    log_info "device_event creating"

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    event = @device.device_events.create!(
      event_type: 'buzzer_test_requested',
      occurred_at: Time.current,
      payload: {
        relay_index: relay_index,
        longlast: longlast,
        requested_by_user_id: @user.id
      }
    )

    log_info(
      "device_event DB duration=#{elapsed_ms(started_at)}ms"
    )

    event
  end

  def elapsed_ms(started_at)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    (elapsed * 1000).round(1)
  end

  def log_info(message)
    Rails.logger.info(
      "[BuzzerTest] device_id=#{@device.id} #{message}"
    )
  end

  def log_warn(message)
    Rails.logger.warn(
      "[BuzzerTest] device_id=#{@device.id} #{message}"
    )
  end

  def log_error(message)
    Rails.logger.error(
      "[BuzzerTest] device_id=#{@device.id} #{message}"
    )
  end
end