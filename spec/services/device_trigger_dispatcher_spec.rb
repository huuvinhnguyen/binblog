require 'rails_helper'

RSpec.describe DeviceTriggerDispatcher do
  let(:user) { User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123') }
  let(:source) { device('pir') }
  let(:first_target) { device('buzzer', device_info: { relays: [{}] }.to_json) }
  let(:second_target) { device('switch', device_info: { relays: [{}, {}] }.to_json) }

  def device(type, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), device_type: type }.merge(attributes)).tap { |record| record.users << user }
  end

  def add_action(target:, position:, delay_ms: 0, enabled: true, relay_index: 0)
    source.trigger_actions.create!(
      target_device: target,
      action_type: 'relay_pulse',
      relay_index: relay_index,
      duration_ms: 1000,
      delay_ms: delay_ms,
      enabled: enabled,
      position: position
    )
  end

  before do
    allow(DeviceTriggerFeature).to receive(:enabled?).and_return(true)
    allow(DeviceTriggerActionExecutor).to receive(:new)
      .and_return(instance_double(DeviceTriggerActionExecutor, call: nil))
  end

  it 'creates one event and one immutable execution per enabled action in configured order' do
    second = add_action(target: second_target, position: 2, relay_index: 1)
    first = add_action(target: first_target, position: 1)

    event = described_class.new(source_device: source, request_metadata: { 'triggered_from' => '127.0.0.1' }).call

    expect(event.parsed_payload).to include('configuration_mode' => 'actions', 'selected_action_count' => 2)
    executions = event.trigger_action_executions.order(:configured_position)
    expect(executions.map(&:device_trigger_action_id)).to eq([first.id, second.id])
    expect(executions.map(&:status)).to eq(%w[pending_publish pending_publish])
    expect(executions.map(&:queued_at)).to eq([nil, nil])
    expect(executions.map(&:command_payload)).to eq(
      [
        {
          'chip_id' => first_target.chip_id,
          'relay_index' => 0,
          'longlast' => 1000
        },
        {
          'chip_id' => second_target.chip_id,
          'relay_index' => 1,
          'longlast' => 1000
        }
      ]
    )
    expect(DeviceTriggerActionExecutor).to have_received(:new).with(execution: executions.first).ordered
    expect(DeviceTriggerActionExecutor).to have_received(:new).with(execution: executions.second).ordered
    expect(DeviceTriggerActionJob.jobs).to be_empty
  end

  it 'commits event and execution before invoking each synchronous executor' do
    add_action(target: first_target, position: 0)
    expect(DeviceTriggerActionExecutor).to receive(:new) do |execution:|
      expect(DeviceTriggerActionExecution.find(execution.id).device_event).to be_persisted
      instance_double(DeviceTriggerActionExecutor, call: nil)
    end

    described_class.new(source_device: source).call
  end

  it 'does not let one executor failure block a sibling' do
    add_action(target: first_target, position: 0)
    add_action(target: second_target, position: 1)
    calls = []
    allow(Rails.logger).to receive(:error)
    allow(DeviceTriggerActionExecutor).to receive(:new) do |execution:|
      runner = instance_double(DeviceTriggerActionExecutor)
      allow(runner).to receive(:call) do
        calls << execution.configured_position
        raise 'first failed' if execution.configured_position.zero?
      end
      runner
    end

    expect { described_class.new(source_device: source).call }.not_to raise_error
    expect(calls).to eq([0, 1])
  end

  it 'rolls the request event back when execution persistence fails before commit' do
    add_action(target: first_target, position: 0)
    dispatcher = described_class.new(source_device: source)
    allow(dispatcher).to receive(:build_action_executions).and_raise(ActiveRecord::RecordInvalid)

    expect { dispatcher.call }.to raise_error(ActiveRecord::RecordInvalid)
    expect(source.device_events.reload).to be_empty
    expect(DeviceTriggerActionExecutor).not_to have_received(:new)
  end

  it 'skips an invalid action independently when ownership changed after configuration' do
    add_action(target: first_target, position: 0)
    add_action(target: second_target, position: 1)
    second_target.users.delete(user)

    event = described_class.new(source_device: source).call
    expect(event.trigger_action_executions.order(:configured_position).pluck(:status, :error_code)).to eq(
      [['pending_publish', nil], ['skipped', 'ownership_changed']]
    )
  end

  it 'suppresses legacy fallback when all persisted actions are disabled' do
    source.update!(trigger: { chip_id: first_target.chip_id, relay_index: 0, longlast: 1000 }.to_json)
    add_action(target: first_target, position: 0, enabled: false)

    event = described_class.new(source_device: source).call
    expect(event.parsed_payload).to include('configuration_mode' => 'actions', 'selected_action_count' => 0)
    expect(event.trigger_action_executions).to be_empty
    expect(DeviceTriggerActionExecutor).not_to have_received(:new)
  end

  it 'creates a synchronous compatibility execution for legacy PIR configuration' do
    source.update!(trigger: { chip_id: first_target.chip_id, relay_index: 0, longlast: 1000, note: 'keep' }.to_json)

    event = described_class.new(source_device: source).call
    execution = event.trigger_action_executions.first
    expect(event.parsed_payload).to include('target_chip_id' => first_target.chip_id, 'relay_index' => 0, 'longlast' => 1000)
    expect(execution).to have_attributes(action_key: 'legacy', target_chip_id: first_target.chip_id, status: 'pending_publish')
    expect(execution.command_payload).to include('note' => 'keep')
  end

  it 'preserves legacy behavior for non-PIR sources' do
    switch_source = device('switch', trigger: { chip_id: first_target.chip_id, relay_index: 0, longlast: 1000 }.to_json)
    event = described_class.new(source_device: switch_source).call
    expect(event.trigger_action_executions.first.action_key).to eq('legacy')
  end

  it 'records no action executions while the feature flag is disabled' do
    add_action(target: first_target, position: 0)
    allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false)
    event = described_class.new(source_device: source).call
    expect(event.parsed_payload['selected_action_count']).to eq(0)
    expect(event.trigger_action_executions).to be_empty
  end

  it 'persists and skips a grandfathered nonzero-delay action without invoking the executor' do
    delayed = add_action(target: first_target, position: 0)
    delayed.update_columns(delay_ms: 250)

    event = described_class.new(source_device: source).call

    expect(event.trigger_action_executions.first).to have_attributes(
      status: 'skipped', error_code: 'delay_not_supported', delay_ms: 250
    )
    expect(DeviceTriggerActionExecutor).not_to have_received(:new)
  end

  it 'rejects missing or malformed legacy configuration without creating an event' do
    [nil, '{}', '{bad', '[]'].each do |trigger|
      source.update!(trigger: trigger)
      before_count = DeviceEvent.count
      expect { described_class.new(source_device: source).call }.to raise_error(described_class::InvalidConfiguration)
      expect(DeviceEvent.count).to eq(before_count)
    end
  end
end
