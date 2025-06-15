# require 'sidekiq'
# require 'sidekiq-cron'

# Sidekiq.configure_server do |config|
#   config.redis = { url: 'redis://localhost:6379/0' }

#   schedule = {
#     'reminder_cron_worker' => {
#       'cron' => '*/3 * * * *', # every 6 minutes
#       'class' => 'ReminderCronWorker',
#       'queue' => 'default'
#     }
#   }

#   Sidekiq::Cron::Job.load_from_hash(schedule)
# end

# Sidekiq.configure_client do |config|
#   config.redis = { url: 'redis://localhost:6379/0' }
# end


require 'sidekiq/scheduler'

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq.schedule = YAML.load_file(Rails.root.join("config/sidekiq_scheduler.yml"))
    Sidekiq::Scheduler.reload_schedule!

    # Gọi trực tiếp không cần worker
    Thread.new do
      Rails.logger.info("[MQTT] Starting listener on boot")
      Mqtt::DeviceListenerService.start_blocking
    end
  end
end
