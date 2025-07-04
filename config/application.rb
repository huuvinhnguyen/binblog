require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RubyGettingStarted
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Set the default time zone to Vietnam
    config.time_zone = 'Asia/Ho_Chi_Minh'
    
    # Ensure Active Record stores times in the database in UTC, but uses local time elsewhere
    config.active_record.default_timezone = :local
    config.i18n.available_locales = [:en, :vi]
    config.eager_load_paths << Rails.root.join('app/services')
    config.assets.enabled = true



    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
