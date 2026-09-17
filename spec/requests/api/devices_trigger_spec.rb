require 'rails_helper'

RSpec.describe 'POST /api/devices/trigger', type: :request do
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

  describe 'motion detection trigger' do
    it 'creates a device_event when device is found' do
      allow_any_instance_of(Api::DevicesController).to receive(:trigger_device)

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

    it 'does not trigger device when MQTT fails but still creates event' do
      allow_any_instance_of(Api::DevicesController).to receive(:trigger_device).and_raise(StandardError.new('MQTT error'))

      expect {
        post '/api/devices/trigger', params: { chip_id: device.chip_id }
      }.to change { DeviceEvent.count }.by(1)

      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
