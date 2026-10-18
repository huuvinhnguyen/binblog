require 'rails_helper'

RSpec.describe DeviceTriggerConfigurationResolver do
  let(:user) { User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123') }

  def device(type, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), device_type: type }.merge(attributes)).tap { |record| record.users << user }
  end

  it 'classifies blank and empty-object trigger values as none' do
    [nil, '', '   ', '{}'].each do |trigger|
      source = device('pir', trigger: trigger)

      expect(described_class.new(source_device: source).mode).to eq('none'), "expected #{trigger.inspect} to resolve as none"
    end
  end

  it 'keeps malformed and incomplete non-empty trigger values invalid' do
    expect(described_class.new(source_device: device('pir', trigger: '{bad')).mode).to eq('invalid_legacy')
    expect(described_class.new(source_device: device('pir', trigger: { relay_index: 0 }.to_json)).mode)
      .to eq('invalid_legacy')
  end

  it 'classifies a valid legacy payload as legacy' do
    legacy = device('pir', trigger: { chip_id: 'target', relay_index: 0, longlast: 1000 }.to_json)

    expect(described_class.new(source_device: legacy).mode).to eq('legacy')
  end

  it 'uses action mode whenever any persisted action exists, including all-disabled rows' do
    source = device('pir', trigger: { chip_id: 'legacy' }.to_json)
    target = device('buzzer', device_info: { relays: [{}] }.to_json)
    source.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                   duration_ms: 1000, delay_ms: 0, enabled: false, position: 0)
    resolver = described_class.new(source_device: source)
    expect(resolver.mode).to eq('actions')
    expect(resolver.runtime_actions).to be_empty
  end

  it 'keeps non-PIR devices on legacy semantics' do
    source = device('switch', trigger: { chip_id: 'target' }.to_json)
    expect(described_class.new(source_device: source).mode).to eq('legacy')
  end

  it 'resolves reverse action and legacy relationships without mixing precedence' do
    target = device('buzzer', device_info: { relays: [{}] }.to_json)
    action_source = device('pir', trigger: { chip_id: target.chip_id }.to_json)
    action_source.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                          duration_ms: 500, delay_ms: 0, enabled: true, position: 0)
    legacy_source = device('pir', trigger: { chip_id: target.chip_id, relay_index: 0, longlast: 1000 }.to_json)
    relationships = described_class.relationships_for_target(target_device: target, source_scope: user.devices)
    expect(relationships.map(&:origin)).to contain_exactly('actions', 'legacy')
    expect(relationships.find { |item| item.source_device == action_source }.duration_ms).to eq(500)
    expect(relationships.find { |item| item.source_device == legacy_source }.duration_ms).to eq(1000)
  end
end
