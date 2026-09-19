require 'rails_helper'

RSpec.describe 'Buzzer JSON API', type: :request do
  let(:user) do
    User.create!(username: "buzzer_api_#{SecureRandom.hex(3)}", email: "buzzer_api_#{SecureRandom.hex(3)}@example.com",
                 password: 'password123')
  end
  let(:headers) do
    { 'Authorization' => "Bearer #{JWT.encode({ user_id: user.id, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)}" }
  end
  let(:buzzer) do
    Device.create!(chip_id: "buzzer_#{SecureRandom.hex(4)}", name: 'Buzzer', device_type: 'buzzer',
                   device_info: { update_at: Time.current.to_i, relays: [{ longlast: 1000 }] }.to_json,
                   meta_info: { last_seen: Time.current.iso8601 }.to_json).tap { |device| device.users << user }
  end
  let(:pir) do
    Device.create!(chip_id: "pir_#{SecureRandom.hex(4)}", name: 'PIR', device_type: 'pir',
                   trigger: { chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }.to_json).tap do |device|
      device.users << user
    end
  end

  def body
    JSON.parse(response.body)
  end

  it 'rejects expired JWTs' do
    token = JWT.encode({ user_id: user.id, exp: 1.minute.ago.to_i }, Rails.application.secret_key_base)

    get "/api/devices/#{buzzer.id}/buzzer", headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(body).to include('error' => 'Unauthorized')
  end

  it 'rejects malformed JWTs' do
    get "/api/devices/#{buzzer.id}/buzzer", headers: { 'Authorization' => 'Bearer not-a-jwt' }

    expect(response).to have_http_status(:unauthorized)
    expect(body).to include('error' => 'Unauthorized')
  end

  it 'rejects JWTs for a nonexistent user' do
    user
    token = JWT.encode({ user_id: User.maximum(:id).to_i + 1, exp: 1.day.from_now.to_i }, Rails.application.secret_key_base)

    get "/api/devices/#{buzzer.id}/buzzer", headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(body).to include('error' => 'Unauthorized')
  end

  it 'hides foreign and non-Buzzer devices' do
    get "/api/devices/#{buzzer.id}/buzzer"
    expect(response).to have_http_status(:unauthorized)

    foreign = Device.create!(chip_id: "foreign_#{SecureRandom.hex(4)}", device_type: 'buzzer')
    get "/api/devices/#{foreign.id}/buzzer", headers: headers
    expect(response).to have_http_status(:not_found)

    get "/api/devices/#{pir.id}/buzzer", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'returns detail and only accessible linked PIRs' do
    pir
    Device.create!(chip_id: "other_pir_#{SecureRandom.hex(4)}", device_type: 'pir',
                   trigger: { chip_id: buzzer.chip_id }.to_json)

    get "/api/devices/#{buzzer.id}/buzzer", headers: headers
    expect(body.fetch('buzzer')).to include('online' => true, 'linked_pir_count' => 1,
                                            'last_triggered_at' => nil)
    expect(body.dig('buzzer', 'last_seen')).to be_present

    get "/api/devices/#{buzzer.id}/buzzer/linked_pirs", headers: headers
    expect(body.fetch('linked_pirs').map { |source| source.fetch('id') }).to eq([pir.id])
  end

  it 'returns the latest 20 matching events in stable order beyond the first scan batch' do
    pir
    201.times do |index|
      pir.device_events.create!(event_type: 'motion_detected', occurred_at: (index + 1).seconds.ago,
                                payload: { target_chip_id: 'other' })
    end
    expected = 21.times.map do |index|
      pir.device_events.create!(event_type: 'motion_detected', occurred_at: (index + 300).seconds.ago,
                                payload: { target_chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 })
    end

    get "/api/devices/#{buzzer.id}/buzzer/history", headers: headers
    expect(response).to have_http_status(:ok)
    expect(body.fetch('events').map { |event| event.fetch('id') }).to eq(expected.first(20).map(&:id))
  end

  it 'uses the existing test service and maps its errors' do
    service = instance_double(BuzzerTestService)
    allow(BuzzerTestService).to receive(:new).with(device: buzzer, user: user).and_return(service)
    allow(service).to receive(:call).and_return(BuzzerTestService::Result.new(relay_index: 0, longlast: 1000))

    post "/api/devices/#{buzzer.id}/buzzer/test", headers: headers
    expect(body).to include('status' => 'success', 'longlast' => 1000)

    { BuzzerTestService::ConfigurationError => :unprocessable_entity,
      BuzzerTestService::CooldownError => :too_many_requests,
      BuzzerTestService::PublishError => :service_unavailable }.each do |error, status|
      allow(service).to receive(:call).and_raise(error, 'Failed')
      post "/api/devices/#{buzzer.id}/buzzer/test", headers: headers
      expect(response).to have_http_status(status)
    end
  end
end
