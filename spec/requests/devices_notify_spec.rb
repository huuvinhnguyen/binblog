# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Device notification webhook', type: :request do
  path '/devices/notify' do
    post 'Send a device notification to Slack' do
      tags 'Devices Webhook'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :payload, in: :body, required: true, schema: {
        type: :object,
        required: %w[id message],
        properties: {
          id: {
            type: :string,
            description: 'The device chip ID.',
            example: 'ESP32_ABC123'
          },
          message: {
            type: :string,
            description: 'Notification text sent to Slack.',
            example: 'Relay 1 đã bật'
          },
          model: {
            type: :string,
            description: 'Device model.',
            example: 'ESP32'
          },
          relay_state: {
            type: :integer,
            description: 'Relay state reported by the device (0 = off, 1 = on).',
            enum: [0, 1],
            example: 1
          },
          relay_index: {
            type: :integer,
            description: 'Zero-based relay index.',
            minimum: 0,
            example: 0
          },
          name: {
            type: :string,
            description: 'Device name used when the device is first registered.',
            example: 'Thiết bị phòng khách'
          }
        }
      }

      response '200', 'notification received' do
        let!(:device) do
          Device.create!(
            name: 'Living room device',
            chip_id: 'ESP32_ABC123',
            device_info: {}.to_json
          )
        end
        let!(:user) do
          User.create!(
            username: 'notify_user',
            email: 'notify@example.com',
            password: 'password123',
            webhook_url: 'https://hooks.slack.com/services/test'
          )
        end
        let(:payload) do
          {
            id: device.chip_id,
            message: 'Relay 1 đã bật',
            model: 'ESP32',
            relay_state: 1,
            relay_index: 0,
            name: device.name
          }
        end

        before do
          device.users << user
          allow_any_instance_of(SlackNotificationService)
            .to receive(:send_notification).and_return(true)
        end

        schema type: :object,
          required: %w[message status],
          properties: {
            message: { type: :string, example: 'Notification sent to Slack' },
            status: { type: :string, enum: %w[success failure], example: 'success' }
          }

        run_test!
      end

    end
  end
end
