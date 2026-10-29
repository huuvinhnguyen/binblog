require 'rails_helper'

RSpec.describe 'Switch web statistics', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { User.create!(username: "stats_#{SecureRandom.hex(4)}", password: 'password123', email: "#{SecureRandom.hex(4)}@example.com") }
  let(:device) do
    Device.create!(chip_id: "stats_#{SecureRandom.hex(4)}", device_type: 'switch',
                   device_info: { relays: [{}] }.to_json).tap { |row| row.users << user }
  end

  it 'requires session authentication and scopes the chip ID to the owner' do
    get '/devices/relay_statistics', params: { chip_id: device.chip_id, relay_index: 0 }
    expect(response.status).to eq(302)
    sign_in user
    foreign = Device.create!(chip_id: 'foreign_stats', device_type: 'switch')
    get '/devices/relay_statistics', params: { chip_id: foreign.chip_id, relay_index: 0 }
    expect(response.status).to eq(404)
  end

  it 'renders real counts and a clear metric instead of the sample chart' do
    sign_in user
    device.relay_logs.create!(relay_index: 0)
    get '/devices/relay_statistics', params: { chip_id: device.chip_id, relay_index: 0 }
    expect(response.status).to eq(200)
    expect(response.body).to include('Tổng số bản ghi: 1')
    expect(response.body).not_to include('myChart')
  end

  it 'keeps legacy HTML none compatible with the persisted once enum' do
    sign_in user
    device.update!(device_info: { relays: [{ is_reminders_active: true }] }.to_json)
    allow_any_instance_of(Api::DevicesController).to receive(:refresh)
    allow_any_instance_of(Reminder).to receive(:schedule_immediate_job_if_soon)
    post '/api/devices/add_reminder', params: { device_id: device.chip_id, relay_index: 0,
      start_time: 1.day.from_now.iso8601, duration: 1000, repeat_type: 'none' }
    expect(response.status).to eq(302)
    expect(device.reminders.last.repeat_type).to eq('once')
  end
end
