require 'rails_helper'

RSpec.describe DeviceTriggerAction, type: :model do
  let(:user) { User.create!(username: "owner_#{SecureRandom.hex(4)}", email: "#{SecureRandom.hex(4)}@example.com", password: 'password123') }
  let(:source) { owned_device('pir', device_info: '{}') }
  let(:buzzer) { owned_device('buzzer', device_info: { relays: [{ longlast: 1000 }] }.to_json) }
  let(:switch) { owned_device('switch', device_info: { relays: [{}, {}] }.to_json) }

  def owned_device(type, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), name: type, device_type: type }.merge(attributes)).tap do |device|
      device.users << user
    end
  end

  def action(target: buzzer, **attributes)
    described_class.new({
      source_device: source,
      target_device: target,
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 1000,
      delay_ms: 0,
      enabled: true,
      position: 0
    }.merge(attributes))
  end

  it 'accepts valid Buzzer and switch duration boundaries' do
    expect(action(duration_ms: 100)).to be_valid
    expect(action(duration_ms: 10_000)).to be_valid
    expect(action(target: switch, relay_index: 1, duration_ms: 86_400_000)).to be_valid
  end

  it 'rejects unsupported source, target, self-target, missing relay, and unsupported action type' do
    expect(action(source_device: switch)).not_to be_valid
    unsupported = owned_device('pir', device_info: { relays: [{}] }.to_json)
    expect(action(target: unsupported)).not_to be_valid
    expect(action(target: source)).not_to be_valid
    expect(action(relay_index: 1)).not_to be_valid
    expect(action(action_type: 'toggle')).not_to be_valid
  end

  it 'enforces target-specific duration, zero-delay synchronous execution, and position bounds' do
    expect(action(duration_ms: 99)).not_to be_valid
    expect(action(duration_ms: 10_001)).not_to be_valid
    expect(action(target: switch, duration_ms: 86_400_001)).not_to be_valid
    expect(action(delay_ms: -1)).not_to be_valid
    expect(action(delay_ms: 1)).not_to be_valid
    expect(action(delay_ms: 300_001)).not_to be_valid
    expect(action(position: -1)).not_to be_valid
  end

  it 'keeps grandfathered nonzero delay rows manageable but marks them unsupported at runtime' do
    record = action
    record.save!
    record.update_columns(delay_ms: 250)

    record.enabled = false
    expect(record.save).to eq(true)
    expect(record.reload.runtime_error_code).to eq('delay_not_supported')

    record.delay_ms = 0
    record.enabled = true
    expect(record.save).to eq(true)
    expect(record.runtime_error_code).to be_nil
  end

  it 'uses explicit relay_indexes when the target does not expose a relays array' do
    explicit = owned_device('switch', device_info: { relay_indexes: [2, 4] }.to_json)
    expect(action(target: explicit, relay_index: 2)).to be_valid
    expect(action(target: explicit, relay_index: 0)).not_to be_valid
  end

  it 'requires source and target to share an owner' do
    foreign = Device.create!(chip_id: SecureRandom.hex(8), device_type: 'buzzer', device_info: { relays: [{}] }.to_json)
    record = action(target: foreign)
    expect(record).not_to be_valid
    expect(record.errors[:target_device]).to be_present
  end

  it 'enforces one action per source target and type at both model and database levels' do
    action.save!
    duplicate = action(position: 1)
    expect(duplicate).not_to be_valid
    expect do
      described_class.insert_all!([duplicate.attributes.except('id', 'created_at', 'updated_at').merge(
        'created_at' => Time.current, 'updated_at' => Time.current
      )])
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'counts enabled and disabled rows toward the maximum of 20 actions' do
    20.times do |index|
      target = owned_device('switch', device_info: { relays: [{}] }.to_json)
      action(target: target, enabled: index.even?, position: index).save!
    end
    extra = action(target: owned_device('buzzer', device_info: { relays: [{}] }.to_json), position: 20)
    expect(extra).not_to be_valid
    expect(extra.errors[:base]).to include('maximum number of trigger actions reached')
  end
end
