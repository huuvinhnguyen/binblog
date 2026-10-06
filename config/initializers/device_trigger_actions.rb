Rails.application.config.x.device_trigger_actions_enabled = ActiveModel::Type::Boolean.new.cast(
  ENV.fetch('DEVICE_TRIGGER_ACTIONS_ENABLED', true)
)
