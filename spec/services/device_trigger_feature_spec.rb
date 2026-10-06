require 'rails_helper'

RSpec.describe DeviceTriggerFeature do
  INITIALIZER_PATH = Rails.root.join('config/initializers/device_trigger_actions.rb')

  around do |example|
    original_env_present = ENV.key?('DEVICE_TRIGGER_ACTIONS_ENABLED')
    original_env_value = ENV['DEVICE_TRIGGER_ACTIONS_ENABLED']
    original_config = Rails.application.config.x.device_trigger_actions_enabled

    example.run
  ensure
    if original_env_present
      ENV['DEVICE_TRIGGER_ACTIONS_ENABLED'] = original_env_value
    else
      ENV.delete('DEVICE_TRIGGER_ACTIONS_ENABLED')
    end
    Rails.application.config.x.device_trigger_actions_enabled = original_config
  end

  def load_configuration(value: nil, absent: false)
    if absent
      ENV.delete('DEVICE_TRIGGER_ACTIONS_ENABLED')
    else
      ENV['DEVICE_TRIGGER_ACTIONS_ENABLED'] = value
    end

    load INITIALIZER_PATH
  end

  it 'is enabled when the environment variable is absent' do
    load_configuration(absent: true)

    expect(described_class.enabled?).to be(true)
  end

  it 'is enabled in production when the environment variable is absent' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

    load_configuration(absent: true)

    expect(described_class.enabled?).to be(true)
  end

  it 'is enabled when the environment variable is true' do
    load_configuration(value: 'true')

    expect(described_class.enabled?).to be(true)
  end

  it 'is disabled when the environment variable is false' do
    load_configuration(value: 'false')

    expect(described_class.enabled?).to be(false)
  end

  it 'is disabled when the environment variable is zero' do
    load_configuration(value: '0')

    expect(described_class.enabled?).to be(false)
  end
end
