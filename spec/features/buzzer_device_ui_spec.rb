require 'rails_helper'

RSpec.describe 'Buzzer Device UI', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(username: 'buzzer_user', email: 'buzzer@example.com', password: 'password123') }
  let(:buzzer) do
    Device.create!(
      chip_id: "esp32_buzzer_ui_#{SecureRandom.hex(4)}",
      name: 'Chuông phòng khách',
      device_type: 'buzzer',
      status: 1,
      is_payment: false,
      device_info: { update_at: Time.current.to_i }.to_json,
      meta_info: {}.to_json
    )
  end
  let(:source_pir) do
    Device.create!(
      chip_id: "esp32_pir_ui_#{SecureRandom.hex(4)}",
      name: 'PIR cửa trước',
      device_type: 'pir',
      status: 1,
      is_payment: false,
      trigger: {
        chip_id: buzzer.chip_id,
        relay_index: 0,
        switch_value: 1,
        longlast: 1000
      }.to_json
    )
  end

  before do
    expect(MQTT::Client).not_to receive(:connect)
    expect_any_instance_of(MQTT::Client).not_to receive(:publish)
    expect(BuzzerTestService).not_to receive(:new)
    buzzer.users << user
    sign_in user
  end

  it 'shows linked PIRs and motion events targeted at this buzzer' do
    source_pir.users << user
    DeviceEvent.create!(
      device: source_pir,
      event_type: 'motion_detected',
      occurred_at: 1.minute.ago,
      payload: { target_chip_id: buzzer.chip_id, relay_index: 0, longlast: 1000 }
    )
    DeviceEvent.create!(
      device: source_pir,
      event_type: 'motion_detected',
      occurred_at: 2.minutes.ago,
      payload: { target_chip_id: 'another_buzzer', longlast: 500 }
    )

    get device_path(buzzer)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Chuông phòng khách')
    expect(response.body).to include('PIR kích hoạt Buzzer')
    expect(response.body).to include('Test Buzzer')
    expect(response.body).to include('chưa có xác nhận từ Buzzer')
    expect(response.body).to include('data-buzzer-test-form="true"')
    expect(response.body).to include('PIR cửa trước')
    expect(response.body).to include('Lịch sử lệnh từ PIR')
    expect(response.body).to include('Đã nhận motion')
    expect(response.body).not_to include('another_buzzer')
  end

  it 'renders clear empty states when no PIR targets the buzzer' do
    get device_path(buzzer)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Chưa có PIR nào được cấu hình để kích hoạt Buzzer này.')
    expect(response.body).to include('Chưa có lịch sử lệnh từ PIR cho Buzzer này.')
  end

  it 'renders management controls separately from the existing Test Buzzer form' do
    get device_path(buzzer)

    html = Nokogiri::HTML(response.body)
    panel = html.at_css('[data-buzzer-links]')
    expect(panel['data-buzzer-id']).to eq(buzzer.id.to_s)
    expect(panel.at_css('[data-links-form]')['data-turbo']).to eq('false')
    expect(panel.at_css('[data-links-relay]')['min']).to eq('0')
    expect(panel.at_css('[data-links-duration]')['min']).to eq('100')
    expect(panel.at_css('[data-links-duration]')['max']).to eq('10000')
    expect(panel.at_css('[data-links-error]')['role']).to eq('alert')
    expect(panel.at_css('[data-buzzer-test-form]')).to be_nil
    expect(html.at_css('[data-buzzer-test-form]')['action']).to eq(test_buzzer_device_path(buzzer))
  end

  it 'uses the signed-in Web session for the existing management API without MQTT' do
    source_pir.users << user
    base = "/api/devices/#{buzzer.id}/buzzer"
    get "#{base}/available_pirs", as: :json
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['available_pirs'].map { |pir| pir['id'] }).to eq([source_pir.id])

    post "#{base}/linked_pirs", params: { pir_id: source_pir.id, relay_index: 1, longlast: 100 }, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/linked_pirs", as: :json
    expect(JSON.parse(response.body)['linked_pirs'].first).to include('relay_index' => 1, 'longlast' => 100)

    delete "#{base}/linked_pirs/#{source_pir.id}", as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/linked_pirs", as: :json
    expect(JSON.parse(response.body)['linked_pirs']).to eq([])
  end
end
