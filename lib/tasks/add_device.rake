namespace :device do
  desc "Create a new single-relay device"
  task :create => :environment do
    puts "Enter chip_id (e.g., esp8266_12345678):"
    chip_id = STDIN.gets&.chomp.to_s

    if chip_id.empty?
      puts "chip_id cannot be blank!"
      next
    end

    if Device.exists?(chip_id: chip_id)
      puts "Device with chip_id '#{chip_id}' already exists!"
      next
    end

    puts "Enter device name:"
    name = STDIN.gets&.chomp.to_s

    if name.empty?
      puts "Device name cannot be blank!"
      next
    end

    puts "Enter note [optional]:"
    note = STDIN.gets&.chomp.to_s
    note = nil if note.empty?

    puts "Enter longlast in milliseconds (default: 6000):"
    longlast_input = STDIN.gets&.chomp.to_s
    longlast_input = "6000" if longlast_input.empty?

    unless longlast_input.match?(/\A\d+\z/)
      puts "longlast must be a non-negative integer!"
      next
    end

    longlast = longlast_input.to_i

    puts "Do you want to link this device to a user? (y/n):"
    link_user = STDIN.gets&.chomp.to_s.downcase
    user = nil

    if link_user == 'y'
      puts "Enter user email:"
      email = STDIN.gets&.chomp.to_s
      user = User.find_by(email: email)

      unless user
        puts "User with email '#{email}' not found! Device was not created."
        next
      end
    end

    device_info = {
      device_type: "switch",
      topic_type: "switchon",
      device_id: chip_id,
      switch_value: nil,
      update_at: Time.current.to_i,
      longlast: nil,
      timetrigger: nil,
      relays: [
        {
          switch_value: 0,
          longlast: longlast,
          is_reminders_active: true,
          reminders: []
        }
      ],
      local_ip: "",
      build_version: 0,
      app_version: "1.0.0"
    }

    trigger = {
      relay_indexes: [0],
      chip_id: chip_id,
      longlast: longlast
    }

    device = nil
    ActiveRecord::Base.transaction do
      device = Device.create!(
        chip_id: chip_id,
        name: name,
        device_type: "switch",
        note: note,
        status: 1,
        is_payment: false,
        device_info: device_info.to_json,
        trigger: trigger.to_json,
        meta_info: {}.to_json
      )
      device.users << user if user
    end

    puts "✓ Single-relay device '#{name}' (#{chip_id}) was successfully created."
    puts "  Device ID: #{device.id}"
    puts "  Relay index: 0"
    puts "  Longlast: #{longlast} ms"
    puts "  User: #{user.email}" if user
  rescue ActiveRecord::RecordInvalid => e
    puts "Failed to create device:"
    puts e.record.errors.full_messages.join("\n")
  end

  desc "List all devices"
  task :list => :environment do
    devices = Device.all

    if devices.empty?
      puts "No devices found."
    else
      puts "\n#{devices.count} device(s) found:\n"
      puts "-" * 80
      devices.each do |device|
        puts "ID: #{device.id}"
        puts "Name: #{device.name}"
        puts "Chip ID: #{device.chip_id}"
        puts "Type: #{device.device_type || 'N/A'}"
        puts "Status: #{device.status}"
        puts "Users: #{device.users.pluck(:email).join(', ')}" if device.users.any?
        puts "Created: #{device.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
        puts "-" * 80
      end
    end
  end

  desc "Link a device to a user"
  task :link => :environment do
    puts "Enter chip_id:"
    chip_id = STDIN.gets.chomp

    device = Device.find_by(chip_id: chip_id)
    unless device
      puts "Device with chip_id '#{chip_id}' not found!"
      exit
    end

    puts "Enter user email:"
    email = STDIN.gets.chomp

    user = User.find_by(email: email)
    unless user
      puts "User with email '#{email}' not found!"
      exit
    end

    if device.users.include?(user)
      puts "Device is already linked to user #{user.email}"
    else
      device.users << user
      puts "✓ Device '#{device.name}' linked to user #{user.email}"
    end
  end

  desc "Delete a device and all related data"
  task :delete => :environment do
    puts "Enter chip_id of the device to delete:"
    chip_id = STDIN.gets&.chomp.to_s

    device = Device.find_by(chip_id: chip_id)
    unless device
      puts "Device with chip_id '#{chip_id}' not found!"
      next
    end

    connection = ActiveRecord::Base.connection
    quoted_device_id = connection.quote(device.id)
    legacy_user_devices = if connection.table_exists?(:user_devices)
      connection.select_value(
        "SELECT COUNT(*) FROM user_devices WHERE device_id = #{quoted_device_id}"
      ).to_i
    else
      0
    end

    puts "\nDevice to delete:"
    puts "  ID: #{device.id}"
    puts "  Name: #{device.name}"
    puts "  Chip ID: #{device.chip_id}"
    puts "  Type: #{device.device_type || 'N/A'}"
    puts "  Users: #{device.users.pluck(:email).join(', ')}"
    puts "\nRelated data:"
    puts "  Reminders: #{device.reminders.count}"
    puts "  Relay logs: #{device.relay_logs.count}"
    puts "  Device events: #{device.device_events.count}"
    puts "  User relay features: #{UserRelayFeature.where(device_id: device.id).count}"
    puts "  User links: #{device.users.count}"
    puts "  Legacy user_devices links: #{legacy_user_devices}"

    confirmation = "DELETE #{device.chip_id}"
    puts "\nThis action cannot be undone."
    puts "Type '#{confirmation}' to confirm:"

    unless STDIN.gets&.chomp == confirmation
      puts "Deletion cancelled."
      next
    end

    timestamp = Time.current.strftime('%Y%m%d%H%M%S')
    backup_path = Rails.root.join('tmp', "device-#{device.id}-#{timestamp}-backup.json")
    legacy_links = if connection.table_exists?(:user_devices)
      connection.select_all(
        "SELECT * FROM user_devices WHERE device_id = #{quoted_device_id}"
      ).to_a
    else
      []
    end

    backup = {
      device: device.attributes,
      user_ids: device.user_ids,
      reminders: device.reminders.map(&:attributes),
      relay_logs: device.relay_logs.map(&:attributes),
      device_events: device.device_events.map(&:attributes),
      user_relay_features: UserRelayFeature.where(device_id: device.id).map(&:attributes),
      legacy_user_devices: legacy_links
    }
    File.write(backup_path, JSON.pretty_generate(backup))

    deleted_device_id = device.id

    ActiveRecord::Base.transaction do
      # Use destroy_all so Reminder#before_destroy cancels scheduled Sidekiq jobs.
      device.reminders.destroy_all
      RelayLog.where(device_id: deleted_device_id).delete_all
      UserRelayFeature.where(device_id: deleted_device_id).delete_all
      device.users.clear

      if connection.table_exists?(:user_devices)
        connection.delete(
          "DELETE FROM user_devices WHERE device_id = #{quoted_device_id}"
        )
      end

      device.destroy!
    end

    puts "✓ Device '#{chip_id}' was successfully deleted."
    puts "  Backup: #{backup_path}"
  rescue StandardError => e
    puts "Failed to delete device: #{e.message}"
    raise
  end

  desc "Configure trigger for a device"
  task :trigger => :environment do
    puts "Enter chip_id:"
    chip_id = STDIN.gets.chomp

    device = Device.find_by(chip_id: chip_id)
    unless device
      puts "Device with chip_id '#{chip_id}' not found!"
      exit
    end

    puts "Current trigger: #{device.trigger || 'Not configured'}"
    puts "\nEnter new trigger configuration:"

    puts "Enter relay_index (default: 0):"
    relay_index = STDIN.gets.chomp
    relay_index = relay_index.empty? ? 0 : relay_index.to_i

    puts "Enter switch_value (0=off, 1=on, default: 1):"
    switch_value = STDIN.gets.chomp
    switch_value = switch_value.empty? ? 1 : switch_value.to_i

    puts "Enter longlast in milliseconds (optional, press Enter to skip):"
    longlast = STDIN.gets.chomp

    trigger_config = {
      chip_id: chip_id,
      relay_index: relay_index,
      switch_value: switch_value
    }
    trigger_config[:longlast] = longlast.to_i unless longlast.empty?

    device.update(trigger: trigger_config.to_json)
    puts "✓ Trigger configured successfully for device '#{device.name}'"
    puts "New trigger: #{device.trigger}"
  end
end
