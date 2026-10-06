require 'rails_helper'

RSpec.describe DeviceTriggerActionExecution, type: :model do
  let(:device) { Device.create!(chip_id: SecureRandom.hex(8), device_type: 'pir') }
  let(:event) { device.device_events.create!(event_type: 'motion_detected', occurred_at: Time.current, payload: {}) }
  let(:execution) do
    described_class.create!(
      device_event: event,
      action_key: 'legacy',
      target_chip_id: 'target',
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 1000,
      delay_ms: 0,
      configured_position: 0,
      command_payload: { chip_id: 'target' },
      status: 'pending_publish',
      scheduled_for: Time.current
    )
  end

  it 'keeps snapshot fields immutable after creation' do
    execution.target_chip_id = 'changed'
    expect(execution).not_to be_valid
    expect(execution.errors[:base]).to include('execution snapshot is immutable')
  end

  it 'allows forward transitions and rejects backward or terminal transitions' do
    execution.status = 'publish_attempted'
    expect(execution.save).to eq(true)
    execution.status = 'publish_returned'
    expect(execution.save).to eq(true)
    execution.status = 'pending_publish'
    expect(execution).not_to be_valid
  end


  it 'keeps historical queue states readable and transitionable' do
    historical = execution.dup
    historical.action_key = 'historical'
    historical.status = 'pending_enqueue'
    historical.save!
    historical.status = 'queued'
    expect(historical.save).to eq(true)
    historical.status = 'publish_attempted'
    expect(historical.save).to eq(true)
  end

  it 'enforces a unique action key per event' do
    execution
    duplicate = described_class.new(execution.attributes.except('id', 'created_at', 'updated_at'))
    expect(duplicate).not_to be_valid
  end

  it 'keeps execution snapshots when the action or target is deleted and cascades with the request event' do
    user = User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
    source = Device.create!(chip_id: SecureRandom.hex(8), device_type: 'pir').tap { |record| record.users << user }
    target = Device.create!(chip_id: SecureRandom.hex(8), device_type: 'buzzer',
                            device_info: { relays: [{}] }.to_json).tap { |record| record.users << user }
    action = source.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                            duration_ms: 1000, delay_ms: 0, enabled: true, position: 0)
    request_event = source.device_events.create!(event_type: 'motion_detected', occurred_at: Time.current, payload: {})
    record = request_event.trigger_action_executions.create!(
      device_trigger_action: action, target_device: target, action_key: "action:#{action.id}",
      target_chip_id: target.chip_id, action_type: 'relay_pulse', relay_index: 0, duration_ms: 1000,
      delay_ms: 0, configured_position: 0, command_payload: {}, status: 'publish_returned',
      scheduled_for: Time.current, publish_attempted_at: Time.current, publish_returned_at: Time.current
    )

    target.destroy!
    expect(record.reload.device_trigger_action_id).to be_nil
    expect(record.target_device_id).to be_nil
    expect(record.target_chip_id).to be_present

    request_event.destroy!
    expect(described_class.where(id: record.id)).not_to exist
  end
end
