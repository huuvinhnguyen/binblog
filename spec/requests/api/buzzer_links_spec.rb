require 'rails_helper'

RSpec.describe 'Buzzer PIR link management', type: :request do
  let(:user) { User.create!(username: 'link_owner', email: 'links@example.com', password: 'password123') }
  let(:headers) do
    { 'Authorization' => "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}" }
  end
  let(:buzzer) { device('buzzer') }
  let(:pir) { device('pir') }
  let(:base) { "/api/devices/#{buzzer.id}/buzzer" }
  let(:payload) { { pir_id: pir.id, relay_index: 0, longlast: 1000 } }

  def device(type, owned: true, **attrs)
    Device.create!({ chip_id: SecureRandom.hex(8), name: type, device_type: type }.merge(attrs)).tap do |record|
      record.users << user if owned
    end
  end

  def body
    JSON.parse(response.body)
  end

  def link(target = buzzer, params = payload)
    post "/api/devices/#{target.id}/buzzer/linked_pirs", params: params, headers: headers, as: :json
  end

  # All management requests must remain configuration-only. Runtime compatibility
  # has a separate example that explicitly permits a mocked MQTT connection.
  before do |example|
    unless example.metadata[:runtime]
      expect(MQTT::Client).not_to receive(:connect)
      expect_any_instance_of(MQTT::Client).not_to receive(:publish)
      expect(BuzzerTestService).not_to receive(:new)
    end
  end

  it 'lists only accessible PIRs and exposes only accessible target identity' do
    other = device('buzzer')
    private_target = device('buzzer', owned: false, name: 'private target')
    selected = device('pir', trigger: { chip_id: buzzer.chip_id }.to_json)
    moved = device('pir', trigger: { chip_id: other.chip_id }.to_json)
    hidden = device('pir', trigger: { chip_id: private_target.chip_id }.to_json)
    device('pir', owned: false)
    device('switch')
    pir

    get "#{base}/available_pirs", headers: headers

    expect(response).to have_http_status(:ok)
    rows = body.fetch('available_pirs').index_by { |row| row.fetch('id') }
    expect(rows.keys).to match_array([pir.id, selected.id, moved.id, hidden.id])
    expect(rows[pir.id]).to include('linked_buzzer' => nil, 'requires_confirmation' => false)
    expect(rows[selected.id]).to include('linked_buzzer' => { 'id' => buzzer.id, 'name' => buzzer.name }, 'requires_confirmation' => false)
    expect(rows[moved.id]).to include('linked_buzzer' => { 'id' => other.id, 'name' => other.name }, 'requires_confirmation' => true)
    expect(rows[hidden.id]).to include('linked_buzzer' => nil, 'requires_confirmation' => true)
    expect(response.body).not_to include(private_target.chip_id, private_target.name)
  end

  it 'returns an empty available list' do
    get "#{base}/available_pirs", headers: headers
    expect(body).to eq('status' => 'success', 'available_pirs' => [])
  end

  it 'links with normalized JSON and immediately updates the existing read endpoint' do
    link
    expect(response).to have_http_status(:ok)
    expect(body.fetch('linked_pir')).to include('id' => pir.id, 'relay_index' => 0, 'longlast' => 1000)
    expect(JSON.parse(pir.reload.trigger)).to eq('chip_id' => buzzer.chip_id, 'relay_index' => 0, 'longlast' => 1000)
    get "#{base}/linked_pirs", headers: headers
    expect(body.fetch('linked_pirs').map { |row| row['id'] }).to eq([pir.id])
  end

  it 'relinks and safely repeats the same link without publishing' do
    old = device('buzzer')
    link(old)
    link
    state = pir.reload.trigger
    link
    expect(pir.reload.trigger).to eq(state)
    get "/api/devices/#{old.id}/buzzer/linked_pirs", headers: headers
    expect(body.fetch('linked_pirs')).to eq([])
    get "#{base}/linked_pirs", headers: headers
    expect(body.fetch('linked_pirs').map { |row| row['id'] }).to eq([pir.id])
  end

  { pir_id: [nil, '1', '1abc', 0, -1, 1.5, [], {}],
    relay_index: [nil, '0', -1, 0.5, false, [], {}],
    longlast: [nil, '1000', 99, 10_001, 100.5, false, [], {}] }.each do |field, values|
    values.each do |value|
      it "rejects invalid #{field}=#{value.inspect} without modifying trigger" do
        pir.update!(trigger: '{malformed')
        link(buzzer, payload.merge(field => value))
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body).to include('status' => 'error', 'message' => a_kind_of(String))
        expect(pir.reload.trigger).to eq('{malformed')
      end
    end
  end

  %i[pir_id relay_index longlast].each do |field|
    it "rejects a missing #{field}" do
      link(buzzer, payload.except(field))
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  [100, 10_000].each do |duration|
    it "accepts the duration boundary #{duration}" do
      link(buzzer, payload.merge(longlast: duration, relay_index: 2))
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(pir.reload.trigger)).to include('longlast' => duration, 'relay_index' => 2)
    end
  end

  [nil, '{broken', '[]', 'null'].each do |stored|
    it "replaces #{stored.inspect} with a complete valid configuration" do
      pir.update!(trigger: stored)
      link
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(pir.reload.trigger)).to eq('chip_id' => buzzer.chip_id, 'relay_index' => 0, 'longlast' => 1000)
    end
  end

  %w[get post delete].each do |method|
    it "requires JWT authentication for #{method}" do
      path = method == 'get' ? "#{base}/available_pirs" : "#{base}/linked_pirs"
      path += "/#{pir.id}" if method == 'delete'
      [nil, 'Bearer invalid'].each do |auth|
        public_send(method, path, params: method == 'post' ? payload : {}, headers: { 'Authorization' => auth }, as: :json)
        expect(response).to have_http_status(:unauthorized)
        expect(body).to eq('error' => 'Unauthorized')
      end
    end

    it "hides missing, inaccessible, and non-Buzzer targets for #{method}" do
      [0, device('buzzer', owned: false).id, device('switch').id].each do |id|
        path = "/api/devices/#{id}/buzzer/#{method == 'get' ? 'available_pirs' : 'linked_pirs'}"
        path += "/#{pir.id}" if method == 'delete'
        public_send(method, path, params: method == 'post' ? payload : {}, headers: headers, as: :json)
        expect(response).to have_http_status(:not_found)
        expect(body).to eq('status' => 'error', 'message' => 'Buzzer device not found')
      end
    end
  end

  %w[post delete].each do |method|
    it "hides missing, inaccessible, and non-PIR sources for #{method}" do
      [2_000_000_000, device('pir', owned: false).id, device('switch').id].each do |id|
        if method == 'post'
          link(buzzer, payload.merge(pir_id: id))
        else
          delete "#{base}/linked_pirs/#{id}", headers: headers
        end
        expect(response).to have_http_status(:not_found)
        expect(body).to eq('status' => 'error', 'message' => 'PIR device not found')
      end
    end
  end

  it 'unlinks, preserves unrelated metadata, and permits repeated unlink without publishing' do
    pir.update!(trigger: { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000,
                           switch_value: 1, sent_time: 'old', note: 'keep' }.to_json)
    2.times do
      delete "#{base}/linked_pirs/#{pir.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(body).to eq('status' => 'success', 'pir_id' => pir.id)
      expect(JSON.parse(pir.reload.trigger)).to eq('note' => 'keep')
    end
    get "#{base}/linked_pirs", headers: headers
    expect(body.fetch('linked_pirs')).to eq([])
  end

  it 'clears a normalized link to an empty JSON object' do
    link
    delete "#{base}/linked_pirs/#{pir.id}", headers: headers
    expect(pir.reload.trigger).to eq('{}')
  end

  it 'does not clear another target, malformed JSON, or unrelated trigger configurations' do
    [nil, '{broken', '[]', { chip_id: 'another', switch_value: 1 }.to_json, { note: 'keep' }.to_json].each do |stored|
      pir.update!(trigger: stored)
      delete "#{base}/linked_pirs/#{pir.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(pir.reload.trigger).to eq(stored)
    end
  end

  it 'rejects partial numeric unlink IDs' do
    delete "#{base}/linked_pirs/#{pir.id}junk", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'allows administrators to use the established access scope' do
    user.add_role(:admin)
    foreign_pir = device('pir', owned: false)
    foreign_buzzer = device('buzzer', owned: false)
    link(foreign_buzzer, payload.merge(pir_id: foreign_pir.id))
    expect(response).to have_http_status(:ok)
  end

  it 'feeds newly written configuration to the unchanged PIR runtime', :runtime do
    client = instance_double(MQTT::Client, publish: nil, disconnect: nil)
    allow(MQTT::Client).to receive(:connect).and_return(client)
    link
    expect(MQTT::Client).not_to have_received(:connect)

    post '/api/devices/trigger', params: { chip_id: pir.chip_id }, as: :json

    expect(response).to have_http_status(:ok)
    expect(client).to have_received(:publish) do |topic, message, options|
      expect(topic).to eq("#{buzzer.chip_id}/switchon")
      expect(JSON.parse(message)).to include('chip_id' => buzzer.chip_id, 'relay_index' => 0, 'longlast' => 1000,
                                            'sent_time' => a_kind_of(String))
      expect(options).to eq(retain: false)
    end
    expect(client).to have_received(:disconnect)
    expect(pir.device_events.last.parsed_payload).to include('target_chip_id' => buzzer.chip_id)
  end
end
