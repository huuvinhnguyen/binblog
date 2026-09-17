require 'rails_helper'

RSpec.describe 'POST /devices/:id/test_buzzer', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(username: "buzzer_owner_#{SecureRandom.hex(4)}", email: "buzzer-owner-#{SecureRandom.hex(4)}@example.com", password: 'password123') }
  let(:buzzer) do
    Device.create!(
      chip_id: "esp32_buzzer_request_#{SecureRandom.hex(4)}",
      name: 'Buzzer request test',
      device_type: 'buzzer',
      status: 1,
      is_payment: false,
      device_info: { relays: [{ longlast: 1000 }] }.to_json
    )
  end

  before do
    buzzer.users << user
    sign_in user
  end

  it 'calls the service for an accessible Buzzer' do
    service = instance_double(BuzzerTestService, call: BuzzerTestService::Result.new(relay_index: 0, longlast: 1000))
    allow(BuzzerTestService).to receive(:new).with(device: buzzer, user: user).and_return(service)

    post test_buzzer_device_path(buzzer)

    expect(response).to redirect_to(device_path(buzzer))
    expect(service).to have_received(:call)
    expect(flash[:notice]).to eq('Đã gửi yêu cầu test đến MQTT broker.')
  end

  it 'returns not found when the user does not own the Buzzer' do
    other_buzzer = Device.create!(
      chip_id: "esp32_buzzer_private_#{SecureRandom.hex(4)}",
      name: 'Private Buzzer',
      device_type: 'buzzer',
      status: 1,
      is_payment: false
    )

    expect(BuzzerTestService).not_to receive(:new)
    post test_buzzer_device_path(other_buzzer)

    expect(response).to have_http_status(:not_found)
  end

  it 'returns the Buzzer page with an error when its configuration is invalid' do
    service = instance_double(BuzzerTestService)
    allow(BuzzerTestService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise(
      BuzzerTestService::ConfigurationError,
      'Cấu hình Buzzer không hợp lệ.'
    )

    post test_buzzer_device_path(buzzer)

    expect(response).to redirect_to(device_path(buzzer))
    expect(flash[:alert]).to eq('Cấu hình Buzzer không hợp lệ.')
  end

  it 'redirects unauthenticated visitors to sign in' do
    sign_out user

    post test_buzzer_device_path(buzzer)

    expect(response).to redirect_to(new_user_session_path)
  end
end
