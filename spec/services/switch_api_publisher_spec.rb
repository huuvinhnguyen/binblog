require 'rails_helper'

RSpec.describe SwitchApi::Publisher do
  let(:client) { instance_double(MQTT::Client, connect: nil, publish: nil, disconnect: nil) }

  before do
    allow(Rails.application).to receive(:config_for).with(:mqtt).and_return(host: 'test.invalid', port: 1883)
    allow(MQTT::Client).to receive(:new).and_return(client)
  end

  it 'uses configured connection, no retain and QoS zero, then disconnects' do
    described_class.new.call(topic: 'test_switch/switchon', payload: { longlast: 1000 })
    expect(client).to have_received(:publish).with('test_switch/switchon', '{"longlast":1000}', false, 0).once
    expect(client).to have_received(:disconnect).with(false)
  end

  it 'classifies connection errors as not attempted and performs cleanup' do
    allow(client).to receive(:connect).and_raise(IOError, 'private connection detail')
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::Unavailable)
    expect(client).not_to have_received(:publish)
    expect(client).to have_received(:disconnect)
  end

  it 'classifies partial publish and disconnect failures as unknown without retry' do
    allow(client).to receive(:publish).and_raise(IOError)
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::OutcomeUnknown)
    expect(client).to have_received(:publish).once
    allow(client).to receive(:publish).and_return(nil)
    allow(client).to receive(:disconnect).and_raise(IOError)
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::OutcomeUnknown)
  end

  it 'maps the MQTT library protocol exception before publish and still cleans up' do
    expect(MQTT::ProtocolException.ancestors).not_to include(StandardError)
    allow(client).to receive(:connect).and_raise(MQTT::ProtocolException, 'synthetic CONNACK refusal')
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::Unavailable)
    expect(client).not_to have_received(:publish)
    expect(client).to have_received(:disconnect).with(false).once
  end

  it 'maps the MQTT library disconnected publish exception to an unknown outcome without retry' do
    allow(client).to receive(:publish).and_raise(MQTT::NotConnectedException)
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::OutcomeUnknown)
    expect(client).to have_received(:publish).once
    expect(client).to have_received(:disconnect).with(false).once
  end

  it 'maps MQTT cleanup errors after publish to an unknown outcome' do
    allow(client).to receive(:disconnect).and_raise(MQTT::ProtocolException)
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::OutcomeUnknown)
    expect(client).to have_received(:publish).once
  end

  it 'keeps the not-attempted outcome when MQTT connect and cleanup both fail' do
    allow(client).to receive(:connect).and_raise(MQTT::ProtocolException)
    allow(client).to receive(:disconnect).and_raise(MQTT::NotConnectedException)
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(described_class::Unavailable)
    expect(client).not_to have_received(:publish)
  end

  it 'does not swallow process interrupts' do
    allow(client).to receive(:publish).and_raise(Interrupt)
    expect { described_class.new.call(topic: 'test', payload: {}) }.to raise_error(Interrupt)
    expect(client).to have_received(:disconnect).with(false).once
  end
end
