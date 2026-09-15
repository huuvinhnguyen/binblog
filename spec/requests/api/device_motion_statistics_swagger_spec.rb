# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'PIR motion statistics API documentation', type: :request do
  let(:user) do
    User.create!(
      username: 'pir_swagger_user',
      email: 'pir-swagger@example.com',
      password: 'password123'
    )
  end
  let(:device) do
    Device.create!(chip_id: 'esp8266_14522670', name: 'PIR phòng khách', device_type: 'pir').tap do |pir_device|
      pir_device.users << user
    end
  end
  let(:Authorization) do
    "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
  end

  path '/api/devices/motion_stats' do
    get 'Get hourly motion counts for a PIR device on one date' do
      tags 'PIR devices'
      produces 'application/json'
      security [bearerAuth: []]

      parameter name: :chip_id, in: :query, type: :string, required: true,
                description: 'Chip ID of a PIR device the authenticated user can access.',
                example: 'esp8266_14522670'
      parameter name: :date, in: :query, type: :string, format: :date, required: false,
                description: 'Date to aggregate, in YYYY-MM-DD. Defaults to today in the application time zone.',
                example: '2026-09-15'

      response '200', 'hourly motion statistics' do
        let(:chip_id) { device.chip_id }
        let(:date) { '2026-09-15' }

        schema type: :object,
          required: %w[status date labels values total],
          properties: {
            status: { type: :string, enum: ['success'], example: 'success' },
            date: { type: :string, format: :date, example: '2026-09-15' },
            labels: {
              type: :array,
              minItems: 24,
              maxItems: 24,
              items: { type: :string },
              example: ['00:00', '01:00', '02:00']
            },
            values: {
              type: :array,
              minItems: 24,
              maxItems: 24,
              items: { type: :integer, minimum: 0 },
              example: [0, 1, 3]
            },
            total: { type: :integer, minimum: 0, example: 4 }
          }

        run_test!
      end

      response '401', 'missing or invalid JWT' do
        let(:Authorization) { nil }
        let(:chip_id) { 'esp8266_14522670' }

        schema type: :object,
          required: ['error'],
          properties: { error: { type: :string, example: 'Unauthorized' } }

        run_test!
      end

      response '404', 'PIR device not found or unavailable to the authenticated user' do
        let(:chip_id) { 'unknown_pir_device' }

        schema type: :object,
          required: %w[status message],
          properties: {
            status: { type: :string, enum: ['error'] },
            message: { type: :string, example: 'PIR device not found' }
          }

        run_test!
      end

      response '422', 'invalid date format' do
        let(:chip_id) { device.chip_id }
        let(:date) { '15-09-2026' }

        schema type: :object,
          required: %w[status message],
          properties: {
            status: { type: :string, enum: ['error'] },
            message: { type: :string, example: 'Invalid date. Use YYYY-MM-DD.' }
          }

        run_test!
      end
    end
  end

  path '/api/devices/motion_heatmap' do
    get 'Get daily motion counts for the PIR heatmap' do
      tags 'PIR devices'
      produces 'application/json'
      security [bearerAuth: []]

      parameter name: :chip_id, in: :query, type: :string, required: true,
                description: 'Chip ID of a PIR device the authenticated user can access.',
                example: 'esp8266_14522670'
      parameter name: :days, in: :query, type: :integer, required: false,
                description: 'Number of days ending today. Defaults to 30; accepted range is 1 to 90.',
                minimum: 1, maximum: 90, default: 30, example: 30

      response '200', 'daily motion counts for the heatmap' do
        let(:chip_id) { device.chip_id }
        let(:days) { 30 }

        schema type: :object,
          required: %w[status from to max_count data],
          properties: {
            status: { type: :string, enum: ['success'], example: 'success' },
            from: { type: :string, format: :date, example: '2026-08-17' },
            to: { type: :string, format: :date, example: '2026-09-15' },
            max_count: { type: :integer, minimum: 0, example: 12 },
            data: {
              type: :array,
              items: {
                type: :object,
                required: %w[date count],
                properties: {
                  date: { type: :string, format: :date, example: '2026-09-15' },
                  count: { type: :integer, minimum: 0, example: 4 }
                }
              }
            }
          }

        run_test!
      end

      response '401', 'missing or invalid JWT' do
        let(:Authorization) { nil }
        let(:chip_id) { 'esp8266_14522670' }

        schema type: :object,
          required: ['error'],
          properties: { error: { type: :string, example: 'Unauthorized' } }

        run_test!
      end

      response '404', 'PIR device not found or unavailable to the authenticated user' do
        let(:chip_id) { 'unknown_pir_device' }

        schema type: :object,
          required: %w[status message],
          properties: {
            status: { type: :string, enum: ['error'] },
            message: { type: :string, example: 'PIR device not found' }
          }

        run_test!
      end
    end
  end
end
