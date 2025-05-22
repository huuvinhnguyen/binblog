# app/services/switch_on_service.rb
class SwitchOnService
    def initialize(device_id, switch_value: nil, longlast: nil, relay_index: nil)
      @device_id = device_id
      @switch_value = switch_value
      @longlast = longlast
      @relay_index = relay_index
    end
  
    def call
      device = Device.find_by(chip_id: @device_id)
      return false unless device
  
      device_info = device.device_info.present? ? JSON.parse(device.device_info) : {}
      relays = device_info["relays"] || []
  
      if @relay_index && @relay_index < relays.length
        relay = relays[@relay_index]
        relay["switch_value"] = @switch_value unless @switch_value.nil?
        relay["longlast"] = @longlast unless @longlast.nil?
      else
        # Nếu không có relay_index cụ thể, update cho toàn bộ relay
        relays.each do |relay|
          relay["switch_value"] = @switch_value unless @switch_value.nil?
          relay["longlast"] = @longlast unless @longlast.nil?
        end
      end
  
      device_info["relays"] = relays
      device.device_info = device_info.to_json
      device.save
      # puts "relay info: " + device_info["relays"].to_s

    end
  end
  