# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API Devices', type: :request do
  let(:user) do
    User.create!(username: "devices_swagger_#{SecureRandom.hex(4)}", password: 'password123',
                 email: "#{SecureRandom.hex(4)}@example.com")
  end
  let(:Authorization) do
    "Bearer #{JWT.encode({ user_id: user.id, exp: 1.hour.from_now.to_i }, Rails.application.secret_key_base, 'HS256')}"
  end
  path '/api/devices' do
    get 'List all devices for the authenticated user' do
      tags 'Devices'
      produces 'application/json'
      security [bearerAuth: []]

      response '200', 'success' do
        schema type: :object,
          properties: {
            status: { type: :string },
            count: { type: :integer },
            devices: {
              type: :array,
              items: {
                type: :object,
                properties: {
                  id: { type: :integer },
                  name: { type: :string },
                  chip_id: { type: :string },
                  device_type: { type: :string, nullable: true },
                  status: { type: :integer, nullable: true },
                  is_payment: { type: :boolean, nullable: true },
                  note: { type: :string, nullable: true },
                  url_firmware: { type: :string, nullable: true },
                  device_info: { type: :object },
                  meta_info: { type: :object },
                  created_at: { type: :string, format: :date_time, nullable: true },
                  updated_at: { type: :string, format: :date_time, nullable: true }
                }
              }
            }
          }

        run_test!
      end

      response '401', 'unauthorized' do
        let(:Authorization) { 'Bearer invalid' }
        run_test!
      end
    end
  end
end
