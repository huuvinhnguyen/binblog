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

    it 'fans one PIR motion event out to persisted action executions without waiting for MQTT' do
      user = User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
      device.users << user
      targets = %w[buzzer switch].map do |type|
        Device.create!(chip_id: SecureRandom.hex(8), device_type: type,
                       device_info: { relays: [{}] }.to_json).tap { |target| target.users << user }
      end
      targets.each_with_index do |target, index|
        device.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                       duration_ms: 1000, delay_ms: index * 100, enabled: true, position: index)
      end
      expect(MQTT::Client).not_to receive(:connect)

      post '/api/devices/trigger', params: { chip_id: device.chip_id }, as: :json

      expect(response).to have_http_status(:ok)
      event = device.device_events.last
      expect(event.parsed_payload).to include('configuration_mode' => 'actions', 'selected_action_count' => 2)
      expect(event.trigger_action_executions.order(:configured_position).pluck(:target_device_id)).to eq(targets.map(&:id))
      expect(event.trigger_action_executions.pluck(:status)).to all(eq('queued'))
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

    it 'returns immediately after persisting and enqueueing the legacy execution' do

      expect {
        post '/api/devices/trigger', params: { chip_id: device.chip_id }
      }.to change { DeviceEvent.count }.by(1)

      expect(response).to have_http_status(:ok)
      execution = DeviceEvent.last.trigger_action_executions.first
      expect(execution).to have_attributes(status: 'queued', action_key: 'legacy')
      expect(DeviceTriggerActionJob.jobs.map { |job| job['args'].first }).to include(execution.id)
    end
  end
end
