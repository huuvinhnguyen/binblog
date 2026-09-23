require 'swagger_helper'

RSpec.describe 'Buzzer PIR management API documentation', type: :request do
  let(:user) { User.create!(username: 'links_swagger', email: 'links_swagger@example.com', password: 'password123') }
  let(:buzzer) do
    Device.create!(chip_id: 'links_buzzer', device_type: 'buzzer', name: 'Hall Buzzer').tap { |device| device.users << user }
  end
  let(:pir) do
    Device.create!(chip_id: 'links_pir', device_type: 'pir').tap { |device| device.users << user }
  end
  let(:id) { buzzer.id }
  let(:pir_id) { pir.id }
  let(:Authorization) do
    "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
  end

  before do
    expect(MQTT::Client).not_to receive(:connect)
    expect_any_instance_of(MQTT::Client).not_to receive(:publish)
    expect(BuzzerTestService).not_to receive(:new)
  end

  path '/api/devices/{id}/buzzer/available_pirs' do
    get 'List accessible PIRs for linking or moving to this Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'Rails ID of an accessible Buzzer.'
      description 'Returns accessible PIRs ordered by ID, including already linked PIRs. linked_buzzer contains only an accessible current Buzzer ID and name; otherwise null. requires_confirmation indicates an existing configuration that would be replaced. Clients should show Move & Link for a different visible Buzzer, or a generic replace-configuration confirmation when its identity is unavailable. POST performs the replacement; this flag is advisory, not a confirmation token.'

      response '200', 'available PIRs; empty array when none are accessible' do
        schema type: :object, required: %w[status available_pirs], properties: {
          status: { type: :string, enum: ['success'] },
          available_pirs: {
            type: :array, items: {
              type: :object, required: %w[id name chip_id linked_buzzer requires_confirmation], properties: {
                id: { type: :integer }, name: { type: :string, nullable: true }, chip_id: { type: :string },
                linked_buzzer: {
                  type: :object, nullable: true, required: %w[id name], properties: {
                    id: { type: :integer }, name: { type: :string, nullable: true }
                  }
                },
                requires_confirmation: { type: :boolean }
              }
            }
          }
        }
        before { pir }
        run_test!

        context 'with an accessible current Buzzer' do
          before { pir.update!(trigger: { chip_id: buzzer.chip_id }.to_json) }
          run_test!
        end
        context 'without PIRs' do
          let(:pir) { nil }
          run_test! do |response|
            expect(JSON.parse(response.body)['available_pirs']).to eq([])
          end
        end
      end
      response '401', 'missing or invalid authentication' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string, example: 'Unauthorized' } }
        run_test!
      end
      response '404', 'missing, inaccessible, or non-Buzzer target' do
        let(:id) { 0 }
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string, example: 'Buzzer device not found' }
        }
        run_test!
      end
    end
  end

  path '/api/devices/{id}/buzzer/linked_pirs' do
    post 'Link or move an accessible PIR to this Buzzer' do
      tags 'Buzzer devices'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      description 'Configuration only: replaces the PIR trigger with chip_id, relay_index and longlast. Repeating the same request produces the same state. Existing configuration is replaced, including malformed JSON. Does not connect to MQTT, test, or sound the Buzzer.'
      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'Rails ID of an accessible Buzzer.'
      parameter name: :payload, in: :body, required: true, schema: {
        type: :object, required: %w[pir_id relay_index longlast], properties: {
          pir_id: { type: :integer, minimum: 1, example: 7 },
          relay_index: { type: :integer, minimum: 0, example: 0 },
          longlast: { type: :integer, minimum: 100, maximum: 10_000, example: 1000, description: 'Duration in milliseconds.' }
        }
      }
      let(:payload) { { pir_id: pir.id, relay_index: 0, longlast: 1000 } }

      response '200', 'PIR linked with normalized configuration' do
        schema type: :object, required: %w[status linked_pir], properties: {
          status: { type: :string, enum: ['success'] },
          linked_pir: {
            type: :object, required: %w[id name chip_id relay_index longlast], properties: {
              id: { type: :integer }, name: { type: :string, nullable: true }, chip_id: { type: :string },
              relay_index: { type: :integer, minimum: 0 },
              longlast: { type: :integer, minimum: 100, maximum: 10_000 }
            }
          }
        }
        run_test!
      end
      response '401', 'missing or invalid authentication' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string, example: 'Unauthorized' } }
        run_test!
      end
      response '404', 'Buzzer or PIR is missing, inaccessible, or the wrong device type' do
        let(:payload) { { pir_id: 2_000_000_000, relay_index: 0, longlast: 1000 } }
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string, example: 'PIR device not found' }
        }
        run_test!
      end
      response '422', 'missing or invalid pir_id, relay_index, or longlast; JSON integers required' do
        let(:payload) { { pir_id: pir.id, relay_index: 0, longlast: 99 } }
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] },
          message: { type: :string, example: 'longlast must be an integer between 100 and 10000 ms.' }
        }
        run_test!
      end
    end
  end

  path '/api/devices/{id}/buzzer/linked_pirs/{pir_id}' do
    delete 'Unlink an accessible PIR from this Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'Rails ID of an accessible Buzzer.'
      parameter name: :pir_id, in: :path, type: :integer, required: true,
                description: 'Rails ID of an accessible PIR.'
      description 'Body-less, configuration-only operation. Removes command fields only if the stored target matches this Buzzer, retaining other metadata. Repeated unlink, another target, missing configuration, and malformed existing JSON are successful no-ops. A normalized link becomes {}. Never connects to MQTT or tests the Buzzer.'

      response '200', 'PIR is no longer linked to this Buzzer, or no matching configuration was found' do
        before { pir.update!(trigger: { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }.to_json) }
        schema type: :object, required: %w[status pir_id], properties: {
          status: { type: :string, enum: ['success'] }, pir_id: { type: :integer }
        }
        run_test!
      end
      response '401', 'missing or invalid authentication' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string, example: 'Unauthorized' } }
        run_test!
      end
      response '404', 'Buzzer or PIR is missing, inaccessible, or the wrong device type; invalid path PIR ID' do
        let(:pir_id) { 0 }
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string, example: 'PIR device not found' }
        }
        run_test!
      end
    end
  end
end
