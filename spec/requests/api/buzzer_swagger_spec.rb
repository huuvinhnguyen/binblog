# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Buzzer mobile API documentation', type: :request do
  let(:user) do
    User.create!(username: 'buzzer_swagger', email: 'buzzer-swagger@example.com', password: 'password123')
  end
  let(:buzzer) do
    Device.create!(chip_id: 'buzzer_swagger', name: 'Hall Buzzer', device_type: 'buzzer',
                   device_info: { update_at: Time.current.to_i, relays: [{ longlast: 1000 }] }.to_json,
                   meta_info: { last_seen: Time.current.iso8601 }.to_json).tap { |device| device.users << user }
  end
  let(:id) { buzzer.id }
  let(:Authorization) do
    "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
  end
  let(:pir) do
    Device.create!(chip_id: 'pir_swagger', name: 'Hall PIR', device_type: 'pir',
                   trigger: { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }.to_json).tap do |device|
      device.users << user
    end
  end
  let(:event) do
    pir.device_events.create!(event_type: 'motion_detected', occurred_at: 1.minute.ago,
                              payload: { target_chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 })
  end

  # Exercise Rails and the real service without contacting a broker or external cache.
  before do
    allow(MQTT::Client).to receive(:connect).and_return(
      instance_double(MQTT::Client, publish: nil, disconnect: nil)
    )
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

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
            required: %w[id name chip_id device_type online last_seen linked_pir_count last_triggered_at],
            properties: {
              id: { type: :integer, example: 42 },
              name: { type: :string, nullable: true, example: 'Hall Buzzer' },
              chip_id: { type: :string, example: 'ESP32_BUZZER_02' },
              device_type: { type: :string, enum: ['buzzer'] },
              online: { type: :boolean, example: true,
                        description: 'True when device_info.update_at is more recent than five minutes ago.' },
              last_seen: { type: :string, format: 'date-time', nullable: true,
                           description: 'Parsed meta_info.last_seen; null when absent or unparseable.' },
              linked_pir_count: { type: :integer, minimum: 0, example: 2 },
              last_triggered_at: { type: :string, format: 'date-time', nullable: true,
                                   description: 'Latest matching PIR event timestamp; null when there is no matching history.' }
            }
          }
        }

        before { event }

        run_test!

        context 'without timestamps or linked PIRs' do
          let(:event) { nil }
          before { buzzer.update!(meta_info: '{}') }
          run_test! do |response|
            expect(JSON.parse(response.body).fetch('buzzer')).to include(
              'last_seen' => nil, 'last_triggered_at' => nil, 'linked_pir_count' => 0
            )
          end
        end
      end

      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'],
               properties: { error: { type: :string, example: 'Unauthorized' } }

        let(:Authorization) { nil }

        run_test!
      end

      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] },
          message: { type: :string, example: 'Buzzer device not found' }
        }

        let(:id) { 0 }

        run_test!
      end
    end
  end

  path '/api/devices/{id}/buzzer/linked_pirs' do
    get 'List PIR devices linked to a Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'Rails devices.id of an accessible Buzzer device.', example: 42

      response '200', 'linked PIR devices' do
        before { pir }
        schema type: :object, required: %w[status linked_pirs], properties: {
          status: { type: :string, enum: ['success'] },
          linked_pirs: {
            type: :array,
            description: 'Accessible PIRs whose trigger.chip_id matches this Buzzer. Empty array when none match.',
            items: {
              type: :object,
              required: %w[id name chip_id relay_index longlast],
              properties: {
                id: { type: :integer }, name: { type: :string, nullable: true }, chip_id: { type: :string },
                relay_index: { description: 'Stored trigger.relay_index JSON value, without coercion; defaults to 0 when null or false.', example: 0 },
                longlast: { nullable: true, description: 'Stored trigger.longlast JSON value, without coercion; null when absent. Duration in milliseconds.', example: 1000 }
              }
            }
          }
        }

        run_test!

        context 'with no matching records' do
          let(:pir) { nil }
          run_test! do |response|
            expect(JSON.parse(response.body).fetch('linked_pirs')).to eq([])
          end
        end

        context 'with missing configuration values and a nullable PIR name' do
          before { pir.update!(name: nil, trigger: { chip_id: buzzer.chip_id }.to_json) }
          run_test! do |response|
            expect(JSON.parse(response.body).fetch('linked_pirs').first).to include(
              'name' => nil, 'relay_index' => 0, 'longlast' => nil
            )
          end
        end

        context 'with numeric strings in stored configuration' do
          before do
            pir.update!(trigger: { chip_id: buzzer.chip_id, relay_index: '0', longlast: '1000' }.to_json)
          end
          run_test! do |response|
            expect(JSON.parse(response.body).fetch('linked_pirs').first).to include(
              'relay_index' => '0', 'longlast' => '1000'
            )
          end
        end
      end
      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'], properties: { error: { type: :string } }

        let(:Authorization) { nil }

        run_test!
      end
      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string }
        }

        let(:id) { 0 }

        run_test!
      end
    end
  end

  path '/api/devices/{id}/buzzer/history' do
    get 'List recent PIR triggers targeting a Buzzer' do
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'Rails devices.id of an accessible Buzzer device.', example: 42

      response '200', 'latest 20 matching events, newest first' do
        before { event }
        schema type: :object, required: %w[status events], properties: {
          status: { type: :string, enum: ['success'] },
          events: {
            type: :array, maxItems: 20,
            description: 'Latest 20 motion_detected events from accessible linked PIRs with matching payload.target_chip_id, ordered by occurred_at descending then id descending. Empty array when none match; events without target metadata are excluded.',
            items: {
              type: :object, required: %w[id event_type occurred_at pir relay_index longlast], properties: {
                id: { type: :integer }, event_type: { type: :string, enum: ['motion_detected'] },
                occurred_at: { type: :string, format: 'date-time' },
                pir: {
                  type: :object, required: %w[id name chip_id], properties: {
                    id: { type: :integer }, name: { type: :string, nullable: true }, chip_id: { type: :string }
                  }
                },
                relay_index: { nullable: true, description: 'Stored payload.relay_index JSON value, without coercion; null when absent.', example: 0 },
                longlast: { nullable: true, description: 'Stored payload.longlast JSON value, without coercion; null when absent. Duration in milliseconds.', example: 1000 }
              }
            }
          }
        }

        run_test!

        context 'with no matching records' do
          let(:event) { nil }
          run_test! do |response|
            expect(JSON.parse(response.body).fetch('events')).to eq([])
          end
        end

        context 'with absent optional payload fields and a nullable PIR name' do
          before do
            pir.update!(name: nil)
            event.update!(payload: { target_chip_id: buzzer.chip_id })
          end
          run_test! do |response|
            item = JSON.parse(response.body).fetch('events').first
            expect(item).to include('relay_index' => nil, 'longlast' => nil)
            expect(item.fetch('pir')['name']).to be_nil
          end
        end

        context 'with more than 20 events sharing a timestamp' do
          before do
            21.times do
              pir.device_events.create!(event_type: 'motion_detected', occurred_at: event.occurred_at,
                                        payload: { target_chip_id: buzzer.chip_id })
            end
          end
          run_test! do |response|
            ids = JSON.parse(response.body).fetch('events').map { |item| item.fetch('id') }
            expect(ids).to eq(pir.device_events.order(id: :desc).limit(20).pluck(:id))
          end
        end
      end
      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'], properties: { error: { type: :string } }

        let(:Authorization) { nil }

        run_test!
      end
      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string }
        }

        let(:id) { 0 }

        run_test!
      end
    end
  end

  path '/api/devices/{id}/buzzer/test' do
    post 'Send a test command to a Buzzer' do
      description 'Body-less POST using the first configured relay and a three-second per-Buzzer cooldown. Success means Rails completed its existing MQTT publish call and recorded the request. It does not guarantee broker PUBACK or physical-device receipt, activation, or sound.'
      tags 'Buzzer devices'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :id, in: :path, type: :integer, required: true,
                description: 'Rails devices.id of an accessible Buzzer device.', example: 42

      response '200', 'command published by Rails using existing MQTT semantics' do
        schema type: :object, required: %w[status message relay_index longlast], properties: {
          status: { type: :string, enum: ['success'] },
          message: { type: :string, example: 'Command sent to MQTT broker' },
          relay_index: { type: :integer, enum: [0], example: 0 },
          longlast: { type: :integer, minimum: 100, maximum: 10_000, description: 'Configured duration in milliseconds.', example: 1000 }
        }

        run_test!
      end
      response '401', 'missing or invalid JWT' do
        schema type: :object, required: ['error'], properties: { error: { type: :string } }

        let(:Authorization) { nil }

        run_test!
      end
      response '404', 'Buzzer is missing, inaccessible, or not a Buzzer' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string }
        }

        let(:id) { 0 }

        run_test!
      end
      response '422', 'invalid Buzzer configuration' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string }
        }

        before { buzzer.update!(device_info: '{}') }

        run_test!
      end
      response '429', 'test cooldown is active' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string }
        }

        before { Rails.cache.write("buzzer-test:#{buzzer.id}", true) }

        run_test!
      end
      response '503', 'MQTT publish failed' do
        schema type: :object, required: %w[status message], properties: {
          status: { type: :string, enum: ['error'] }, message: { type: :string }
        }

        before { allow(MQTT::Client).to receive(:connect).and_raise(StandardError, 'broker unavailable') }

        run_test!
      end
    end
  end
end
