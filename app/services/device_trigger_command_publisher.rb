class DeviceTriggerCommandPublisher
  PublishError = Class.new(StandardError)

  def initialize(execution:)
    @execution = execution
  end

  def call
    settings = Rails.application.config_for(:mqtt)
    host = settings[:host] || settings['host']
    port = settings[:port] || settings['port']
    raise KeyError, 'MQTT host or port is missing' unless host && port

    client = MQTT::Client.connect(host: host, port: port)
    yield if block_given?
    client.publish(topic, publish_payload.to_json, retain: false)
  rescue KeyError, MQTT::Exception, SocketError, SystemCallError => e
    raise PublishError, e.message
  ensure
    client&.disconnect
  end

  private

  def topic
    "#{@execution.target_chip_id}/switchon"
  end

  def publish_payload
    snapshot = @execution.command_payload.deep_stringify_keys
    if @execution.action_key == 'legacy'
      snapshot.merge('sent_time' => Time.current.to_i.to_s)
    else
      {
        'chip_id' => @execution.target_chip_id,
        'relay_index' => @execution.relay_index,
        'switch_value' => 1,
        'longlast' => @execution.duration_ms,
        'sent_time' => Time.current.to_i.to_s
      }
    end
  end
end
