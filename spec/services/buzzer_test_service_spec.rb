require 'rails_helper'

RSpec.describe BuzzerTestService do
  let(:user) { User.create!(username: "buzzer_service_#{SecureRandom.hex(4)}", email: "buzzer-service-#{SecureRandom.hex(4)}@example.com", password: 'password123') }
  let(:buzzer) do
    Device.create!(
      chip_id: "esp32_buzzer_service_#{SecureRandom.hex(4)}",
      name: 'Buzzer service test',
      device_type: 'buzzer',
      status: 1,
      is_payment: false,
      device_info: { relays: [{ switch_value: 0, longlast: 1000 }] }.to_json
    )
  end
  let(:mqtt_client_class) { class_double(MQTT::Client) }
  let(:client) { instance_double(MQTT::Client) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(mqtt_client_class).to receive(:connect).and_return(client)
    allow(client).to receive(:publish)
    allow(client).to receive(:disconnect)
  end

  def call_service
    described_class.new(device: buzzer, user: user, mqtt_client: mqtt_client_class, cache: cache).call
  end

  it 'publishes the compatible MQTT command and records an audit event' do
    result = call_service

    expect(result).to have_attributes(relay_index: 0, longlast: 1000)
    expect(client).to have_received(:publish) do |topic, payload, retain:|
      expect(topic).to eq("#{buzzer.chip_id}/switchon")
      expect(JSON.parse(payload)).to include(
        'chip_id' => buzzer.chip_id,
        'relay_index' => 0,
        'longlast' => 1000,
        'sent_time' => be_a(String)
      )
      expect(retain).to be(false)
    end
    expect(mqtt_client_class).to have_received(:connect).with(
      Rails.application.config_for(:mqtt).symbolize_keys.slice(:host, :port)
    )
    expect(client).to have_received(:disconnect)

    event = buzzer.device_events.last
    expect(event).to have_attributes(event_type: 'buzzer_test_requested')
    expect(event.parsed_payload).to include(
      'relay_index' => 0,
      'longlast' => 1000,
      'requested_by_user_id' => user.id
    )
  end

  it 'rejects an invalid Buzzer duration without publishing' do
    buzzer.update!(device_info: { relays: [{ longlast: 20_000 }] }.to_json)

    expect { call_service }.to raise_error(
      BuzzerTestService::ConfigurationError,
      /Thời lượng Buzzer/
    )
    expect(mqtt_client_class).not_to have_received(:connect)
  end

  it 'releases the cooldown and disconnects when MQTT publishing fails' do
    allow(client).to receive(:publish).and_raise(StandardError, 'broker unavailable')

    expect { call_service }.to raise_error(BuzzerTestService::PublishError, /broker unavailable/)
    expect(client).to have_received(:disconnect)
    expect(cache.exist?("buzzer-test:#{buzzer.id}")).to be(false)
  end

  it 'prevents duplicate test commands during the cooldown' do
    call_service

    expect { call_service }.to raise_error(BuzzerTestService::CooldownError)
    expect(client).to have_received(:publish).once
  end
end
