# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Buzzer mobile API documentation', type: :request do
  path '/api/devices/{id}/buzzer' do
    get 'Get Buzzer details' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]

      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'ID of an accessible Buzzer device.', example: 42

      response '200', 'Buzzer details' do
        schema type: :object, required: %w[status buzzer], properties: {
          status: { type: :string, enum: ['success'] },
          buzzer: {
            type: :object,
            required: %w[id name chip_id device_type online linked_pir_count],
            properties: {
              id: { type: :integer, example: 42 },
              name: { type: :string, example: 'Hall Buzzer' },
              chip_id: { type: :string, example: 'ESP32_BUZZER_02' },
              device_type: { type: :string, enum: ['buzzer'] },
              online: { type: :boolean, example: true },
              last_seen: { type: :string, format: 'date-time', nullable: true },
              linked_pir_count: { type: :integer, minimum: 0, example: 2 },
              last_triggered_at: { type: :string, format: 'date-time', nullable: true }
            }
          }
        }
      end

      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'],
               properties: { error: { type: :string, example: 'Unauthorized' } }
      end

      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] },
          message: { type: :string, example: 'Buzzer device not found' }
        }
      end
    end
  end

  path '/api/devices/{id}/buzzer/linked_pirs' do
    get 'List PIR devices linked to a Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true, example: 42

      response '200', 'linked PIR devices' do
        schema type: :object, required: %w[status linked_pirs], properties: {
          status: { type: :string, enum: ['success'] },
          linked_pirs: {
            type: :array,
            items: {
              type: :object,
              required: %w[id name chip_id relay_index longlast],
              properties: {
                id: { type: :integer }, name: { type: :string }, chip_id: { type: :string },
                relay_index: { type: :integer, minimum: 0 }, longlast: { type: :integer, nullable: true }
              }
            }
          }
        }
      end
      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
      end
      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string }, message: { type: :string }
        }
      end
    end
  end

  path '/api/devices/{id}/buzzer/history' do
    get 'List recent PIR triggers targeting a Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true, example: 42

      response '200', 'latest 20 matching events, newest first' do
        schema type: :object, required: %w[status events], properties: {
          status: { type: :string, enum: ['success'] },
          events: {
            type: :array, maxItems: 20,
            items: {
              type: :object, required: %w[id event_type occurred_at pir], properties: {
                id: { type: :integer }, event_type: { type: :string, enum: ['motion_detected'] },
                occurred_at: { type: :string, format: 'date-time' },
                pir: {
                  type: :object, required: %w[id name chip_id], properties: {
                    id: { type: :integer }, name: { type: :string }, chip_id: { type: :string }
                  }
                },
                relay_index: { type: :integer, nullable: true },
                longlast: { type: :integer, nullable: true }
              }
            }
          }
        }
      end
      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
      end
      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string }, message: { type: :string }
        }
      end
    end
  end

  path '/api/devices/{id}/buzzer/test' do
    post 'Send a test command to a Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true, example: 42

      response '200', 'command accepted by the MQTT broker' do
        schema type: :object, required: %w[status message relay_index longlast], properties: {
          status: { type: :string, enum: ['success'] },
          message: { type: :string, example: 'Command sent to MQTT broker' },
          relay_index: { type: :integer, example: 0 }, longlast: { type: :integer, example: 1000 }
        }
      end
      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
      end
      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string }, message: { type: :string }
        }
      end
      response '422', 'invalid Buzzer configuration' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string }, message: { type: :string }
        }
      end
      response '429', 'test cooldown is active' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string }, message: { type: :string }
        }
      end
      response '503', 'MQTT publish failed' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string }, message: { type: :string }
        }
      end
    end
  end
end
