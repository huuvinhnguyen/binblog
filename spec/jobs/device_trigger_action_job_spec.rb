require 'rails_helper'

RSpec.describe DeviceTriggerActionJob, type: :job do
  it 'delegates historical executions to the shared executor' do
    executor = instance_double(DeviceTriggerActionExecutor, call: nil)
    expect(DeviceTriggerActionExecutor).to receive(:new).with(execution_id: 42).and_return(executor)

    described_class.new.perform(42)

    expect(executor).to have_received(:call)
  end

  it 'keeps retries disabled because a publish outcome may be unknown' do
    expect(described_class.get_sidekiq_options['retry']).to eq(false)
  end
end
