class SwitchOnDurationService
    def initialize(device_id, longlast: nil, relay_index: nil)
      @device_id = device_id
      @longlast = longlast
      @relay_index = relay_index
    end
  
    def call
      device = Device.find_by(chip_id: @device_id)
      return unless device
  
      device_info = JSON.parse(device.device_info)
      relays = device_info["relays"] || []
      return unless @relay_index < relays.length
  
      relay = relays[@relay_index]
      relay["switch_value"] = 1
      relays[@relay_index] = relay  # ✅ Cập nhật relay đã chỉnh sửa
  
      device_info["relays"] = relays
      device_info["update_at"] = Time.now.to_i
  
      device.update(device_info: device_info.to_json)
      trigger_time = Time.current
      log = create_log(device.id, @relay_index, trigger_time, @longlast)
  
      puts "Đã bật relay #{@relay_index} cho thiết bị #{device.chip_id}"
  
      duration_ms = @longlast.to_i
      puts "duration_ms: #{duration_ms}"
  
      if duration_ms == 0
        TurnOffRelayJob.perform_async(device.chip_id, @relay_index)
      else
        puts "Lên lịch tắt relay trong #{duration_ms / 1000} giây"
        TurnOffRelayJob.perform_in(duration_ms / 1000, device.chip_id, @relay_index)
      end
    end

    def create_log(device_id, relay_index, trigger_time, duration)
      log = RelayLog.create(
                device_id: device_id,
                relay_index: relay_index,
                turn_on_at: trigger_time,
                turn_off_at: nil,
                triggered_by: "SwitchOnDurationService",
                command_source: "switch on",
                user_id: nil,
                note: "Set relay ON trong #{(duration / 1_000)} giây qua Reminder"
              )
  
      unless log.persisted?
        Rails.logger.error("RelayLog creation failed: #{log.errors.full_messages.join(', ')}")
      end
      log
    end
  end
  