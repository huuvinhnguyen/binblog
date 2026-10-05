class DeviceTriggerFeature
  def self.enabled?
    Rails.application.config.x.device_trigger_actions_enabled == true
  end
end
