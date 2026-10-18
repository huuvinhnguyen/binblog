class DeviceTriggerCommandPublisher
  PublishError = Class.new(StandardError)
  ConnectError = Class.new(PublishError)
  OPERATION_TIMEOUT_SECONDS = 5

  def initialize(execution:)
    @execution = execution
  end

  def call
    stage = :connect
    client = nil
    settings = Rails.application.config_for(:mqtt)
    host = settings[:host] || settings['host']
    port = settings[:port] || settings['port']
    raise KeyError, 'MQTT host or port is missing' unless host && port

    client = MQTT::Client.new(host: host, port: port)
    Timeout.timeout(OPERATION_TIMEOUT_SECONDS) do
      client.connect
      stage = :publish
      client.publish(topic, publish_payload.to_json, false)
    end
  rescue KeyError, Timeout::Error, MQTT::Exception, SocketError, SystemCallError, IOError => e
    error_class = stage == :connect ? ConnectError : PublishError
    raise error_class, e.message
  ensure
    disconnect_best_effort(client)
  end

  private

  def topic
    "#{@execution.target_chip_id}/switchon"
  end

  def disconnect_best_effort(client)
    client&.disconnect(false)
  rescue StandardError => e
    Rails.logger.warn("Device trigger MQTT cleanup failed: #{e.class}")
  end

  def publish_payload
    snapshot = @execution.command_payload.deep_stringify_keys
    if @execution.action_key == 'legacy'
      snapshot.merge('sent_time' => sent_time)
    else
      {
        'chip_id' => @execution.target_chip_id,
        'relay_index' => @execution.relay_index,
        'longlast' => @execution.duration_ms,
        'sent_time' => sent_time
      }
    end
  end

  def sent_time
    Time.current.strftime('%Y-%m-%d %H:%M:%S')
  end
end
