class ActivateRelayJob
  include Sidekiq::Worker

  def perform(reminder_id)
    puts "ActivateRelayJob perform"

    reminder = Reminder.find_by(id: reminder_id)
    return unless reminder

    device = reminder.device
    relay_index = reminder.relay_index
    return unless device&.device_info.present?

    device_info = JSON.parse(device.device_info)
    relays = device_info["relays"] || []
    return unless relay_index < relays.length

    relay = relays[relay_index]
    relay["switch_value"] = 1
    device_info["relays"][relay_index] = relay
    device_info["update_at"] = Time.now.to_i
    device.update(device_info: device_info.to_json)

    puts "Đã bật relay #{relay_index} cho thiết bị #{device.chip_id}"

    duration_ms = reminder.duration.to_i
    puts "duration_ms: #{duration_ms}"
    # TurnOffRelayJob.perform_in(duration_ms / 1000, reminder.device.chip_id, reminder.relay_index)

    if duration_ms == 0
      TurnOffRelayJob.perform_async(reminder.device.chip_id, reminder.relay_index)
    else
      # Nếu duration > 0, lên lịch tắt relay sau thời gian duration
      puts "Lên lịch tắt relay trong #{duration_ms / 1000} giây"

      TurnOffRelayJob.perform_in(reminder.duration / 1000, reminder.device.chip_id, reminder.relay_index)
    end
    

    unless reminder.repeat_type == "once"
      next_time = reminder.next_trigger_time
      if next_time.present? && next_time.future?
        jid = ActivateRelayJob.perform_at(next_time, reminder.id)
        reminder.update(job_jid: jid)
      end
    end
  end
end
