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
  end

  it 'creates one event and one immutable execution per enabled action in configured order' do
    second = add_action(target: second_target, position: 2, delay_ms: 500, relay_index: 1)
    first = add_action(target: first_target, position: 1)

    event = described_class.new(source_device: source, request_metadata: { 'triggered_from' => '127.0.0.1' }).call

    expect(event.parsed_payload).to include('configuration_mode' => 'actions', 'selected_action_count' => 2)
    executions = event.trigger_action_executions.order(:configured_position)
    expect(executions.map(&:device_trigger_action_id)).to eq([first.id, second.id])
    expect(executions.map(&:status)).to eq(%w[queued queued])
    expect(executions.second.scheduled_for).to be_within(1.second).of(event.occurred_at + 0.5)
    expect(DeviceTriggerActionJob.jobs.map { |job| job['args'].first }).to match_array(executions.ids)
  end

  it 'commits event and execution before enqueueing each independent job' do
    add_action(target: first_target, position: 0)
    expect(DeviceTriggerActionJob).to receive(:perform_async) do |execution_id|
      expect(DeviceTriggerActionExecution.find(execution_id).device_event).to be_persisted
    end.and_return('jid')

    described_class.new(source_device: source).call
  end

  it 'marks one enqueue failure without blocking another execution' do
    add_action(target: first_target, position: 0)
    add_action(target: second_target, position: 1)
    calls = 0
    allow(DeviceTriggerActionJob).to receive(:perform_async) do
      calls += 1
      raise Redis::CannotConnectError if calls == 1
      'jid'
    end

    event = described_class.new(source_device: source).call
    expect(event.trigger_action_executions.order(:configured_position).pluck(:status, :error_code)).to eq(
      [['failed', 'enqueue_failed'], ['queued', nil]]
    )
  end

  it 'rolls the request event back when execution persistence fails before commit' do
    add_action(target: first_target, position: 0)
    dispatcher = described_class.new(source_device: source)
    allow(dispatcher).to receive(:build_action_executions).and_raise(ActiveRecord::RecordInvalid)

    expect { dispatcher.call }.to raise_error(ActiveRecord::RecordInvalid)
    expect(source.device_events.reload).to be_empty
    expect(DeviceTriggerActionJob.jobs).to be_empty
  end

  it 'skips an invalid action independently when ownership changed after configuration' do
    add_action(target: first_target, position: 0)
    add_action(target: second_target, position: 1)
    second_target.users.delete(user)

    event = described_class.new(source_device: source).call
    expect(event.trigger_action_executions.order(:configured_position).pluck(:status, :error_code)).to eq(
      [['queued', nil], ['skipped', 'ownership_changed']]
    )
  end

  it 'suppresses legacy fallback when all persisted actions are disabled' do
    source.update!(trigger: { chip_id: first_target.chip_id, relay_index: 0, longlast: 1000 }.to_json)
    add_action(target: first_target, position: 0, enabled: false)

    event = described_class.new(source_device: source).call
    expect(event.parsed_payload).to include('configuration_mode' => 'actions', 'selected_action_count' => 0)
    expect(event.trigger_action_executions).to be_empty
    expect(DeviceTriggerActionJob.jobs).to be_empty
  end

  it 'creates an asynchronous compatibility execution for legacy PIR configuration' do
    source.update!(trigger: { chip_id: first_target.chip_id, relay_index: 0, longlast: 1000, note: 'keep' }.to_json)

    event = described_class.new(source_device: source).call
    execution = event.trigger_action_executions.first
    expect(event.parsed_payload).to include('target_chip_id' => first_target.chip_id, 'relay_index' => 0, 'longlast' => 1000)
    expect(execution).to have_attributes(action_key: 'legacy', target_chip_id: first_target.chip_id, status: 'queued')
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

  it 'rejects missing or malformed legacy configuration without creating an event' do
    [nil, '{bad', '[]'].each do |trigger|
      source.update!(trigger: trigger)
      before_count = DeviceEvent.count
      expect { described_class.new(source_device: source).call }.to raise_error(described_class::InvalidConfiguration)
      expect(DeviceEvent.count).to eq(before_count)
    end
  end
end
