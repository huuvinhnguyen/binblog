require 'swagger_helper'

RSpec.describe 'Switch facade OpenAPI', type: :request do
  let(:user) { User.create!(username: "switch_doc_#{SecureRandom.hex(4)}", password: 'password123', email: "#{SecureRandom.hex(4)}@example.com") }
  let(:device) do
    Device.create!(name: 'Switch', chip_id: "switch_doc_#{SecureRandom.hex(4)}", device_type: 'switch',
                   device_info: { relays: [{ switch_value: 0, longlast: 1000, is_reminders_active: true }] }.to_json)
          .tap { |row| row.users << user }
  end
  let(:id) { device.id.to_s }
  let(:relay_index) { '0' }
  let(:reminder_id) { '123' }
  let(:Authorization) { "Bearer #{JWT.encode({ user_id: user.id, exp: 1.hour.from_now.to_i }, Rails.application.secret_key_base, 'HS256')}" }

  before do
    allow(SwitchApi::Features).to receive(:enabled?).and_return(true)
    allow(SwitchApi::Publisher).to receive(:new).and_return(instance_double(SwitchApi::Publisher, call: nil))
  end

  error_schema = {
    type: :object, required: %w[status code request_id], additionalProperties: false,
    properties: { status: { type: :string, enum: ['error'] }, code: { type: :string },
                  request_id: { type: :string }, outcome: { type: :string, enum: %w[not_attempted unknown] } }
  }
  command_schema = {
    type: :object, additionalProperties: false,
    required: %w[status outcome acknowledgement request_id event_id],
    properties: { status: { type: :string, enum: ['accepted'] }, outcome: { type: :string, enum: ['publish_returned'] },
                  acknowledgement: { type: :string, enum: ['none'] }, request_id: { type: :string }, event_id: { type: :string } }
  }
  relay_schema = {
    type: :object, required: %w[index switch_value duration_ms reminders_active], additionalProperties: false,
    properties: { index: { type: :integer, minimum: 0 }, switch_value: { type: :integer, nullable: true, enum: [0, 1, nil] },
                  duration_ms: { type: :integer, nullable: true }, reminders_active: { type: :boolean, nullable: true } }
  }
  reminder_schema = {
    type: :object, additionalProperties: false,
    required: %w[id device_id relay_index start_time duration_ms repeat_type enabled configuration_valid],
    properties: { id: { type: :string }, device_id: { type: :string }, relay_index: { type: :integer },
                  start_time: { type: :string, format: :'date-time', nullable: true }, duration_ms: { type: :integer, nullable: true },
                  repeat_type: { type: :string }, enabled: { type: :boolean }, configuration_valid: { type: :boolean } }
  }
  detail_schema = {
    type: :object, required: %w[status switch server_time], additionalProperties: false,
    properties: {
      status: { type: :string, enum: ['success'] }, server_time: { type: :string, format: :'date-time' },
      switch: {
        type: :object, additionalProperties: false,
        required: %w[id chip_id name device_type timezone last_seen online state_source physical_state_verified capabilities limits relays],
        properties: {
          id: { type: :string }, chip_id: { type: :string }, name: { type: :string },
          device_type: { type: :string, enum: ['switch'] }, timezone: { type: :string, enum: ['Asia/Ho_Chi_Minh'] },
          last_seen: { type: :string, format: :'date-time', nullable: true }, online: { type: :boolean, nullable: true },
          state_source: { type: :string, enum: ['server_snapshot'] }, physical_state_verified: { type: :boolean, enum: [false] },
          capabilities: { type: :object, additionalProperties: false, required: %w[manual_switch pulse reminders statistics refresh],
                          properties: %i[manual_switch pulse reminders statistics refresh].to_h { |key| [key, { type: :boolean }] } },
          limits: { type: :object, required: %w[duration_min_ms duration_max_ms reminder_limit_per_relay],
                    properties: { duration_min_ms: { type: :integer, enum: [1000] }, duration_max_ms: { type: :integer, enum: [86_400_000] },
                                  reminder_limit_per_relay: { type: :integer, enum: [100] } } },
          relays: { type: :array, maxItems: 32, items: relay_schema }
        }
      }
    }
  }
  statistics_schema = {
    type: :object, additionalProperties: false,
    required: %w[status timezone from to metric total_records days physical_runtime_seconds physical_runtime_verified],
    properties: {
      status: { type: :string, enum: ['success'] }, timezone: { type: :string },
      from: { type: :string, format: :date }, to: { type: :string, format: :date },
      metric: { type: :string, enum: ['log_records'] }, total_records: { type: :integer, minimum: 0 },
      days: { type: :array, minItems: 1, maxItems: 31, items: { type: :object, required: %w[date count],
              properties: { date: { type: :string, format: :date }, count: { type: :integer, minimum: 0 } } } },
      physical_runtime_seconds: { type: :integer, nullable: true }, physical_runtime_verified: { type: :boolean, enum: [false] }
    }
  }
  reminder_list_schema = {
    type: :object, additionalProperties: false, required: %w[status reminders next_after_id],
    properties: { status: { type: :string, enum: ['success'] }, reminders: { type: :array, maxItems: 100, items: reminder_schema },
                  next_after_id: { type: :string, nullable: true } }
  }

  [
    ['/api/switches/{id}', 'Read switch snapshot (not confirmed hardware state)', detail_schema],
    ['/api/switches/{id}/relays/{relay_index}/reminders', 'Read persisted reminders; writes remain disabled', reminder_list_schema],
    ['/api/switches/{id}/relays/{relay_index}/statistics', 'Count persisted relay log records (not physical runtime)', statistics_schema]
  ].each do |route, summary, success_schema|
    path route do
      parameter name: :id, in: :path, type: :string, required: true, description: 'Database Device ID, not chip_id.'
      if route.include?('{relay_index}')
        parameter name: :relay_index, in: :path, type: :integer, minimum: 0, required: true
      end
      get summary do
        tags 'Switches'
        produces 'application/json'
        security [bearerAuth: []]
        if route.end_with?('/statistics')
          parameter name: :from, in: :query, type: :string, format: :date, required: false,
                    description: 'Inclusive +07 local date; provide both from/to, maximum 31 days, no future dates.'
          parameter name: :to, in: :query, type: :string, format: :date, required: false
        elsif route.end_with?('/reminders')
          parameter name: :after_id, in: :query, type: :string, required: false
          parameter name: :limit, in: :query, type: :integer, minimum: 1, maximum: 100, required: false
        end
        response '200', 'success (Cache-Control: no-store)' do
          schema success_schema
          run_test!
        end
        response '401', 'Bearer authentication required; no session fallback' do
          schema error_schema
          let(:Authorization) { 'Bearer invalid' }
          run_test!
        end
        response '404', 'Switch inaccessible, missing or wrong type' do
          schema error_schema
          let(:id) { '999999999' }
          run_test!
        end
        response '503', 'Facade disabled by default' do
          schema error_schema
          before { allow(SwitchApi::Features).to receive(:enabled?).and_return(false) }
          run_test!
        end
        response '422', 'Invalid stored configuration or request parameters' do
          schema error_schema
          before { device.update!(device_info: '{}') }
          run_test!
        end
      end
    end
  end

  [
    ['/api/switches/{id}/relays/{relay_index}/state', { switch_value: { type: :integer, enum: [0, 1] } }, { switch_value: 1 }],
    ['/api/switches/{id}/relays/{relay_index}/pulse', { duration_ms: { type: :integer, minimum: 1000, maximum: 86_400_000, multipleOf: 1000 } }, { duration_ms: 1000 }],
    ['/api/switches/{id}/refresh', {}, {}]
  ].each do |route, fields, valid_body|
    path route do
      parameter name: :id, in: :path, type: :string, required: true
      parameter name: :relay_index, in: :path, type: :integer, required: true if route.include?('{relay_index}')
      post 'Send a new command intent; never automatically retry on timeout' do
        tags 'Switches'
        consumes 'application/json'
        produces 'application/json'
        security [bearerAuth: []]
        parameter name: :input, in: :body, required: !fields.empty?, schema: {
          type: :object, additionalProperties: false, required: fields.keys.map(&:to_s), properties: fields
        }
        let(:input) { valid_body }
        response '200', 'Publish call returned; no broker or physical ACK' do
          schema command_schema
          run_test!
        end
        response '401', 'Authentication required' do
          schema error_schema
          let(:Authorization) { 'Bearer invalid' }
          run_test!
        end
        response '404', 'Switch inaccessible, missing or wrong type' do
          schema error_schema
          let(:id) { '999999999' }
          run_test!
        end
        response '422', 'Invalid input; no side effect' do
          schema error_schema
          let(:input) { { unknown: true } }
          run_test!
        end
        response '400', 'Malformed JSON' do
          schema error_schema
          it 'returns a JSON error for malformed bytes' do
            url = route.gsub('{id}', id).gsub('{relay_index}', relay_index)
            post url, params: '{', headers: { 'Authorization' => self.Authorization, 'Accept' => 'application/json',
                                             'Content-Type' => 'application/json' }
            expect(response.status).to eq(400)
            expect(JSON.parse(response.body)['code']).to eq('malformed_json')
          end
        end
        response '415', 'Nonempty body requires application/json' do
          schema error_schema
          it 'rejects form content on the JSON facade' do
            url = route.gsub('{id}', id).gsub('{relay_index}', relay_index)
            post url, params: 'value=1', headers: { 'Authorization' => self.Authorization, 'Accept' => 'application/json',
                                                  'Content-Type' => 'application/x-www-form-urlencoded' }
            expect(response.status).to eq(415)
          end
        end
        response '502', 'Publish outcome unknown; no automatic replay' do
          schema error_schema
          before { allow_any_instance_of(SwitchCommandService).to receive(:call).and_raise(SwitchApi::Error.new('command_outcome_unknown', status: :bad_gateway, outcome: 'unknown')) }
          run_test!
        end
        response '503', 'Dependency unavailable before publish' do
          schema error_schema
          before { allow_any_instance_of(SwitchCommandService).to receive(:call).and_raise(SwitchApi::Error.new('command_unavailable', status: :service_unavailable, outcome: 'not_attempted')) }
          run_test!
        end
      end
    end
  end

  [[:post, '/api/switches/{id}/relays/{relay_index}/reminders'],
   [:delete, '/api/switches/{id}/relays/{relay_index}/reminders/{reminder_id}'],
   [:put, '/api/switches/{id}/relays/{relay_index}/reminders-active']].each do |verb, route|
    path route do
      parameter name: :id, in: :path, type: :string, required: true
      parameter name: :relay_index, in: :path, type: :integer, required: true
      parameter name: :reminder_id, in: :path, type: :string, required: true if verb == :delete
      public_send(verb, 'Reminder write reserved; execution-owner gate unresolved, no writes performed') do
        tags 'Switches'
        consumes 'application/json'
        produces 'application/json'
        security [bearerAuth: []]
        if verb != :delete
          parameter name: :input, in: :body, required: true, schema: { type: :object }
          let(:input) { {} }
        end
        response '503', 'Reminder execution unavailable (writes remain hard-disabled)' do
          schema error_schema
          run_test!
        end
        response '403', 'Reminder capability explicitly denied' do
          schema error_schema
          before { UserRelayFeature.create!(device: device, user: user, feature: 'reminder', enabled: false) }
          run_test!
        end
      end
    end
  end
end
