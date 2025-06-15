# app/services/mqtt/device_listener_service.rb
require 'mqtt'

module Mqtt
  class DeviceListenerService
    @started = false

    def self.start_blocking
      return if @started
      @started = true

      loop do
        begin
          Rails.logger.info "[MQTT][Listener] Connecting to broker..."

          client = ::MQTT::Client.connect(
            host: '103.9.77.155',
            port: 1883,
            keep_alive: 60
          )

          client.subscribe("device")
          Rails.logger.info "[MQTT][Listener] Subscribed to 'device' topic"

          client.get do |topic, message|
            Rails.logger.info "[MQTT][Listener] Received: #{topic} => #{message}"
            handle_message(message)
          end

        rescue MQTT::ProtocolException => e
          Rails.logger.error "[MQTT][Listener] Protocol error: #{e.message}"
          sleep 5
          retry

        rescue => e
          Rails.logger.error "[MQTT][Listener] Unexpected error: #{e.message}"
          sleep 5
          retry
        end
      end
    end

    def self.handle_message(message)
      begin
        data = JSON.parse(message)
        chip_id = data["device_id"]
        relay_index = data["relay_index"]
        longlast = data["longlast"]
        sent_time = data["sent_time"]

        Rails.logger.info "[MQTT][Listener] Device #{chip_id}, Relay #{relay_index}, Duration #{longlast}, Sent at #{sent_time}"
        # TODO: xử lý logic
      rescue JSON::ParserError => e
        Rails.logger.error "[MQTT][Listener] Invalid JSON: #{message}"
      end
    end
  end
end
