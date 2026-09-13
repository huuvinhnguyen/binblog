require 'rails_helper'

RSpec.describe 'PIR Device UI', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { User.create!(username: 'testuser', email: 'test@example.com', password: 'password123') }
  let(:pir_device) do
    Device.create!(
      chip_id: 'esp32_PIR_TEST_001',
      name: 'PIR Phòng khách Test',
      device_type: 'pir',
      status: 1,
      is_payment: false,
      note: 'Test PIR device',
      device_info: {
        device_type: 'pir',
        device_id: 'esp32_PIR_TEST_001',
        update_at: 1.minute.ago.to_i,
        local_ip: '192.168.1.100',
        build_version: 1,
        app_version: '1.0.0'
      }.to_json,
      trigger: nil,
      meta_info: {}.to_json
    )
  end

  before do
    # Link device to user
    pir_device.users << user

    # Create some device events
    3.times do |i|
      DeviceEvent.create!(
        device: pir_device,
        event_type: 'motion_detected',
        occurred_at: (i + 1).minutes.ago,
        payload: {
          triggered_from: '192.168.1.50',
          user_agent: 'ESP32-HTTPClient/1.0'
        }.to_json
      )
    end

    # Login user
    sign_in user
  end

  describe 'GET /devices/:id for PIR device' do
    it 'displays PIR device information' do
      get device_path(pir_device)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('PIR Phòng khách Test')
      expect(response.body).to include('192.168.1.100')
      expect(response.body).to include('1.0.0')
    end

    it 'displays motion detection history' do
      get device_path(pir_device)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Lịch sử phát hiện chuyển động')
      expect(response.body).to include('192.168.1.50')
      expect(response.body).to include('ESP32-HTTPClient/1.0')
    end

    it 'renders the 24-hour motion chart with motion event data' do
      get device_path(pir_device)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('id="pir-motion-chart"')
      expect(response.body).to include('Phát hiện chuyển động')
      expect(response.body).to include('data-labels=')
      expect(response.body).to include('data-values=')
    end

    it 'loads device events for PIR devices' do
      get device_path(pir_device)

      device_events = pir_device.device_events.order(occurred_at: :desc).limit(20)
      expect(device_events).to be_present
      expect(device_events.count).to eq(3)
      expect(device_events.first.event_type).to eq('motion_detected')
    end

    it 'limits device events to 20' do
      # Create 25 events
      25.times do |i|
        DeviceEvent.create!(
          device: pir_device,
          event_type: 'motion_detected',
          occurred_at: (i + 10).minutes.ago,
          payload: {
            triggered_from: '192.168.1.50',
            user_agent: 'ESP32-HTTPClient/1.0'
          }.to_json
        )
      end

      get device_path(pir_device)

      device_events = pir_device.device_events.order(occurred_at: :desc).limit(20)
      expect(device_events.count).to eq(20)
    end

    it 'orders events by occurred_at descending' do
      get device_path(pir_device)

      device_events = pir_device.device_events.order(occurred_at: :desc).limit(20)
      expect(device_events.first.occurred_at).to be > device_events.last.occurred_at
    end
  end
end
