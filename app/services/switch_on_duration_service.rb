class SwitchOnDurationService
    def initialize(device_id, longlast: nil, relay_index: nil)
      @device_id = device_id
      @longlast = longlast
      @relay_index = relay_index
    end
  
    def call
      @device = Device.find_by(chip_id: @device_id)
      return unless @device
  
      device_info = JSON.parse(@device.device_info || '{}')

      relays = device_info["relays"] || []
      return unless @relay_index < relays.length
  
      relay = relays[@relay_index]
      relay["switch_value"] = 1
      relays[@relay_index] = relay  # ✅ Cập nhật relay đã chỉnh sửa
  
      device_info["relays"] = relays
      device_info["update_at"] = Time.zone.now.to_i

      subscribe_for_duration(
        chip_id: @device_id,
        relay_index: @relay_index,
        duration_ms: @longlast.to_i
      ) 
  
      if @device.update(device_info: device_info.to_json)
        @device.reload

        publish_duration(device_id: @device_id, longlast: @longlast, relay_index: @relay_index)

        trigger_time = Time.current
        log = create_log(@device.id, @relay_index, trigger_time, @longlast)
      
        duration_ms = @longlast.to_i
        if duration_ms == 0
          SwitchOffDurationJob.perform_async(@device.chip_id, @relay_index)
        else
          SwitchOffDurationJob.perform_in(duration_ms / 1000, @device.chip_id, @relay_index)
        end
      
        Rails.logger.info("Đã bật relay #{@relay_index} cho thiết bị #{@device.chip_id}, tắt sau #{duration_ms / 1000}s")
      else
        Rails.logger.error("❗Không thể cập nhật device_info cho thiết bị #{@device.chip_id}, không lên lịch TurnOffRelayJob")
      end
      
    end

    def publish_duration(device_id:, longlast:, relay_index:)
      topic = "#{device_id}/switchon"
    
      message_hash = {
        "relay_index" => relay_index,
        "longlast" => longlast,
        "sent_time" => Time.current.strftime('%Y-%m-%d %H:%M:%S')
      }.compact
    
      message_json = message_hash.to_json
      puts "#message json: #{message_json}"
    
      client = MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
    
      client.publish(topic, message_json, retain: false) if topic.present?
      client.disconnect
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

    def subscribe_for_duration(chip_id:, relay_index:, duration_ms:)
      topic = "#{chip_id}/switchon/relay"
      puts "#topic : #{topic}"

      # Thread 1: Trước khi bật relay (gần thời điểm publish)
      Thread.new do
        listen_mqtt_for(topic, duration: 10, note: "trước khi bật relay")
      end
    
      # Thread 2: Trước khi relay kết thúc 5s
      if duration_ms.to_i > 5_000
        time_before_end = (duration_ms.to_i - 5_000) / 1000.0
        Thread.new do
          sleep time_before_end
          listen_mqtt_for(topic, duration: 10, note: "trước khi tắt relay")
        end
      end
    end
    

    def listen_mqtt_for(topic, duration:, note:)
      client = MQTT::Client.connect(
        host: '103.9.77.155',
        port: 1883
      )
    
      Rails.logger.info "[MQTT][Thread][#{note}] Lắng nghe topic #{topic} trong #{duration}s"
      puts "#topic : #{topic}"

      begin
        Timeout.timeout(duration) do
          client.get(topic) do |_, message|
            # handle_message(message)
            puts "#topic: #{topic}"
            puts "#message: #{message}"
            Rails.logger.info "[MQTT][Thread][#{note}] Nhận được từ #{topic}: #{message}"
            # break
          end
        end
      rescue Timeout::Error
        Rails.logger.info "[MQTT][Thread][#{note}] Hết thời gian mà không có message"
      rescue => e
        Rails.logger.error "[MQTT][Thread][#{note}] Lỗi khi subscribe: #{e.message}"
      ensure
        client.disconnect if client.connected?
        Rails.logger.info "[MQTT][Thread][#{note}] MQTT client đã ngắt kết nối"
      end
    end

    def handle_message(message)
      begin
        data = JSON.parse(message)
        chip_id = data["device_id"]
        relay_index = data["relay_index"].to_i
        longlast = data["longlast"]
        sent_time = data["sent_time"]

        Rails.logger.info "[MQTT][Listener] Device #{chip_id}, Relay #{relay_index}, Duration #{longlast}, Sent at #{sent_time}"
        # TODO: xử lý logic
        log = RelayLog.create(
              device_id: @device.id,
              relay_index: relay_index,
              turn_on_at: nil,
              turn_off_at: nil,
              triggered_by: "MQTT",
              command_source: "active_relay",
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
  