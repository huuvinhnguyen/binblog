class TurnOffRelayJob
    include Sidekiq::Worker
  
    def perform(device_id, relay_index)
      device = Device.find_by(chip_id: device_id)
      return unless device&.device_info.present?
  
      device_info = JSON.parse(device.device_info)
      relays = device_info["relays"] || []
      return unless relay_index < relays.length
  
      relay = relays[relay_index]
      relay["switch_value"] = 0
      device_info["update_at"] = Time.zone.now.to_i
      device_info["relays"][relay_index] = relay
  
      device.update(device_info: device_info.to_json)
  
      puts "TurnOffRelayJob: Đã tắt relay #{relay_index} của thiết bị #{device_id}"
      refresh device_id
    end

    private
    def mqtt_client
      MQTT::Client.connect(
        host: MQTT_CONFIG["host"],
        port: MQTT_CONFIG["port"]
      )
    end

    def refresh chip_id
      topic = "#{chip_id}/refresh"
  
      client = mqtt_client
      message = {
          "action": "refresh",
          "sent_time": Time.current.strftime('%Y-%m-%d %H:%M:%S')
       }.to_json
  
      client.publish(topic, message) if topic.present?
      client.disconnect()
  
    end
end