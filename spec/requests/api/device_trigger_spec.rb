# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Device trigger API', type: :request do
  path '/api/devices/trigger' do
    post 'Publish the configured device trigger through MQTT' do
      tags 'Devices'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        required: %w[chip_id],
        properties: {
          chip_id: {
            type: :string,
            description: 'Chip ID used to find the device whose stored trigger will be published.',
            example: 'ESP32_ABC123'
          }
        }
      }

      response '200', 'trigger message published successfully' do
        let!(:device) do
          Device.create!(
            name: 'Living room device',
            chip_id: 'ESP32_ABC123',
            trigger: {
              chip_id: 'ESP32_ABC123',
              relay_index: 0,
              switch_value: 1
            }.to_json
          )
        end
        let(:payload) { { chip_id: device.chip_id } }
        let(:mqtt_client) { instance_double(MQTT::Client) }

        before do
          allow(MQTT::Client).to receive(:connect).and_return(mqtt_client)
          allow(mqtt_client).to receive(:publish)
          allow(mqtt_client).to receive(:disconnect)
        end

        schema type: :object,
          required: %w[status message],
          properties: {
            status: { type: :string, enum: ['success'], example: 'success' },
            message: { type: :string, example: 'Message sent successfully' }
          }

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(mqtt_client).to have_received(:publish) do |topic, message, options|
            expect(topic).to eq('ESP32_ABC123/switchon')
            expect(JSON.parse(message)).to include(
              'chip_id' => 'ESP32_ABC123',
              'relay_index' => 0,
              'switch_value' => 1,
              'sent_time' => be_a(String)
            )
            expect(options).to eq(retain: false)
          end
          expect(mqtt_client).to have_received(:disconnect)
        end
      end

      response '422', 'stored trigger is not valid JSON' do
        let!(:device) do
          Device.create!(
            name: 'Invalid trigger device',
            chip_id: 'ESP32_INVALID_TRIGGER',
            trigger: '{invalid-json}'
          )
        end
        let(:payload) { { chip_id: device.chip_id } }

        schema type: :object,
          required: %w[status message],
          properties: {
            status: { type: :string, enum: ['error'], example: 'error' },
            message: { type: :string, example: 'Invalid JSON format' }
          }

        run_test!
      end

      response '500', 'device or trigger configuration is invalid' do
        let(:payload) { { chip_id: 'UNKNOWN_DEVICE' } }

        schema type: :object,
          required: %w[status message],
          properties: {
            status: { type: :string, enum: ['error'], example: 'error' },
            message: { type: :string, example: "undefined method `trigger' for nil" }
          }

        run_test!
      end
    end
  end
end
