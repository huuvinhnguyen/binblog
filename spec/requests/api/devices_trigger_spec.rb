require 'rails_helper'

RSpec.describe 'POST /api/devices/trigger', type: :request do
  let(:mqtt_client) { instance_double(MQTT::Client, connect: nil, publish: nil, disconnect: nil) }
  let(:device) do
    Device.create!(
      chip_id: 'esp32_test_pir_trigger',
      name: 'Test PIR',
      device_type: 'pir',
      status: 1,
      is_payment: false,
      trigger: {
        chip_id: 'esp32_test_buzzer_target',
        relay_index: 0,
        switch_value: 1,
        longlast: 1000
      }.to_json
    )
  end

  after do
    device.destroy
  end

  before do
    allow(MQTT::Client).to receive(:new).and_return(mqtt_client)
  end

  describe 'motion detection trigger' do
    it 'creates a device_event when device is found' do
      expect {
        post '/api/devices/trigger', params: { chip_id: device.chip_id }
      }.to change { DeviceEvent.count }.by(1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('success')

      event = DeviceEvent.last
      expect(event.device_id).to eq(device.id)
      expect(event.event_type).to eq('motion_detected')
      expect(event.occurred_at).to be_within(2.seconds).of(Time.current)
      expect(event.parsed_payload).to include(
        'target_chip_id' => 'esp32_test_buzzer_target',
        'relay_index' => 0,
        'longlast' => 1000
      )
    end

    it 'returns error when device not found' do
      post '/api/devices/trigger', params: { chip_id: 'nonexistent_chip' }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('error')
      expect(json['message']).to eq('Device not found')
    end

    it 'fans one PIR motion event out synchronously and persists final action outcomes' do
      user = User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
      device.users << user
      targets = %w[buzzer switch].map do |type|
        Device.create!(chip_id: SecureRandom.hex(8), device_type: type,
                       device_info: { relays: [{}] }.to_json).tap { |target| target.users << user }
      end
      targets.each_with_index do |target, index|
        device.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                       duration_ms: 1000, delay_ms: 0, enabled: true, position: index)
      end

      post '/api/devices/trigger', params: { chip_id: device.chip_id }, as: :json

      expect(response).to have_http_status(:ok)
      event = device.device_events.last
      expect(event.parsed_payload).to include('configuration_mode' => 'actions', 'selected_action_count' => 2)
      expect(event.trigger_action_executions.order(:configured_position).pluck(:target_device_id)).to eq(targets.map(&:id))
      expect(event.trigger_action_executions.pluck(:status)).to all(eq('publish_returned'))
      expect(mqtt_client).to have_received(:publish).twice
      expect(DeviceTriggerActionJob.jobs).to be_empty
    end

    it 'does not fall back to legacy when the source has only disabled action rows' do
      user = User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
      device.users << user
      target = Device.create!(chip_id: SecureRandom.hex(8), device_type: 'buzzer',
                              device_info: { relays: [{}] }.to_json).tap { |record| record.users << user }
      device.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                     duration_ms: 1000, delay_ms: 0, enabled: false, position: 0)

      post '/api/devices/trigger', params: { chip_id: device.chip_id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(device.device_events.last.trigger_action_executions).to be_empty
      expect(device.device_events.last.parsed_payload['selected_action_count']).to eq(0)
    end

    it 'waits for the legacy publish attempt and preserves the existing response' do

      expect {
        post '/api/devices/trigger', params: { chip_id: device.chip_id }
      }.to change { DeviceEvent.count }.by(1)

      expect(response).to have_http_status(:ok)
      execution = DeviceEvent.last.trigger_action_executions.first
      expect(execution).to have_attributes(status: 'publish_returned', action_key: 'legacy')
      expect(mqtt_client).to have_received(:publish)
      expect(DeviceTriggerActionJob.jobs).to be_empty
    end
  end
end
