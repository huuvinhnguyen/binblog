require 'rails_helper'

RSpec.describe DeviceTriggerActionJob, type: :job do
  let(:user) { User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123') }
  let(:source) { owned_device('pir') }
  let(:target) { owned_device('buzzer', device_info: { relays: [{}] }.to_json) }
  let(:action) do
    source.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                   duration_ms: 1000, delay_ms: 0, enabled: true, position: 0)
  end
  let(:event) { source.device_events.create!(event_type: 'motion_detected', occurred_at: Time.current, payload: {}) }
  let(:execution) do
    event.trigger_action_executions.create!(
      device_trigger_action: action,
      target_device: target,
      action_key: "action:#{action.id}",
      target_chip_id: target.chip_id,
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 1000,
      delay_ms: 0,
      configured_position: 0,
      command_payload: { chip_id: target.chip_id, relay_index: 0, switch_value: 1, longlast: 1000 },
      status: 'queued',
      queued_at: Time.current,
      scheduled_for: Time.current
    )
  end

  def owned_device(type, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), device_type: type }.merge(attributes)).tap { |device| device.users << user }
  end

  def mqtt_client
    @mqtt_client ||= instance_double(MQTT::Client, publish: nil, disconnect: nil)
  end

  def legacy_execution(payload)
    event.trigger_action_executions.create!(
      target_device: target,
      action_key: 'legacy',
      target_chip_id: payload.fetch('chip_id'),
      action_type: 'relay_pulse',
      relay_index: payload['relay_index'],
      duration_ms: payload['longlast'],
      delay_ms: 0,
      configured_position: 0,
      command_payload: payload,
      status: 'queued',
      queued_at: Time.current,
      scheduled_for: Time.current
    )
  end

  it 'publishes the exact relay pulse payload and records publish_returned after publish returns' do
    allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)
    travel_to(Time.zone.parse('2026-10-04 12:00:00')) { described_class.new.perform(execution.id) }

    expect(mqtt_client).to have_received(:publish) do |topic, payload, options|
      expect(topic).to eq("#{target.chip_id}/switchon")
      expect(JSON.parse(payload)).to eq(
        'chip_id' => target.chip_id,
        'relay_index' => 0,
        'switch_value' => 1,
        'longlast' => 1000,
        'sent_time' => Time.zone.parse('2026-10-04 12:00:00').to_i.to_s
      )
      expect(options).to eq(retain: false)
    end
    expect(execution.reload).to have_attributes(status: 'publish_returned', error_code: nil)
    expect(execution.publish_attempted_at).to be_present
    expect(execution.publish_returned_at).to be_present
  end

  it 'publishes the exact immutable legacy snapshot with only a refreshed sent_time' do
    payload = {
      'chip_id' => target.chip_id,
      'relay_index' => 2,
      'switch_value' => 0,
      'longlast' => 900,
      'custom_field' => 'preserve-me'
    }
    legacy = legacy_execution(payload)
    allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)

    travel_to(Time.zone.parse('2026-10-04 12:30:00')) { described_class.new.perform(legacy.id) }

    expect(legacy.action_key).to eq('legacy')
    expect(mqtt_client).to have_received(:publish) do |topic, published, options|
      expect(topic).to eq("#{target.chip_id}/switchon")
      expect(JSON.parse(published)).to eq(payload.merge('sent_time' => Time.zone.parse('2026-10-04 12:30:00').to_i.to_s))
      expect(options).to eq(retain: false)
    end
    expect(legacy.reload).to have_attributes(status: 'publish_returned', error_code: nil)
  end

  it 'preserves the historical relay_indexes field in a legacy snapshot' do
    payload = {
      'chip_id' => target.chip_id,
      'relay_indexes' => [1, 3],
      'longlast' => 700,
      'custom_field' => 'unchanged'
    }
    legacy = legacy_execution(payload)
    allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)

    travel_to(Time.zone.parse('2026-10-04 12:45:00')) { described_class.new.perform(legacy.id) }

    expect(mqtt_client).to have_received(:publish) do |_topic, published, _options|
      expect(JSON.parse(published)).to eq(payload.merge('sent_time' => Time.zone.parse('2026-10-04 12:45:00').to_i.to_s))
      expect(JSON.parse(published)).not_to have_key('relay_index')
    end
  end

  it 'records connect failure before attempt separately from uncertain publish outcome' do
    allow(MQTT::Client).to receive(:connect).and_raise(MQTT::Exception.new('offline'))
    described_class.new.perform(execution.id)
    expect(execution.reload).to have_attributes(status: 'failed', error_code: 'mqtt_connect_failed')
    expect(execution.publish_attempted_at).to be_nil

    another = execution.dup
    another.action_key = 'action:other'
    another.status = 'queued'
    another.save!
    allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)
    allow(mqtt_client).to receive(:publish).and_raise(MQTT::Exception.new('lost'))
    described_class.new.perform(another.id)
    expect(another.reload).to have_attributes(status: 'failed', error_code: 'publish_outcome_unknown')
    expect(another.publish_attempted_at).to be_present
  end

  it 'does not connect or publish for terminal or duplicate execution attempts' do
    execution.update_columns(status: 'publish_returned', publish_returned_at: Time.current)
    expect(MQTT::Client).not_to receive(:connect)
    2.times { described_class.new.perform(execution.id) }
  end

  it 'skips when the action is removed before execution' do
    execution
    action.destroy!
    expect(MQTT::Client).not_to receive(:connect)
    described_class.new.perform(execution.id)
    expect(execution.reload).to have_attributes(status: 'skipped', error_code: 'action_missing')
  end

  it 'revalidates again immediately before publish and skips a concurrently removed action' do
    execution
    allow(MQTT::Client).to receive(:connect) do
      action.destroy!
      mqtt_client
    end
    expect(mqtt_client).not_to receive(:publish)

    described_class.new.perform(execution.id)

    expect(execution.reload).to have_attributes(status: 'skipped', error_code: 'action_missing')
  end

  it 'does not let a losing duplicate connection failure overwrite the winning publish attempt' do
    execution
    winner_client = instance_double(MQTT::Client, disconnect: nil)
    winner_fiber = nil
    connect_calls = 0

    allow(winner_client).to receive(:publish) { Fiber.yield(:winner_claimed) }
    allow(MQTT::Client).to receive(:connect) do
      connect_calls += 1
      if connect_calls == 1
        expect(winner_fiber.resume).to eq(:winner_claimed)
        raise MQTT::Exception, 'loser connection failed'
      end
      winner_client
    end
    allow(Rails.logger).to receive(:error)

    winner_fiber = Fiber.new do
      described_class.new.perform(execution.id)
      :winner_finished
    end

    described_class.new.perform(execution.id)
    expect(execution.reload).to have_attributes(status: 'publish_attempted', error_code: nil)

    expect(winner_fiber.resume).to eq(:winner_finished)
    expect(winner_client).to have_received(:publish).once
    expect(execution.reload).to have_attributes(status: 'publish_returned', error_code: nil)
  end

  it 'skips a disabled action or a relay removed after enqueue' do
    execution
    action.update!(enabled: false)
    expect(MQTT::Client).not_to receive(:connect)
    described_class.new.perform(execution.id)
    expect(execution.reload).to have_attributes(status: 'skipped', error_code: 'action_disabled')

    second = execution.dup
    second.action_key = 'action:relay-change'
    second.status = 'queued'
    second.device_trigger_action = action
    second.save!
    action.update_columns(enabled: true)
    target.update!(device_info: { relays: [] }.to_json)
    described_class.new.perform(second.id)
    expect(second.reload).to have_attributes(status: 'skipped', error_code: 'invalid_relay_index')
  end

  it 'skips when target ownership or relay configuration changed' do
    execution
    target.users.delete(user)
    expect(MQTT::Client).not_to receive(:connect)
    described_class.new.perform(execution.id)
    expect(execution.reload).to have_attributes(status: 'skipped', error_code: 'ownership_changed')
  end

  it 'declares retry false because a publish timeout has uncertain delivery' do
    expect(described_class.get_sidekiq_options['retry']).to eq(false)
  end
end
