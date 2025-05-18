
# spec/controllers/api/devices_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::DevicesController, type: :controller do
  describe 'POST #set_longlast' do

    let(:device) do
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
      puts "$body = " + response.body

      device.reload
      device_info = JSON.parse(device.device_info)
      expect(device_info['relays']).to be_present
      # longlast sẽ không trực tiếp lưu trong device_info relays vì set_longlast không update relays,
      # nhưng test này chủ yếu kiểm tra response success và không lỗi khi gọi api.
    end
  end

  describe 'POST #reset_wifi' do
    let(:device_id) { 'ABC123' }
    let(:mqtt_client) { double('MQTT::Client') }

    before do
      # Giả lập phương thức chip_id được gọi trong controller
      # allow(controller).to receive(:device_id).and_return(device_id)

      # Giả lập mqtt_client method
      allow(controller).to receive(:mqtt_client).and_return(mqtt_client)

      # Cho phép publish và disconnect
      allow(mqtt_client).to receive(:publish)
      allow(mqtt_client).to receive(:disconnect)
    end

    it 'publishes MQTT message and returns success JSON' do
      post :reset_wifi,  params: {
        device_id: device_id,
       
      }, format: :json

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['status']).to eq('ok')
      expect(json['topic']).to eq("#{device_id}/reset_wifi")
      expect(json['message']).to be_a(Hash)
      expect(json['message']['action']).to eq('reset_wifi')
      expect(mqtt_client).to have_received(:disconnect)
    end
  end
end
