# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'PIR trigger action API documentation', type: :request do
  let(:user) do
    User.create!(username: "trigger_swagger_#{SecureRandom.hex(3)}",
                 email: "trigger-swagger-#{SecureRandom.hex(3)}@example.com",
                 password: 'password123')
  end
  let(:source) do
    Device.create!(chip_id: "pir_#{SecureRandom.hex(5)}", name: 'Hall PIR', device_type: 'pir').tap do |device|
      device.users << user
    end
  end
  let(:target) do
    Device.create!(chip_id: "buzzer_#{SecureRandom.hex(5)}", name: 'Hall Buzzer', device_type: 'buzzer',
                   device_info: { relays: [{}] }.to_json).tap { |device| device.users << user }
  end
  let(:alternate_target) do
    Device.create!(chip_id: "switch_#{SecureRandom.hex(5)}", name: 'Hall Switch', device_type: 'switch',
                   device_info: { relays: [{}, {}] }.to_json).tap { |device| device.users << user }
  end
  let(:chip_id) { source.chip_id }
  let(:Authorization) do
    "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}"
  end
  let(:action) do
    source.trigger_actions.create!(target_device: target, action_type: 'relay_pulse', relay_index: 0,
                                   duration_ms: 1000, delay_ms: 0, enabled: true, position: 0)
  end
  let(:id) { action.id }

  before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(true) }

  action_schema = {
    type: :object,
    additionalProperties: false,
    required: %w[id origin action_type target relay_index duration_ms delay_ms enabled position],
    properties: {
      id: { type: :integer, nullable: true },
      origin: { type: :string, enum: %w[persisted legacy] },
      action_type: { type: :string, enum: ['relay_pulse'] },
      target: {
        type: :object,
        nullable: true,
        additionalProperties: false,
        required: %w[id chip_id name device_type],
        properties: {
          id: { type: :integer },
          chip_id: { type: :string },
          name: { type: :string, nullable: true },
          device_type: { type: :string, enum: %w[switch buzzer] }
        }
      },
      relay_index: { type: :integer, minimum: 0 },
      duration_ms: { type: :integer, minimum: 100, maximum: 86_400_000 },
      delay_ms: { type: :integer, minimum: 0, maximum: 0 },
      enabled: { type: :boolean },
      position: { type: :integer, minimum: 0 }
    }
  }
  error_schema = {
    type: :object,
    required: %w[status code message],
    properties: {
      status: { type: :string, enum: ['error'] },
      code: {
        type: :string,
        enum: %w[
          source_not_found target_not_found action_not_found feature_disabled
          duplicate_action action_limit_reached configuration_mode_conflict
          legacy_configuration_requires_reconciliation invalid_action_type
          invalid_relay_index invalid_duration invalid_delay invalid_enabled invalid_order
        ]
      },
      message: { type: :string }
    }
  }

  path '/api/devices/{chip_id}/trigger_actions' do
    parameter name: :chip_id, in: :path, type: :string, required: true,
              description: 'Chip ID of an accessible PIR source device.'

    get 'List the effective PIR trigger configuration' do
      tags 'PIR trigger actions'
      produces 'application/json'
      security [bearerAuth: []]

      response '200', 'canonical source configuration and effective actions' do
        schema type: :object, additionalProperties: false,
               required: %w[status configuration_mode source_device actions], properties: {
          status: { type: :string, enum: ['success'] },
          configuration_mode: { type: :string, enum: %w[none legacy actions invalid_legacy] },
          source_device: {
            type: :object,
            additionalProperties: false,
            required: %w[id name chip_id],
            properties: {
              id: { type: :integer }, name: { type: :string, nullable: true }, chip_id: { type: :string }
            }
          },
          actions: { type: :array, items: action_schema }
        }

        context 'with no configuration' do
          run_test! do |response|
            expect(JSON.parse(response.body)).to eq(
              'status' => 'success',
              'configuration_mode' => 'none',
              'source_device' => { 'id' => source.id, 'name' => 'Hall PIR', 'chip_id' => source.chip_id },
              'actions' => []
            )
          end
        end

        context 'with valid legacy configuration' do
          before { source.update!(trigger: { chip_id: target.chip_id, relay_index: 0, longlast: 1000 }.to_json) }
          run_test! do |response|
            expect(JSON.parse(response.body)).to eq(
              'status' => 'success',
              'configuration_mode' => 'legacy',
              'source_device' => { 'id' => source.id, 'name' => 'Hall PIR', 'chip_id' => source.chip_id },
              'actions' => [{
                'id' => nil,
                'origin' => 'legacy',
                'action_type' => 'relay_pulse',
                'target' => {
                  'id' => target.id, 'chip_id' => target.chip_id, 'name' => 'Hall Buzzer',
                  'device_type' => 'buzzer'
                },
                'relay_index' => 0,
                'duration_ms' => 1000,
                'delay_ms' => 0,
                'enabled' => true,
                'position' => 0
              }]
            )
          end
        end

        context 'with persisted actions' do
          before { action }
          run_test! do |response|
            expect(JSON.parse(response.body)).to eq(
              'status' => 'success',
              'configuration_mode' => 'actions',
              'source_device' => { 'id' => source.id, 'name' => 'Hall PIR', 'chip_id' => source.chip_id },
              'actions' => [{
                'id' => action.id,
                'origin' => 'persisted',
                'action_type' => 'relay_pulse',
                'target' => {
                  'id' => target.id, 'chip_id' => target.chip_id, 'name' => 'Hall Buzzer',
                  'device_type' => 'buzzer'
                },
                'relay_index' => 0,
                'duration_ms' => 1000,
                'delay_ms' => 0,
                'enabled' => true,
                'position' => 0
              }]
            )
          end
        end

        context 'with invalid legacy configuration' do
          before { source.update!(trigger: '{bad') }
          run_test! do |response|
            expect(JSON.parse(response.body)).to eq(
              'status' => 'success',
              'configuration_mode' => 'invalid_legacy',
              'source_device' => { 'id' => source.id, 'name' => 'Hall PIR', 'chip_id' => source.chip_id },
              'actions' => []
            )
          end
        end
      end

      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source missing or inaccessible' do
        let(:chip_id) { 'missing' }
        schema error_schema
        run_test!
      end

      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end

    post 'Create a relay pulse action' do
      tags 'PIR trigger actions'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[target_device_id action_type relay_index duration_ms],
        properties: {
          target_device_id: { type: :integer },
          action_type: { type: :string, enum: ['relay_pulse'] },
          relay_index: { type: :integer, minimum: 0 },
          duration_ms: { type: :integer },
          delay_ms: { type: :integer, minimum: 0, maximum: 0, default: 0 },
          enabled: { type: :boolean, default: true }
        }
      }
      let(:body) do
        { target_device_id: target.id, action_type: 'relay_pulse', relay_index: 0,
          duration_ms: 1000, delay_ms: 0, enabled: true }
      end

      response '201', 'action created' do
        schema type: :object, required: %w[status action], properties: {
          status: { type: :string, enum: ['success'] }, action: action_schema
        }
        run_test!
      end

      response '409', 'legacy configuration or duplicate action conflicts with creation' do
        before { source.update!(trigger: { chip_id: target.chip_id, relay_index: 0, longlast: 1000 }.to_json) }
        schema error_schema
        run_test!
      end

      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source or target is missing, inaccessible, or ineligible' do
        let(:chip_id) { 'missing' }
        schema error_schema
        run_test!
      end

      response '422', 'relay, duration, delay, or action validation failed' do
        let(:body) { super().merge(relay_index: 99) }
        schema error_schema
        run_test!
      end


      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end
  end

  path '/api/devices/{chip_id}/trigger_actions/targets' do
    get 'List accessible supported target devices' do
      tags 'PIR trigger actions'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :chip_id, in: :path, type: :string, required: true

      response '200', 'supported targets and relay indexes' do
        before { target }
        schema type: :object, additionalProperties: false, required: %w[status targets], properties: {
          status: { type: :string, enum: ['success'] },
          targets: {
            type: :array,
            items: {
              type: :object, additionalProperties: false,
              required: %w[id chip_id name device_type relay_indexes duration_ms],
              properties: {
                id: { type: :integer }, chip_id: { type: :string }, name: { type: :string, nullable: true },
                device_type: { type: :string, enum: %w[switch buzzer] },
                relay_indexes: { type: :array, items: { type: :integer } },
                duration_ms: {
                  type: :object,
                  additionalProperties: false,
                  required: %w[minimum maximum],
                  properties: { minimum: { type: :integer }, maximum: { type: :integer } }
                }
              }
            }
          }
        }
        run_test! do |response|
          expect(JSON.parse(response.body)).to eq(
            'status' => 'success',
            'targets' => [{
              'id' => target.id,
              'chip_id' => target.chip_id,
              'name' => 'Hall Buzzer',
              'device_type' => 'buzzer',
              'relay_indexes' => [0],
              'duration_ms' => { 'minimum' => 100, 'maximum' => 10_000 }
            }]
          )
        end
      end


      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source is missing, inaccessible, or wrong type' do
        let(:chip_id) { 'missing' }
        schema error_schema
        run_test!
      end

      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end
  end

  path '/api/devices/{chip_id}/trigger_actions/{id}' do
    parameter name: :chip_id, in: :path, type: :string, required: true
    parameter name: :id, in: :path, type: :integer, required: true

    put 'Update a trigger action' do
      tags 'PIR trigger actions'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :body, in: :body, required: true,
                schema: {
                  type: :object,
                  properties: {
                    target_device_id: { type: :integer },
                    action_type: { type: :string, enum: ['relay_pulse'] },
                    relay_index: { type: :integer, minimum: 0 },
                    duration_ms: { type: :integer },
                    delay_ms: { type: :integer, minimum: 0, maximum: 0 },
                    enabled: { type: :boolean }
                  }
                }
      let(:body) do
        { target_device_id: alternate_target.id, action_type: 'relay_pulse', relay_index: 1,
          duration_ms: 2000, delay_ms: 0, enabled: false }
      end

      response '200', 'action updated' do
        schema type: :object, required: %w[status action], properties: {
          status: { type: :string, enum: ['success'] }, action: action_schema
        }
        run_test!
      end


      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source, target, or action is missing or inaccessible' do
        let(:id) { 0 }
        schema error_schema
        run_test!
      end

      response '409', 'updated action duplicates another persisted action' do
        before do
          source.trigger_actions.create!(target_device: alternate_target, action_type: 'relay_pulse', relay_index: 0,
                                         duration_ms: 1000, delay_ms: 0, enabled: true, position: 1)
        end
        schema error_schema
        run_test!
      end

      response '422', 'updated action fields fail validation' do
        let(:body) { { duration_ms: 1 } }
        schema error_schema
        run_test!
      end

      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end

    delete 'Delete a trigger action' do
      tags 'PIR trigger actions'
      produces 'application/json'
      security [bearerAuth: []]

      response '200', 'action deleted' do
        schema type: :object, required: %w[status action_id], properties: {
          status: { type: :string, enum: ['success'] }, action_id: { type: :integer }
        }
        run_test!
      end


      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source or action is missing or inaccessible' do
        let(:id) { 0 }
        schema error_schema
        run_test!
      end

      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end
  end

  path '/api/devices/{chip_id}/trigger_actions/order' do
    put 'Replace the complete action order' do
      tags 'PIR trigger actions'
      consumes 'application/json'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :chip_id, in: :path, type: :string, required: true
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: ['action_ids'],
        properties: { action_ids: { type: :array, items: { type: :integer } } }
      }
      let(:body) { { action_ids: [action.id] } }

      response '200', 'actions reordered' do
        schema type: :object, required: %w[status actions], properties: {
          status: { type: :string, enum: ['success'] }, actions: { type: :array, items: action_schema }
        }
        run_test!
      end

      response '422', 'the submitted IDs are not the exact current set' do
        let(:body) { { action_ids: [] } }
        before { action }
        schema error_schema
        run_test!
      end


      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source is missing, inaccessible, or wrong type' do
        let(:chip_id) { 'missing' }
        schema error_schema
        run_test!
      end

      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end
  end

  path '/api/devices/{chip_id}/trigger_actions/migrate_legacy' do
    post 'Explicitly migrate one valid legacy trigger' do
      tags 'PIR trigger actions'
      produces 'application/json'
      security [bearerAuth: []]
      parameter name: :chip_id, in: :path, type: :string, required: true

      response '200', 'legacy configuration migrated or already migrated' do
        before { source.update!(trigger: { chip_id: target.chip_id, relay_index: 0, longlast: 1000 }.to_json) }
        schema type: :object, required: %w[status migrated mode action], properties: {
          status: { type: :string, enum: ['success'] },
          migrated: { type: :boolean },
          mode: { type: :string, enum: ['actions'] },
          action: action_schema
        }
        run_test!
      end

      response '409', 'legacy configuration requires reconciliation or conflicts with actions' do
        before { source.update!(trigger: '{bad') }
        schema error_schema
        run_test!
      end


      response '401', 'authentication required' do
        let(:Authorization) { nil }
        schema type: :object, required: ['error'], properties: { error: { type: :string } }
        run_test!
      end

      response '404', 'source or eligible legacy target is unavailable' do
        let(:chip_id) { 'missing' }
        schema error_schema
        run_test!
      end

      response '503', 'trigger action management is disabled by rollout flag' do
        before { allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false) }
        schema error_schema
        run_test!
      end
    end
  end
end
