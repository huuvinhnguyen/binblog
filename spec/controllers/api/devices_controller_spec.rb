# spec/controllers/api/devices_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DevicesController, type: :controller do

  describe 'GET #index' do
    let!(:user) do
      User.create!(username: 'demo_user', email: 'demo@example.com', password: 'password123')
    end

    let!(:device_1) { Device.create!(name: 'Device A', chip_id: 'chip_a', device_info: {}.to_json) }
    let!(:device_2) { Device.create!(name: 'Device B', chip_id: 'chip_b', device_info: {}.to_json) }

    before do
      user.devices << [device_1, device_2]
      request.headers['Authorization'] = "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
    end

    it 'returns all devices in JSON for authenticated user' do
      get :index, format: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['status']).to eq('success')
      expect(json['devices'].map { |d| d['chip_id'] }).to contain_exactly('chip_a', 'chip_b')
    end
  end

  describe 'POST #set_longlast' do
    let!(:user) do
      User.create!(username: 'token_user', email: 'token@example.com', password: 'password123')
    end

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

    before do
      request.headers['Authorization'] = "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
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
    let!(:user) do
      User.create!(username: 'wifi_user', email: 'wifi@example.com', password: 'password123')
    end

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
      request.headers['Authorization'] = "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
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
    let!(:user) do
      User.create!(username: 'refresh_user', email: 'refresh@example.com', password: 'password123')
    end

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
      request.headers['Authorization'] = "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
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

  describe 'API auth fallback' do
    let!(:user) do
      User.create!(username: 'session_user', email: 'session@example.com', password: 'password123')
    end

    let!(:device) do
      Device.create!(name: 'Session Device', chip_id: 'session_chip', device_info: {}.to_json)
    end

    before do
      user.devices << device
      sign_in user
    end

    it 'accepts an already authenticated web session when no bearer token is provided' do
      get :index, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('success')
      expect(json['devices'].map { |d| d['chip_id'] }).to include('session_chip')
    end
  end
end
