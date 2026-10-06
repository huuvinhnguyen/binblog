require 'rails_helper'

RSpec.describe DeviceTriggerCommandPublisher do
  let(:execution) do
    instance_double(
      DeviceTriggerActionExecution,
      action_key: 'action:1',
      target_chip_id: 'TARGET_01',
      relay_index: 0,
      duration_ms: 1000,
      command_payload: { chip_id: 'TARGET_01', relay_index: 0, longlast: 1000 }
    )
  end

  let(:client) { instance_double(MQTT::Client, connect: nil, publish: nil, disconnect: nil) }

  before do
    allow(MQTT::Client).to receive(:new).and_return(client)
  end

  it 'publishes the duration-only relay pulse contract and passes boolean false as the positional retain argument' do
    calls = []
    allow(MQTT::Client).to receive(:new) { calls << :new; client }
    allow(client).to receive(:connect) { calls << :connect }
    allow(client).to receive(:publish) { calls << :publish }
    expect(Timeout).to receive(:timeout).with(5).and_yield

    travel_to(Time.zone.parse('2026-10-06 09:50:01')) do
      described_class.new(execution: execution).call
    end

    expect(MQTT::Client).to have_received(:new).with(host: anything, port: anything)
    expect(client).to have_received(:publish).with(
      'TARGET_01/switchon',
      {
        'chip_id' => 'TARGET_01',
        'relay_index' => 0,
        'longlast' => 1000,
        'sent_time' => '2026-10-06 09:50:01'
      }.to_json,
      false
    )
    expect(calls).to eq(%i[new connect publish])
    expect(client).to have_received(:disconnect).with(false)
  end

  it 'refreshes only sent_time in a legacy snapshot using the firmware-compatible format' do
    legacy_payload = {
      'chip_id' => 'TARGET_01',
      'relay_indexes' => [1, 3],
      'longlast' => 700,
      'sent_time' => 'stale',
      'custom_field' => 'keep'
    }
    legacy_execution = instance_double(
      DeviceTriggerActionExecution,
      action_key: 'legacy',
      target_chip_id: 'TARGET_01',
      command_payload: legacy_payload
    )

    travel_to(Time.zone.parse('2026-10-06 09:50:01')) do
      described_class.new(execution: legacy_execution).call
    end

    expect(client).to have_received(:publish).with(
      'TARGET_01/switchon',
      legacy_payload.merge('sent_time' => '2026-10-06 09:50:01').to_json,
      false
    )
    expect(legacy_payload).to include('sent_time' => 'stale', 'custom_field' => 'keep')
  end

  it 'preserves a connect failure when best-effort cleanup also fails' do
    allow(client).to receive(:connect).and_raise(MQTT::Exception.new('primary connect failure'))
    allow(client).to receive(:disconnect).with(false).and_raise(IOError.new('cleanup failure'))
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new(execution: execution).call }
      .to raise_error(DeviceTriggerCommandPublisher::ConnectError, 'primary connect failure')
    expect(client).not_to have_received(:publish)
    expect(Rails.logger).to have_received(:warn).with(/IOError/)
  end

  it 'preserves a publish failure when best-effort cleanup also fails' do
    allow(client).to receive(:publish).and_raise(MQTT::Exception.new('primary publish failure'))
    allow(client).to receive(:disconnect).with(false).and_raise(IOError.new('cleanup failure'))
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new(execution: execution).call }
      .to raise_error(DeviceTriggerCommandPublisher::PublishError, 'primary publish failure')
    expect(Rails.logger).to have_received(:warn).with(/IOError/)
  end

  it 'does not turn a successful publish into failure when best-effort cleanup fails' do
    allow(client).to receive(:disconnect).with(false).and_raise(IOError.new('cleanup failure'))
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new(execution: execution).call }.not_to raise_error

    expect(client).to have_received(:publish)
    expect(Rails.logger).to have_received(:warn).with(/IOError/)
  end

  it 'attempts cleanup and reports a connect timeout without publishing' do
    allow(client).to receive(:connect).and_raise(Timeout::Error.new('connect timeout'))

    expect { described_class.new(execution: execution).call }
      .to raise_error(DeviceTriggerCommandPublisher::ConnectError, 'connect timeout')
    expect(client).not_to have_received(:publish)
    expect(client).to have_received(:disconnect).with(false)
  end

  it 'reports a publish timeout as an uncertain publish outcome' do
    allow(client).to receive(:publish).and_raise(Timeout::Error.new('publish timeout'))

    expect { described_class.new(execution: execution).call }
      .to raise_error(DeviceTriggerCommandPublisher::PublishError, 'publish timeout')
    expect(client).to have_received(:disconnect).with(false)
  end
end
