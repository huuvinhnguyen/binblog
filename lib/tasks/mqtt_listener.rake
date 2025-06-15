
  # lib/tasks/mqtt_listener.rake
namespace :mqtt do
    namespace :device_listener do
      desc "Start MQTT relay listener daemon"
      task start: :environment do
        puts "[MQTT] Starting DeiviceListenerService..."
        Mqtt::DeviceListenerService.start
        # Giữ cho process không bị thoát
        loop do
          sleep 5
        end
      end
    end
  end
  