require 'rails_helper'

RSpec.describe 'Switch JSON facade', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(username: "switch_#{SecureRandom.hex(4)}", password: 'password123', email: "#{SecureRandom.hex(4)}@example.com") }
  let(:device) do
    Device.create!(name: 'Switch', chip_id: "switch_#{SecureRandom.hex(4)}", device_type: 'switch',
                   device_info: { update_at: 123, relays: [{ switch_value: 0, longlast: 1000, is_reminders_active: true }, {}] }.to_json,
                   meta_info: { last_seen: '2026-10-27T08:00:00+07:00' }.to_json).tap { |row| row.users << user }
  end
  let(:headers) do
    { 'Authorization' => "Bearer #{JWT.encode({ user_id: user.id, exp: 1.hour.from_now.to_i }, Rails.application.secret_key_base, 'HS256')}",
      'Accept' => 'application/json', 'Content-Type' => 'application/json' }
  end
  let(:base) { "/api/switches/#{device.id}" }
  let(:publisher) { instance_double(SwitchApi::Publisher, call: nil) }

  before do
    allow(SwitchApi::Features).to receive(:enabled?).and_return(true)
    allow(SwitchApi::Publisher).to receive(:new).and_return(publisher)
    allow(MQTT::Client).to receive(:new) { raise 'Unexpected real MQTT client in request spec' }
  end

  def json
    JSON.parse(response.body)
  end

  it 'requires a Bearer token even with a web session' do
    sign_in user
    get base, headers: headers.except('Authorization')
    expect(response.status).to eq(401)
    expect(json).to include('code' => 'authentication_required', 'request_id' => a_kind_of(String))
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'rejects bad, expired and wrong-algorithm tokens' do
    tokens = ['not-a-token', JWT.encode({ user_id: user.id, exp: 1.second.ago.to_i }, Rails.application.secret_key_base),
              JWT.encode({ user_id: user.id, exp: 1.hour.from_now.to_i }, Rails.application.secret_key_base, 'HS384')]
    tokens.each do |token|
      get base, headers: headers.merge('Authorization' => "Bearer #{token}")
      expect(response.status).to eq(401)
    end
  end

  it 'hides foreign, missing and wrong-type devices and rejects partial numeric IDs' do
    foreign = Device.create!(chip_id: 'foreign_switch', device_type: 'switch')
    [foreign.id, '999999999', "#{device.id}suffix"].each do |id|
      get "/api/switches/#{id}", headers: headers
      expect(response.status).to eq(404)
    end
    device.update!(device_type: 'pir')
    get base, headers: headers
    expect(response.status).to eq(404)
    expect(publisher).not_to have_received(:call)
  end

  it 'uses the established admin device scope' do
    user.add_role(:admin)
    foreign = Device.create!(chip_id: 'admin_visible', device_type: 'switch', device_info: { relays: [] }.to_json)
    get "/api/switches/#{foreign.id}", headers: headers
    expect(response.status).to eq(200)
  end

  it 'returns an honest snapshot without jobs, telemetry updates or MQTT' do
    original = device.attributes
    get base, headers: headers
    expect(response.status).to eq(200)
    expect(json.fetch('switch')).to include('id' => device.id.to_s, 'online' => nil,
                                           'physical_state_verified' => false, 'state_source' => 'server_snapshot')
    expect(json.dig('switch', 'relays', 1)).to include('switch_value' => nil, 'reminders_active' => nil)
    expect(json.dig('switch', 'capabilities', 'reminders')).to be(false)
    expect(device.reload.attributes).to eq(original)
    expect(DeviceEvent.count).to eq(0)
    expect(publisher).not_to have_received(:call)
  end

  it 'fails closed on malformed stored configuration and preserves valid empty relays' do
    ['{', '{}', '{"relays":{}}', '{"relays":[null]}', { relays: Array.new(33) { {} } }.to_json].each do |value|
      device.update!(device_info: value)
      get base, headers: headers
      expect(response.status).to eq(422)
      expect(json['code']).to eq('invalid_configuration')
    end
    device.update!(device_info: { relays: [] }.to_json)
    get base, headers: headers
    expect(json.dig('switch', 'relays')).to eq([])
  end

  it 'reads last_seen written by the legacy heartbeat producer without guessing missing offsets' do
    device.update!(meta_info: { last_seen: '2026-10-27 08:00:00 +0700' }.to_json)
    get base, headers: headers
    expect(json.dig('switch', 'last_seen')).to eq('2026-10-27T08:00:00+07:00')
    ['2026-02-30 08:00:00 +0700', '2026-10-27T08:00:00', nil].each do |value|
      device.update!(meta_info: { last_seen: value }.to_json)
      get base, headers: headers
      expect(json.dig('switch', 'last_seen')).to be_nil
    end
  end

  it 'rejects impossible ISO8601 calendar dates without normalizing heartbeat metadata' do
    ['2026-02-30T08:00:00+07:00', '2026-02-29T01:00:00Z', '2026-04-31T08:00:00+07:00'].each do |value|
      device.update!(meta_info: { last_seen: value }.to_json)
      get base, headers: headers
      expect(response.status).to eq(200)
      expect(json.dig('switch', 'last_seen')).to be_nil
      expect(device.reload.meta_info).to eq({ last_seen: value }.to_json)
    end
    { '2024-02-29T01:02:03Z' => '2024-02-29T08:02:03+07:00',
      '2024-02-29T08:02:03.123+07:00' => '2024-02-29T08:02:03+07:00' }.each do |value, expected|
      device.update!(meta_info: { last_seen: value }.to_json)
      get base, headers: headers
      expect(json.dig('switch', 'last_seen')).to eq(expected)
    end
  end

  it 'returns JSON outcomes and result audits for actual MQTT exception classes' do
    allow(SwitchApi::Publisher).to receive(:new).and_call_original
    client = instance_double(MQTT::Client, connect: nil, publish: nil, disconnect: nil)
    allow(MQTT::Client).to receive(:new).and_return(client)
    allow(Rails.application).to receive(:config_for).with(:mqtt).and_return(host: 'test.invalid', port: 1883)
    allow(client).to receive(:connect).and_raise(MQTT::ProtocolException, 'synthetic private broker detail')

    post "#{base}/refresh", headers: headers
    expect(response.status).to eq(503)
    expect(json).to include('code' => 'command_unavailable', 'outcome' => 'not_attempted')
    expect(response.body).not_to include('synthetic private broker detail')
    expect(device.device_events.order(:id).last.payload['outcome']).to eq('not_attempted')
    expect(client).not_to have_received(:publish)

    allow(client).to receive(:connect).and_return(nil)
    allow(client).to receive(:publish).and_raise(MQTT::NotConnectedException)
    post "#{base}/relays/0/state", params: '{"switch_value":1}', headers: headers
    expect(response.status).to eq(502)
    expect(json).to include('code' => 'command_outcome_unknown', 'outcome' => 'unknown')
    expect(device.device_events.order(:id).last.payload['outcome']).to eq('unknown')
    expect(device.device_events.group(:event_type).count).to eq(
      'switch_command_requested' => 2, 'switch_command_result' => 2
    )
    expect(client).to have_received(:publish).once
  end

  it 'keeps the feature disabled by default and fails closed on malformed values' do
    allow(SwitchApi::Features).to receive(:enabled?).and_call_original
    original = ENV['SWITCH_MOBILE_API_ENABLED']
    begin
      [nil, '', 'false', '0', 'yes', 'TRUE'].each do |value|
        ENV['SWITCH_MOBILE_API_ENABLED'] = value
        get base, headers: headers
        expect(response.status).to eq(503)
      end
      %w[true 1].each do |value|
        ENV['SWITCH_MOBILE_API_ENABLED'] = value
        get base, headers: headers
        expect(response.status).to eq(200)
      end
    ensure
      ENV['SWITCH_MOBILE_API_ENABLED'] = original
    end
  end

  it 'sends exactly one state command without changing server state' do
    original = device.attributes
    post "#{base}/relays/0/state", params: { switch_value: 1 }.to_json, headers: headers
    expect(response.status).to eq(200)
    expect(json).to include('status' => 'accepted', 'outcome' => 'publish_returned', 'acknowledgement' => 'none')
    expect(publisher).to have_received(:call).once.with(topic: "#{device.chip_id}/switchon",
      payload: { relay_index: 0, switch_value: 1, sent_time: a_kind_of(String) })
    expect(device.reload.attributes).to eq(original)
    expect(device.device_events.order(:id).pluck(:event_type)).to eq(%w[switch_command_requested switch_command_result])
  end

  it 'sends duration-only pulse at both boundaries and never schedules a delayed OFF' do
    expect(SwitchOffDurationJob).not_to receive(:perform_in)
    [1000, 86_400_000].each do |duration|
      post "#{base}/relays/1/pulse", params: { duration_ms: duration }.to_json, headers: headers
      expect(response.status).to eq(200)
      expect(publisher).to have_received(:call).with(topic: "#{device.chip_id}/switchon",
        payload: { relay_index: 1, longlast: duration, sent_time: a_kind_of(String) })
    end
  end

  it 'rejects invalid durations, relay indices and state values without any command or audit' do
    [nil, 0, -1, 999, 1500, 86_401_000, '1000', 1000.0, true].each do |value|
      post "#{base}/relays/0/pulse", params: { duration_ms: value }.to_json, headers: headers
      expect(response.status).to eq(422)
    end
    %w[-1 2 01 1.0 abc].each do |index|
      post "#{base}/relays/#{index}/state", params: { switch_value: 1 }.to_json, headers: headers
      expect(response.status).to eq(422)
    end
    [nil, -1, 2, '1', true, 1.0].each do |value|
      post "#{base}/relays/0/state", params: { switch_value: value }.to_json, headers: headers
      expect(response.status).to eq(422)
    end
    expect(DeviceEvent.count).to eq(0)
    expect(publisher).not_to have_received(:call)
  end

  it 'rejects malformed JSON, non-object JSON, unknown keys and wrong media type' do
    post "#{base}/relays/0/state", params: '{', headers: headers
    expect(response.status).to eq(400)
    ['null', '[]', '{"switch_value":1,"chip_id":"foreign"}', ''].each do |payload|
      post "#{base}/relays/0/state", params: payload, headers: headers
      expect(response.status).to eq(422)
    end
    post "#{base}/relays/0/state", params: 'switch_value=1', headers: headers.merge('Content-Type' => 'application/x-www-form-urlencoded')
    expect(response.status).to eq(415)
    get base, headers: headers.merge('Accept' => 'text/html')
    expect(response.status).to eq(406)
    expect(publisher).not_to have_received(:call)
  end

  it 'separates bodyless refresh from read-only GET and rejects refresh payload overrides' do
    post "#{base}/refresh", headers: headers
    expect(response.status).to eq(200)
    expect(publisher).to have_received(:call).once.with(topic: "#{device.chip_id}/refresh",
      payload: { action: 'refresh', sent_time: a_kind_of(String) })
    post "#{base}/refresh", params: '{"topic":"other"}', headers: headers
    expect(response.status).to eq(422)
  end

  it 'reports uncertain publish results without retry or success fiction' do
    allow(publisher).to receive(:call).and_raise(SwitchApi::Publisher::OutcomeUnknown)
    post "#{base}/relays/0/state", params: '{"switch_value":1}', headers: headers
    expect(response.status).to eq(502)
    expect(json).to include('code' => 'command_outcome_unknown', 'outcome' => 'unknown')
    expect(publisher).to have_received(:call).once
  end

  it 'fails before publish when audit persistence is unavailable' do
    allow_any_instance_of(DeviceEvent).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    post "#{base}/refresh", headers: headers
    expect(response.status).to eq(503)
    expect(json['outcome']).to eq('not_attempted')
    expect(publisher).not_to have_received(:call)
  end

  it 'reports outcome unknown when result audit fails after publish' do
    allow_any_instance_of(DeviceEvent).to receive(:save!).and_wrap_original do |method, *args|
      raise ActiveRecord::RecordInvalid if method.receiver.event_type == 'switch_command_result'

      method.call(*args)
    end
    post "#{base}/refresh", headers: headers
    expect(response.status).to eq(502)
    expect(json['outcome']).to eq('unknown')
    expect(publisher).to have_received(:call).once
  end

  it 'keeps pre-publish failure explicit even when the failure audit cannot be saved' do
    allow(publisher).to receive(:call).and_raise(SwitchApi::Publisher::Unavailable)
    allow_any_instance_of(DeviceEvent).to receive(:save!).and_wrap_original do |method, *args|
      raise ActiveRecord::RecordInvalid if method.receiver.event_type == 'switch_command_result'

      method.call(*args)
    end
    post "#{base}/refresh", headers: headers
    expect(response.status).to eq(503)
    expect(json['outcome']).to eq('not_attempted')
  end

  it 'rejects oversized bodies and unsafe stored topic identities before publish' do
    post "#{base}/relays/0/state", params: '{"padding":"' + ('x' * 16_385) + '"}', headers: headers
    expect(response.status).to eq(413)
    device.update!(chip_id: 'bad/+/topic')
    post "#{base}/refresh", headers: headers
    expect(response.status).to eq(422)
    expect(publisher).not_to have_received(:call)
  end

  it 'lists persisted reminders by ID with stable bounded pagination including invalid legacy rows' do
    rows = 3.times.map do
      device.reminders.create!(relay_index: 0, start_time: 1.day.from_now, duration: 1000, repeat_type: 'once')
    end
    rows[1].update_columns(duration: nil, repeat_type: 'legacy_bad')
    get "#{base}/relays/0/reminders", params: { limit: '2' }, headers: headers
    expect(response.status).to eq(200)
    expect(json['reminders'].map { |row| row['id'] }).to eq(rows.first(2).map { |row| row.id.to_s })
    expect(json['next_after_id']).to eq(rows[1].id.to_s)
    expect(json['reminders'][1]['configuration_valid']).to be(false)
    get "#{base}/relays/0/reminders", params: { after_id: rows[1].id.to_s }, headers: headers
    expect(json['reminders'].map { |row| row['id'] }).to eq([rows[2].id.to_s])
    expect(json['next_after_id']).to be_nil
    get "#{base}/relays/0/reminders", params: { limit: '101' }, headers: headers
    expect(response.status).to eq(422)
  end

  it 'blocks every reminder write even if an environment variable requests readiness' do
    original = ENV['SWITCH_REMINDER_EXECUTION_READY']
    begin
      ENV['SWITCH_REMINDER_EXECUTION_READY'] = 'true'
      expect do
        post "#{base}/relays/0/reminders", params: { start_time: 1.day.from_now.iso8601, duration_ms: 1000, repeat_type: 'once' }.to_json, headers: headers
        expect(response.status).to eq(503)
        delete "#{base}/relays/0/reminders/123", headers: headers
        expect(response.status).to eq(503)
        put "#{base}/relays/0/reminders-active", params: '{"active":true}', headers: headers
        expect(response.status).to eq(503)
      end.not_to change(Reminder, :count)
      expect(publisher).not_to have_received(:call)
    ensure
      ENV['SWITCH_REMINDER_EXECUTION_READY'] = original
    end
  end

  it 'enforces explicit reminder capability denial while keeping read access' do
    UserRelayFeature.create!(user: user, device: device, feature: 'reminder', enabled: false)
    post "#{base}/relays/0/reminders", params: '{}', headers: headers
    expect(response.status).to eq(403)
    get "#{base}/relays/0/reminders", headers: headers
    expect(response.status).to eq(200)
    expect(json['reminders']).to eq([])
  end

  it 'counts actual scoped log records and zero-fills dates without physical runtime' do
    travel_to Time.zone.local(2026, 10, 27, 10) do
      device.relay_logs.create!(relay_index: 0, created_at: Time.zone.local(2026, 10, 26, 23, 59))
      device.relay_logs.create!(relay_index: 0, created_at: Time.zone.local(2026, 10, 27, 0, 0))
      device.relay_logs.create!(relay_index: 1, created_at: Time.current)
      get "#{base}/relays/0/statistics", params: { from: '2026-10-25', to: '2026-10-27' }, headers: headers
      expect(response.status).to eq(200)
      expect(json['days'].map { |day| day['count'] }).to eq([0, 1, 1])
      expect(json).to include('metric' => 'log_records', 'total_records' => 2,
                             'physical_runtime_seconds' => nil, 'physical_runtime_verified' => false)
    end
  end

  it 'rejects invalid, partial, reversed, future and oversized statistics ranges' do
    travel_to Time.zone.local(2026, 10, 27, 10) do
      [{ from: '2026-10-01' }, { from: '2026-02-30', to: '2026-10-27' },
       { from: '2026-10-27', to: '2026-10-26' }, { from: '2026-10-27', to: '2026-10-28' },
       { from: '2026-09-01', to: '2026-10-27' }].each do |range|
        get "#{base}/relays/0/statistics", params: range, headers: headers
        expect(response.status).to eq(422)
      end
    end
  end

  it 'returns JSON for an unknown facade path' do
    get '/api/switches/not/a/route', headers: headers
    expect(response.status).to eq(404)
    expect(response.media_type).to eq('application/json')
  end
end
