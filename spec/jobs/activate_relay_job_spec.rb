require 'rails_helper'



RSpec.describe ActivateRelayJob, type: :job do
  
  let(:device) do
    Device.create!(
      name: "Test Device",
      chip_id: "abc123",
      device_info: {
        relays: [{ "switch_value" => 1 }],
        update_at: Time.zone.now.to_i
      }.to_json
    )
  end
  

  let(:reminder) do
    Reminder.create!(
      device: device,
      relay_index: 0,
      start_time: Time.zone.now,
      repeat_type: "daily",
      duration: 5000 # milliseconds
    )
  end

  it 'enqueues the job' do
    expect {
      ActivateRelayJob.perform_async(reminder.id)
    }.to change(ActivateRelayJob.jobs, :size).by(1)
  end

  it "does not schedule job if next_trigger_time is nil for daily repeat" do
    reminder = Reminder.create!(
      relay_index: 0,
      start_time: Time.zone.now,
      repeat_type: 'daily',
      duration: 5000,
      device: device
    )
  
    allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(nil)
  
    ActivateRelayJob.new.perform(reminder.id)
  
    expect(ActivateRelayJob.jobs.size).to eq(0)
  end  

  it 'does not reschedule if repeat_type is once' do
    reminder.update!(repeat_type: "once")

    ActivateRelayJob.new.perform(reminder.id)
    expect(ActivateRelayJob.jobs.size).to eq(0)
    expect(reminder.reload.job_jid).to be_nil
  end

  it "does not reschedule job for repeat_type once" do
    reminder = Reminder.create!(
      relay_index: 0,
      start_time: 1.hour.from_now,
      repeat_type: 'once',
      duration: 5000,
      device: device
    )
  
    ActivateRelayJob.new.perform(reminder.id)
  
    expect(ActivateRelayJob.jobs.size).to eq(0) # Không có job nào được lên lịch lại
  end


  it 'does nothing if reminder does not exist' do
    expect {
      ActivateRelayJob.new.perform(99999) # ID không tồn tại
    }.not_to change { TurnOffRelayJob.jobs.size }
  end

  it 'does nothing if device has no device_info' do
    device.update(device_info: nil)

    expect {
      ActivateRelayJob.new.perform(reminder.id)
    }.not_to change { TurnOffRelayJob.jobs.size }
  end

  it 'does nothing if relay_index is out of bounds' do
    reminder.update(relay_index: 5) # quá chỉ số relay

    expect {
      ActivateRelayJob.new.perform(reminder.id)
    }.not_to change { TurnOffRelayJob.jobs.size }
  end

  it 'does not schedule job if day does not exist in next month (e.g. 31 Feb)' do
    reminder.update(
      repeat_type: 'monthly',
      start_time: Time.zone.parse('2025-01-31 08:00')
    )
  
    ActivateRelayJob.new.perform(reminder.id)
  
    # Không có job mới nếu next_trigger_time = nil
    expect(ActivateRelayJob.jobs.size).to eq(0)
  end

  it "does not schedule job if next_trigger_time is nil for weekly repeat" do
    reminder = Reminder.create!(
      relay_index: 0,
      start_time: Time.zone.now,
      repeat_type: 'weekly',
      duration: 10_000,
      device: device
    )
  
    # Stub next_trigger_time to nil
    allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(nil)
  
    ActivateRelayJob.new.perform(reminder.id)
  
    expect(ActivateRelayJob.jobs.size).to eq(0)
  end

  it 'enqueues the job' do
    expect {
      ActivateRelayJob.perform_async(reminder.id)
    }.to change(ActivateRelayJob.jobs, :size).by(1)
  end
  
end

