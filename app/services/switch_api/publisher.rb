require 'timeout'

module SwitchApi
  class Publisher
    Unavailable = Class.new(StandardError)
    OutcomeUnknown = Class.new(StandardError)
    TIMEOUT_SECONDS = 5

    def call(topic:, payload:)
      client = nil
      attempted = false
      begin
        settings = Rails.application.config_for(:mqtt)
        host, port = settings[:host], settings[:port]
        raise Unavailable unless host.is_a?(String) && host.present? && port.to_s.match?(/\A\d+\z/)

        Timeout.timeout(TIMEOUT_SECONDS) do
          client = MQTT::Client.new(host: host, port: port.to_i)
          client.connect
          attempted = true
          client.publish(topic, payload.to_json, false, 0)
        end
      rescue MQTT::Exception, StandardError => e
        Rails.logger.warn("Switch MQTT operation failed: #{e.class}")
        raise(attempted ? OutcomeUnknown : Unavailable)
      ensure
        if client
          begin
            Timeout.timeout(TIMEOUT_SECONDS) { client.disconnect(false) }
          rescue MQTT::Exception, StandardError => e
            Rails.logger.warn("Switch MQTT cleanup failed: #{e.class}")
            raise OutcomeUnknown if attempted
          end
        end
      end
    end
  end
end
