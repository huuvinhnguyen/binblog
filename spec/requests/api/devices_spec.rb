# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API Devices', type: :request do
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
        run_test!
      end
    end
  end
end
