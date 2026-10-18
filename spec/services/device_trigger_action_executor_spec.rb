require 'rails_helper'

RSpec.describe DeviceTriggerActionExecutor do
  let(:user) { User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123') }
  let(:source) { owned_device('pir') }
  let(:target) { owned_device('buzzer', device_info: { relays: [{}] }.to_json) }
  let(:action) do
    source.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                   duration_ms: 1000, delay_ms: 0, enabled: true, position: 0)
  end
  let(:event) { source.device_events.create!(event_type: 'motion_detected', occurred_at: Time.current, payload: {}) }
  let(:execution) { build_execution }

  def owned_device(type, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), device_type: type }.merge(attributes)).tap { |device| device.users << user }
  end

  def build_execution(status: 'pending_publish', action_key: nil, command_payload: nil, linked_action: action)
    event.trigger_action_executions.create!(
      device_trigger_action: linked_action,
      target_device: target,
      action_key: action_key || "action:#{action.id}",
      target_chip_id: target.chip_id,
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 1000,
      delay_ms: 0,
      configured_position: event.trigger_action_executions.count,
      command_payload: command_payload || { chip_id: target.chip_id, relay_index: 0, longlast: 1000 },
      status: status,
      queued_at: status == 'queued' ? Time.current : nil,
      scheduled_for: Time.current
    )
  end

  def mqtt_client
    @mqtt_client ||= instance_double(MQTT::Client, connect: nil, publish: nil, disconnect: nil)
  end

  before do
    allow(MQTT::Client).to receive(:new).and_return(mqtt_client)
  end

  it 'claims before network, publishes the duration-only Buzzer pulse payload, and records return' do
    expect(mqtt_client).to receive(:connect) do
      expect(execution.reload.status).to eq('publish_attempted')
    end

    travel_to(Time.zone.parse('2026-10-06 09:00:00')) { described_class.new(execution: execution).call }

    expect(mqtt_client).to have_received(:publish) do |topic, payload, retain|
      expect(topic).to eq("#{target.chip_id}/switchon")
      expect(JSON.parse(payload)).to eq(
        'chip_id' => target.chip_id,
        'relay_index' => 0,
        'longlast' => 1000,
        'sent_time' => '2026-10-06 09:00:00'
      )
      expect(retain).to be(false)
    end
    expect(execution.reload).to have_attributes(status: 'publish_returned', error_code: nil)
    expect(execution.publish_attempted_at).to be_present
    expect(execution.publish_returned_at).to be_present
  end

  it 'publishes an immutable legacy payload with only sent_time refreshed' do
    payload = { 'chip_id' => target.chip_id, 'relay_indexes' => [1, 3], 'longlast' => 700, 'custom_field' => 'keep' }
    legacy = build_execution(action_key: 'legacy', command_payload: payload, linked_action: nil)
    travel_to(Time.zone.parse('2026-10-06 09:30:00')) { described_class.new(execution: legacy).call }

    expect(mqtt_client).to have_received(:publish) do |_topic, published, retain|
      expect(JSON.parse(published)).to eq(payload.merge('sent_time' => '2026-10-06 09:30:00'))
      expect(retain).to be(false)
    end
    expect(legacy.reload.status).to eq('publish_returned')
    expect(legacy.command_payload).to eq(payload)
  end

  it 'skips a missing action before network work' do
    record = execution
    action.destroy!
    expect(MQTT::Client).not_to receive(:new)

    described_class.new(execution: record).call

    expect(record.reload).to have_attributes(status: 'skipped', error_code: 'action_missing')
  end

  it 'skips disabled, invalid-target, and unsupported-delay actions independently' do
    action.update!(enabled: false)
    described_class.new(execution: execution).call
    expect(execution.reload).to have_attributes(status: 'skipped', error_code: 'action_disabled')

    invalid_target = owned_device('switch', device_info: { relays: [{}] }.to_json)
    invalid_action = source.trigger_actions.create!(target_device: invalid_target, action_type: 'relay_pulse', relay_index: 0,
                                                    duration_ms: 1000, delay_ms: 0, enabled: true, position: 1)
    invalid = build_execution(action_key: "action:#{invalid_action.id}", linked_action: invalid_action)
    invalid_target.users.delete(user)
    described_class.new(execution: invalid).call
    expect(invalid.reload).to have_attributes(status: 'skipped', error_code: 'ownership_changed')

    delayed_target = owned_device('switch', device_info: { relays: [{}] }.to_json)
    delayed_action = source.trigger_actions.create!(target_device: delayed_target, action_type: 'relay_pulse', relay_index: 0,
                                                    duration_ms: 1000, delay_ms: 0, enabled: true, position: 2)
    delayed_action.update_columns(delay_ms: 250)
    delayed = build_execution(action_key: "action:#{delayed_action.id}", linked_action: delayed_action)
    described_class.new(execution: delayed).call
    expect(delayed.reload).to have_attributes(status: 'skipped', error_code: 'delay_not_supported')
  end

  it 'classifies known connection failure separately from uncertain post-claim failure' do
    allow(mqtt_client).to receive(:connect).and_raise(MQTT::Exception.new('offline'))
    described_class.new(execution: execution).call
    expect(execution.reload).to have_attributes(status: 'failed', error_code: 'mqtt_connect_failed')

    another = build_execution(action_key: 'legacy', linked_action: nil)
    allow(mqtt_client).to receive(:connect).and_return(nil)
    allow(mqtt_client).to receive(:publish).and_raise(MQTT::Exception.new('lost'))
    described_class.new(execution: another).call
    expect(another.reload).to have_attributes(status: 'failed', error_code: 'publish_outcome_unknown')
  end

  it 'classifies connect and publish timeouts without retrying' do
    allow(mqtt_client).to receive(:connect).and_raise(Timeout::Error)
    described_class.new(execution: execution).call
    expect(execution.reload).to have_attributes(status: 'failed', error_code: 'mqtt_connect_failed')

    another = build_execution(action_key: 'legacy', linked_action: nil)
    allow(mqtt_client).to receive(:connect).and_return(nil)
    allow(mqtt_client).to receive(:publish).and_raise(Timeout::Error)
    described_class.new(execution: another).call
    expect(another.reload).to have_attributes(status: 'failed', error_code: 'publish_outcome_unknown')
  end

  it 'uses an atomic claim so duplicate and terminal invocations do not publish twice' do
    first = nil
    allow(mqtt_client).to receive(:connect) do
      Fiber.yield(:claimed)
    end
    first = Fiber.new do
      described_class.new(execution: execution).call
      :finished
    end

    expect(first.resume).to eq(:claimed)
    described_class.new(execution_id: execution.id).call
    expect(first.resume).to eq(:finished)
    described_class.new(execution_id: execution.id).call

    expect(mqtt_client).to have_received(:publish).once
    expect(execution.reload.status).to eq('publish_returned')
  end

  it 'drains historical pending_enqueue and queued executions' do
    pending = build_execution(status: 'pending_enqueue', action_key: 'legacy-pending', linked_action: nil)
    queued = build_execution(status: 'queued', action_key: 'legacy-queued', linked_action: nil)

    described_class.new(execution_id: pending.id).call
    described_class.new(execution_id: queued.id).call

    expect([pending.reload.status, queued.reload.status]).to eq(%w[publish_returned publish_returned])
    expect(mqtt_client).to have_received(:publish).twice
  end
end
