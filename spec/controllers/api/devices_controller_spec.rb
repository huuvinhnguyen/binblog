# spec/controllers/api/devices_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DevicesController, type: :controller do

  describe 'POST #set_longlast' do
    let!(:device) do
      Device.create!(
        name: "Test Device",
        chip_id: "abc123",
        device_info: {
          relays: [{ "switch_value" => 1 }],
          update_at: Time.zone.now.to_i
        }.to_json
      )
    end

    it 'sets longlast and returns success' do
      post :set_longlast, params: {
        device_id: device.chip_id,
        longlast: 120_000,
        relay_index: 0
      }, format: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['status']).to eq('success')

      device.reload
      device_info = JSON.parse(device.device_info)
      expect(device_info['relays']).to be_present
    end
  end

  describe 'POST #reset_wifi' do
    let(:device_id) { 'ABC123' }
    let!(:device) do
      Device.create!(
        name: "ESP Device",
        chip_id: device_id,
        device_info: {}.to_json
      )
    end

    let(:mqtt_client) { double('MQTT::Client') }

    before do
      allow(controller).to receive(:mqtt_client).and_return(mqtt_client)
      allow(mqtt_client).to receive(:publish)
      allow(mqtt_client).to receive(:disconnect)
    end

    it 'publishes MQTT message and returns success JSON' do
      post :reset_wifi, params: { chip_id: device_id }, format: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['status']).to eq('ok')
      expect(json['topic']).to eq("#{device_id}/reset_wifi")
      expect(json['message']['action']).to eq('reset_wifi')

      expect(mqtt_client).to have_received(:publish)
      expect(mqtt_client).to have_received(:disconnect)
    end
  end

  describe 'POST #refresh_device' do
    let(:device_id) { 'ABC123' }
    let!(:device) do
      Device.create!(
        name: "ESP Device",
        chip_id: device_id,
        device_info: {}.to_json
      )
    end

    let(:mqtt_client) { double('MQTT::Client') }

    before do
      allow(controller).to receive(:mqtt_client).and_return(mqtt_client)
      allow(mqtt_client).to receive(:publish)
      allow(mqtt_client).to receive(:disconnect)
    end

    it 'publishes MQTT message and returns success JSON' do
      post :refresh_device, params: { chip_id: device_id }, format: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['status']).to eq('ok')
      expect(json['topic']).to eq("#{device_id}/refresh_device")

      expect(mqtt_client).to have_received(:publish)
      expect(mqtt_client).to have_received(:disconnect)
    end
  end
end
