class SwitchOnService
    def initialize(device_id, relay_index: nil, switch_value:)
      @device_id = device_id
      @relay_index = relay_index
      @switch_value = switch_value
    end
  
    def call
      device = Device.find_by(chip_id: @device_id)
  
      raise "Device not found" unless device
  
      device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      relays = device_info["relays"] || []
  
      if @relay_index.present?
        # Update chỉ 1 relay cụ thể
        raise "Invalid relay index" if @relay_index >= relays.size
  
        relays[@relay_index]["switch_value"] = @switch_value
      else
        # Update tất cả các relay
        relays.each do |relay|
          relay["switch_value"] = @switch_value
        end
      end
  
      device_info["relays"] = relays
      device.device_info = device_info.to_json
      device.save!
  
      # Gửi MQTT message để switch on/off
    #   publish_switch_message
  
      true
    rescue => e
      Rails.logger.error("[SwitchOnService] Error: #{e.message}")
      false
    end
  
    private
  
    def publish_switch_message
      topic = "#{@device_id}/switchon"
  
      message = {
        device_id: @device_id,
        action: 'switchon',
        relays: []
      }
  
      # Nếu chỉ update 1 relay
      if @relay_index.present?
        message[:relays] << {
          index: @relay_index,
          switch_value: @switch_value
        }
      else
        # Nếu update tất cả relays
        device = Device.find_by(chip_id: @device_id)
        device_info = JSON.parse(device.device_info)
  
        device_info["relays"].each_with_index do |relay, index|
          message[:relays] << {
            index: index,
            switch_value: relay["switch_value"]
          }
        end
      end
  
      client = MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
  
      client.publish(topic, message.to_json, retain: false)
      client.disconnect
    end
  end
  