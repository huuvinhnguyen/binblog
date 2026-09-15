require 'rails_helper'

RSpec.describe 'PIR motion statistics API', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(username: 'motion_stats_user', email: 'motion-stats@example.com', password: 'password123') }
  let(:device) do
    Device.create!(chip_id: 'esp32_motion_stats', name: 'PIR stats', device_type: 'pir')
  end

  before do
    device.users << user
    sign_in user
  end

  it 'returns 24 hourly buckets for a selected date' do
    travel_to Time.zone.parse('2026-09-15 10:30:00') do
      DeviceEvent.create!(device: device, event_type: 'motion_detected', occurred_at: Time.zone.parse('2026-09-15 02:10:00'))
      DeviceEvent.create!(device: device, event_type: 'motion_detected', occurred_at: Time.zone.parse('2026-09-15 02:45:00'))

      get '/api/devices/motion_stats', params: { chip_id: device.chip_id, date: '2026-09-15' }
    end

    json = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(json['labels'].length).to eq(24)
    expect(json['values'][2]).to eq(2)
    expect(json['total']).to eq(2)
  end

  it 'returns a 30-day heatmap with event counts' do
    DeviceEvent.create!(device: device, event_type: 'motion_detected', occurred_at: Time.zone.today.beginning_of_day + 1.hour)

    get '/api/devices/motion_heatmap', params: { chip_id: device.chip_id, days: 30 }

    json = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(json['data'].length).to eq(30)
    expect(json['data'].last).to include('date' => Time.zone.today.iso8601, 'count' => 1)
  end

  it 'requires authentication' do
    sign_out user

    get '/api/devices/motion_stats', params: { chip_id: device.chip_id, date: Time.zone.today.iso8601 }

    expect(response).to have_http_status(:unauthorized)
  end
end
