require 'rails_helper'
require 'rake'
require 'stringio'

RSpec.describe 'device:create' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task) { Rake::Task['device:create'] }

  before do
    task.reenable
  end

  def run_task(*answers)
    input = StringIO.new("#{answers.join("\n")}\n")
    output = StringIO.new

    stub_const('STDIN', input)
    allow($stdout).to receive(:write) { |value| output.write(value) }

    task.invoke
    output.string
  end

  it 'creates a complete single-relay device with the default duration' do
    run_task('esp8266_create_default', 'Relay 1 kenh', '', '', 'n')

    device = Device.find_by!(chip_id: 'esp8266_create_default')
    device_info = JSON.parse(device.device_info)
    trigger = JSON.parse(device.trigger)

    expect(device).to have_attributes(
      name: 'Relay 1 kenh',
      device_type: 'switch',
      status: 1,
      is_payment: false,
      note: nil
    )
    expect(device.parsed_meta_info).to eq({})
    expect(device_info).to include(
      'device_type' => 'switch',
      'topic_type' => 'switchon',
      'device_id' => device.chip_id,
      'switch_value' => nil,
      'longlast' => nil,
      'timetrigger' => nil,
      'local_ip' => '',
      'build_version' => 0,
      'app_version' => '1.0.0'
    )
    expect(device_info['update_at']).to be_a(Integer)
    expect(device_info['relays']).to eq([
      {
        'switch_value' => 0,
        'longlast' => 6000,
        'is_reminders_active' => true,
        'reminders' => []
      }
    ])
    expect(trigger).to eq(
      'relay_indexes' => [0],
      'chip_id' => device.chip_id,
      'longlast' => 6000
    )
    expect(device.users).to be_empty
  end

  it 'uses an explicit duration and links an existing user' do
    user = User.create!(
      username: 'single_relay_owner',
      email: 'single-relay-owner@example.com',
      password: 'password123'
    )

    run_task(
      'esp8266_create_linked',
      'Relay linked',
      'Test note',
      '12000',
      'y',
      user.email
    )

    device = Device.find_by!(chip_id: 'esp8266_create_linked')

    expect(device.note).to eq('Test note')
    expect(JSON.parse(device.device_info).dig('relays', 0, 'longlast')).to eq(12000)
    expect(JSON.parse(device.trigger)['longlast']).to eq(12000)
    expect(device.users).to contain_exactly(user)
  end

  it 'does not create a duplicate device' do
    existing = Device.create!(name: 'Existing', chip_id: 'esp8266_duplicate')

    output = run_task('esp8266_duplicate')

    expect(Device.where(chip_id: existing.chip_id).count).to eq(1)
    expect(existing.reload.name).to eq('Existing')
    expect(output).to include("Device with chip_id 'esp8266_duplicate' already exists!")
  end

  it 'rejects an invalid duration without creating a partial device' do
    output = run_task('esp8266_invalid_duration', 'Relay invalid', '', '-1')

    expect(Device.exists?(chip_id: 'esp8266_invalid_duration')).to be(false)
    expect(output).to include('longlast must be a non-negative integer!')
  end

  it 'does not create the device when the selected user is missing' do
    output = run_task(
      'esp8266_missing_user',
      'Relay missing user',
      '',
      '6000',
      'y',
      'missing@example.com'
    )

    expect(Device.exists?(chip_id: 'esp8266_missing_user')).to be(false)
    expect(output).to include("User with email 'missing@example.com' not found! Device was not created.")
  end
end
