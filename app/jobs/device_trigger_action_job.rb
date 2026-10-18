class DeviceTriggerActionJob
  include Sidekiq::Worker

  sidekiq_options retry: false

  def perform(execution_id)
    DeviceTriggerActionExecutor.new(execution_id: execution_id).call
  end
end
