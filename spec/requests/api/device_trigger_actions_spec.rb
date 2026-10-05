require 'rails_helper'

RSpec.describe 'Device trigger action management', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) do
    User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
  end
  let(:headers) do
    token = JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)
    { 'Authorization' => "Bearer #{token}" }
  end
  let(:source) { device('pir') }
  let(:buzzer) { device('buzzer', device_info: { relays: [{}] }.to_json) }
  let(:switch) { device('switch', device_info: { relays: [{}, {}] }.to_json) }
  let(:base_path) { "/api/devices/#{source.chip_id}/trigger_actions" }
  let(:valid_payload) do
    { target_device_id: buzzer.id, action_type: 'relay_pulse', relay_index: 0,
      duration_ms: 1000, delay_ms: 0, enabled: true }
  end

  def device(type, owned: true, owner: user, **attributes)
    Device.create!({ chip_id: SecureRandom.hex(8), name: type, device_type: type }.merge(attributes)).tap do |record|
      record.users << owner if owned
    end
  end

  def json
    JSON.parse(response.body)
  end

  def persisted_action(target: buzzer, position: 0, **attributes)
    source.trigger_actions.create!({
      target_device: target,
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 1000,
      delay_ms: 0,
      enabled: true,
      position: position
    }.merge(attributes))
  end

  before do
    allow(DeviceTriggerFeature).to receive(:enabled?).and_return(true)
  end

  it 'requires a current bearer JWT and preserves the existing Unauthorized response' do
    get base_path
    expect(response).to have_http_status(:unauthorized)
    expect(json).to eq('error' => 'Unauthorized')

    get base_path, headers: { 'Authorization' => 'Bearer invalid' }
    expect(response).to have_http_status(:unauthorized)
    expect(json).to eq('error' => 'Unauthorized')
  end

  it 'accepts Devise session authority and serializes none mode canonically' do
    sign_in user
    get base_path

    expect(response).to have_http_status(:ok)
    expect(json).to eq(
      'status' => 'success',
      'configuration_mode' => 'none',
      'source_device' => { 'id' => source.id, 'name' => source.name, 'chip_id' => source.chip_id },
      'actions' => []
    )
  end

  it 'serializes legacy mode as one read-only virtual action in the shared actions array' do
    source.update!(trigger: { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }.to_json)

    get base_path, headers: headers

    expect(json).to eq(
      'status' => 'success',
      'configuration_mode' => 'legacy',
      'source_device' => { 'id' => source.id, 'name' => source.name, 'chip_id' => source.chip_id },
      'actions' => [{
        'id' => nil,
        'origin' => 'legacy',
        'action_type' => 'relay_pulse',
        'target' => {
          'id' => buzzer.id, 'name' => buzzer.name, 'chip_id' => buzzer.chip_id, 'device_type' => 'buzzer'
        },
        'relay_index' => 0,
        'duration_ms' => 1000,
        'delay_ms' => 0,
        'enabled' => true,
        'position' => 0
      }]
    )
  end

  it 'serializes invalid legacy mode without exposing an action' do
    source.update!(trigger: '{bad')

    get base_path, headers: headers

    expect(response).to have_http_status(:ok)
    expect(json).to eq(
      'status' => 'success',
      'configuration_mode' => 'invalid_legacy',
      'source_device' => { 'id' => source.id, 'name' => source.name, 'chip_id' => source.chip_id },
      'actions' => []
    )
  end

  it 'serializes persisted actions canonically and hides a target after access is lost' do
    action = persisted_action

    get base_path, headers: headers
    expected_action = {
      'id' => action.id,
      'origin' => 'persisted',
      'action_type' => 'relay_pulse',
      'target' => {
        'id' => buzzer.id, 'name' => buzzer.name, 'chip_id' => buzzer.chip_id, 'device_type' => 'buzzer'
      },
      'relay_index' => 0,
      'duration_ms' => 1000,
      'delay_ms' => 0,
      'enabled' => true,
      'position' => 0
    }
    expect(json).to eq(
      'status' => 'success',
      'configuration_mode' => 'actions',
      'source_device' => { 'id' => source.id, 'name' => source.name, 'chip_id' => source.chip_id },
      'actions' => [expected_action]
    )

    buzzer.users.delete(user)
    get base_path, headers: headers
    expect(json).to eq(
      'status' => 'success',
      'configuration_mode' => 'actions',
      'source_device' => { 'id' => source.id, 'name' => source.name, 'chip_id' => source.chip_id },
      'actions' => [expected_action.merge('target' => nil)]
    )
    expect(response.body).not_to include(buzzer.chip_id, buzzer.name)
  end

  it 'does not disclose an inaccessible legacy target identity' do
    foreign = device('buzzer', owned: false, device_info: { relays: [{}] }.to_json)
    source.update!(trigger: { chip_id: foreign.chip_id, relay_index: 0, longlast: 1000 }.to_json)

    get base_path, headers: headers

    expect(json).to include('configuration_mode' => 'legacy')
    expect(json.dig('actions', 0, 'target')).to be_nil
    expect(response.body).not_to include(foreign.chip_id, foreign.name)
  end

  it 'lists only eligible targets with relay indexes and type-specific duration constraints' do
    foreign = device('buzzer', owned: false, device_info: { relays: [{}] }.to_json)
    buzzer
    switch

    get "#{base_path}/targets", headers: headers

    expect(response).to have_http_status(:ok)
    expected_targets = [
      {
        'id' => buzzer.id, 'chip_id' => buzzer.chip_id, 'name' => buzzer.name, 'device_type' => 'buzzer',
        'relay_indexes' => [0], 'duration_ms' => { 'minimum' => 100, 'maximum' => 10_000 }
      },
      {
        'id' => switch.id, 'chip_id' => switch.chip_id, 'name' => switch.name, 'device_type' => 'switch',
        'relay_indexes' => [0, 1], 'duration_ms' => { 'minimum' => 100, 'maximum' => 86_400_000 }
      }
    ].sort_by { |row| row.fetch('id') }
    expect(json).to eq(
      'status' => 'success',
      'targets' => expected_targets
    )
    expect(response.body).not_to include(foreign.chip_id)
  end

  it 'keeps admin target eligibility aligned with the shared-owner runtime rule' do
    admin = User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
    admin.add_role(:admin)
    owner = User.create!(username: SecureRandom.hex(6), email: "#{SecureRandom.hex(5)}@example.com", password: 'password123')
    admin_source = device('pir', owner: owner)
    same_owner = device('buzzer', owner: owner, device_info: { relays: [{}] }.to_json)
    cross_owner = device('buzzer', owned: false, device_info: { relays: [{}] }.to_json)
    token = JWT.encode({ user_id: admin.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)

    get "/api/devices/#{admin_source.chip_id}/trigger_actions/targets",
        headers: { 'Authorization' => "Bearer #{token}" }

    ids = json.fetch('targets').map { |row| row.fetch('id') }
    expect(ids).to include(same_owner.id)
    expect(ids).not_to include(cross_owner.id)
  end

  it 'creates with server position, updates every supported field, reorders, and deletes without MQTT' do
    expect(MQTT::Client).not_to receive(:connect)
    persisted_action(position: 0)

    post base_path, params: valid_payload.merge(target_device_id: switch.id, relay_index: 1, position: 99),
         headers: headers, as: :json
    expect(response).to have_http_status(:created)
    action_id = json.dig('action', 'id')
    expect(json.dig('action', 'position')).to eq(1)

    put "#{base_path}/#{action_id}", params: {
      target_device_id: buzzer.id,
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 2000,
      delay_ms: 250,
      enabled: false,
      position: 77
    }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(json).to include('code' => 'duplicate_action')

    first = source.trigger_actions.first
    delete "#{base_path}/#{first.id}", headers: headers
    put "#{base_path}/#{action_id}", params: {
      target_device_id: buzzer.id,
      action_type: 'relay_pulse',
      relay_index: 0,
      duration_ms: 2000,
      delay_ms: 250,
      enabled: false,
      position: 77
    }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json.fetch('action')).to include(
      'target' => include('id' => buzzer.id),
      'duration_ms' => 2000,
      'delay_ms' => 250,
      'enabled' => false,
      'position' => 1
    )

    put "#{base_path}/order", params: { action_ids: [action_id] }, headers: headers, as: :json
    expect(json.dig('actions', 0, 'position')).to eq(0)

    delete "#{base_path}/#{action_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(source.trigger_actions.reload).to be_empty
  end

  it 'returns the canonical validation and duplicate codes' do
    foreign = device('buzzer', owned: false, device_info: { relays: [{}] }.to_json)
    cases = [
      [valid_payload.merge(target_device_id: foreign.id), :not_found, 'target_not_found'],
      [valid_payload.merge(action_type: 'toggle'), :unprocessable_entity, 'invalid_action_type'],
      [valid_payload.merge(relay_index: 9), :unprocessable_entity, 'invalid_relay_index'],
      [valid_payload.merge(duration_ms: 99), :unprocessable_entity, 'invalid_duration'],
      [valid_payload.merge(delay_ms: 300_001), :unprocessable_entity, 'invalid_delay'],
      [valid_payload.merge(enabled: 'yes'), :unprocessable_entity, 'invalid_enabled']
    ]
    cases.each do |payload, status, code|
      post base_path, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(status)
      expect(json).to include('code' => code)
    end

    post base_path, params: valid_payload, headers: headers, as: :json
    post base_path, params: valid_payload, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(json).to include('code' => 'duplicate_action')

    put "#{base_path}/order", params: { action_ids: [] }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json).to include('code' => 'invalid_order')
  end

  it 'returns action_limit_reached as a conflict after 20 persisted rows' do
    20.times do |index|
      target = device('switch', device_info: { relays: [{}] }.to_json)
      persisted_action(target: target, position: index)
    end
    extra = device('buzzer', device_info: { relays: [{}] }.to_json)

    post base_path, params: valid_payload.merge(target_device_id: extra.id), headers: headers, as: :json

    expect(response).to have_http_status(:conflict)
    expect(json).to include('code' => 'action_limit_reached')
  end

  it 'requires reconciliation before create over valid or invalid legacy configuration' do
    [
      { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }.to_json,
      '{bad'
    ].each do |legacy|
      source.update!(trigger: legacy)
      post base_path, params: valid_payload, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      expect(json).to include('code' => 'legacy_configuration_requires_reconciliation')
    end
  end

  it 'returns the same generic 404 for missing, inaccessible, and unsupported legacy targets' do
    unsupported = device('dht')
    inaccessible = device('buzzer', owned: false, device_info: { relays: [{}] }.to_json)
    responses = [unsupported.chip_id, inaccessible.chip_id, 'missing-target'].map do |chip_id|
      source.update!(trigger: { chip_id: chip_id, relay_index: 0, longlast: 1000 }.to_json)
      post "#{base_path}/migrate_legacy", headers: headers
      expect(source.trigger_actions.reload).to be_empty
      [response.status, json]
    end

    expect(responses).to all(eq([404, {
      'status' => 'error', 'code' => 'target_not_found', 'message' => 'Target device not found'
    }]))
  end

  it 'migrates legacy configuration idempotently and reports mode conflicts canonically' do
    source.update!(trigger: { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }.to_json)
    post "#{base_path}/migrate_legacy", headers: headers
    expect(response).to have_http_status(:ok)
    expect(json).to include('migrated' => true, 'mode' => 'actions')
    action_id = json.dig('action', 'id')

    post "#{base_path}/migrate_legacy", headers: headers
    expect(json).to include('migrated' => false)
    expect(json.dig('action', 'id')).to eq(action_id)

    source.trigger_actions.first.update!(duration_ms: 1200)
    post "#{base_path}/migrate_legacy", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(json).to include('code' => 'configuration_mode_conflict')
  end

  it 'rejects malformed legacy values with the reconciliation code and no partial mutation' do
    source.update!(trigger: { chip_id: buzzer.chip_id, relay_index: '0', longlast: 1000 }.to_json)

    post "#{base_path}/migrate_legacy", headers: headers

    expect(response).to have_http_status(:conflict)
    expect(json).to include('code' => 'legacy_configuration_requires_reconciliation')
    expect(source.trigger_actions).to be_empty
  end

  it 'returns service unavailable while the execution and management feature is disabled' do
    allow(DeviceTriggerFeature).to receive(:enabled?).and_return(false)
    get base_path, headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(json).to include('code' => 'feature_disabled')
  end
end
