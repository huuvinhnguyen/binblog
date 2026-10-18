require 'rails_helper'

RSpec.describe 'Buzzer services during trigger action transition' do
  let(:user) { User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123') }
  let(:source) { owned('pir') }
  let(:buzzer) { owned('buzzer', device_info: { relays: [{}] }.to_json) }

  def owned(type, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), device_type: type }.merge(attributes)).tap { |device| device.users << user }
  end

  before do
    source.trigger_actions.create!(target_device: buzzer, action_type: 'relay_pulse', relay_index: 0,
                                   duration_ms: 1200, delay_ms: 0, enabled: true, position: 0)
  end

  it 'makes legacy Buzzer link and unlink writes return a conflict without modifying either store' do
    service = BuzzerLinks.new(buzzer: buzzer, user: user)
    original_trigger = source.trigger
    expect { service.link(pir_id: source.id, relay_index: 0, longlast: 1000) }
      .to raise_error(BuzzerLinks::ConflictError)
    expect { service.unlink(pir_id: source.id) }.to raise_error(BuzzerLinks::ConflictError)
    expect(source.reload.trigger).to eq(original_trigger)
    expect(source.trigger_actions.count).to eq(1)
  end

  it 'rechecks action mode under the source row lock before a legacy write' do
    source.trigger_actions.destroy_all
    original_trigger = source.trigger
    allow_any_instance_of(Device).to receive(:with_lock).and_wrap_original do |method, &block|
      source.trigger_actions.create!(target_device: buzzer, action_type: 'relay_pulse', relay_index: 0,
                                     duration_ms: 1000, delay_ms: 0, enabled: true, position: 0)
      method.call(&block)
    end

    expect do
      BuzzerLinks.new(buzzer: buzzer, user: user).link(pir_id: source.id, relay_index: 0, longlast: 1000)
    end.to raise_error(BuzzerLinks::ConflictError)
    expect(source.reload.trigger).to eq(original_trigger)
  end

  it 'reads linked PIRs through the canonical resolver and reads new execution history' do
    event = source.device_events.create!(event_type: 'motion_detected', occurred_at: Time.current, payload: {})
    event.trigger_action_executions.create!(
      device_trigger_action: source.trigger_actions.first,
      target_device: buzzer,
      action_key: "action:#{source.trigger_actions.first.id}",
      target_chip_id: buzzer.chip_id,
      action_type: 'relay_pulse', relay_index: 0, duration_ms: 1200, delay_ms: 0,
      configured_position: 0, command_payload: {}, status: 'publish_returned', scheduled_for: Time.current,
      publish_attempted_at: Time.current, publish_returned_at: Time.current
    )
    details = BuzzerDetails.new(device: buzzer, user: user)
    expect(details.linked_pirs).to eq([source])
    expect(details.trigger_for(source)).to include('longlast' => 1200, 'configuration_mode' => 'actions')
    expect(details.events).to eq([event])
    expect(details.event_payload(event)).to include('longlast' => 1200, 'execution_status' => 'publish_returned')
  end

  it 'exposes the canonical invalid_relay_index execution error in Buzzer history' do
    event = source.device_events.create!(event_type: 'motion_detected', occurred_at: Time.current, payload: {})
    event.trigger_action_executions.create!(
      device_trigger_action: source.trigger_actions.first,
      target_device: buzzer,
      action_key: "action:#{source.trigger_actions.first.id}",
      target_chip_id: buzzer.chip_id,
      action_type: 'relay_pulse', relay_index: 0, duration_ms: 1200, delay_ms: 0,
      configured_position: 0, command_payload: {}, status: 'skipped', scheduled_for: Time.current,
      failed_at: Time.current, error_code: 'invalid_relay_index'
    )

    payload = BuzzerDetails.new(device: buzzer, user: user).event_payload(event)
    expect(payload).to include('execution_status' => 'skipped', 'error_code' => 'invalid_relay_index')
  end
end
