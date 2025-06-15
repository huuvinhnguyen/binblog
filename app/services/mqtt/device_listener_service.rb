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
        relay_index = data["relay_index"].to_i
        longlast = data["longlast"]
        sent_time = data["sent_time"]

        Rails.logger.info "[MQTT][Listener] Device #{chip_id}, Relay #{relay_index}, Duration #{longlast}, Sent at #{sent_time}"
        # TODO: xử lý logic
        device = Device.find_by(chip_id: chip_id)
        log = RelayLog.create(
              device_id: device.id,
              relay_index: relay_index,
              turn_on_at: nil,
              turn_off_at: nil,
              triggered_by: "MQTT",
              command_source: "mqtt",
              user_id: nil,
              note: "Set relay ON trong #{(longlast / 1_000)} giây qua Reminder"
            )

        unless log.persisted?
          Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
        end
      rescue JSON::ParserError => e
        Rails.logger.error "[MQTT][Listener] Invalid JSON: #{message}"
      end
    end
  end
end
