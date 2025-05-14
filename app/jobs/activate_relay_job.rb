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
  end
end
