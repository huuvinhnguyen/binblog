require 'sidekiq'
require 'sidekiq-cron'

Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6379/0' }

  schedule = {
    'reminder_cron_worker' => {
      'cron' => '*/3 * * * *', # every 6 minutes
      'class' => 'ReminderCronWorker',
      'queue' => 'default'
    }
  }

  Sidekiq::Cron::Job.load_from_hash(schedule)
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/0' }
end
