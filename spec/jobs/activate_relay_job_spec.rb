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

  it 'activates relay and schedules turn off job' do
    ActivateRelayJob.new.perform(reminder.id)
    updated_device_info = JSON.parse(device.reload.device_info)
    relay = updated_device_info["relays"][0]

    expect(relay["switch_value"]).to eq(1)
    expect(updated_device_info["update_at"]).to be_present
    expect(TurnOffRelayJob.jobs.size).to eq(1)
  end

  it 'reschedules itself if repeat_type is not once' do
    expect {
      ActivateRelayJob.new.perform(reminder.id)
    }.to change(ActivateRelayJob.jobs, :size).by(1)

    expect(reminder.reload.job_jid).to be_present
  end

  it "schedules job for next day if daily and current time has passed" do
    # start_time là 1 tiếng trước
    start_time = 1.hour.ago.change(sec: 0)
  
    reminder = Reminder.create!(
      relay_index: 0,
      start_time: start_time,
      repeat_type: 'daily',
      duration: 5000,
      device: device
    )
  
    ActivateRelayJob.new.perform(reminder.id)
  
    expect(ActivateRelayJob.jobs.size).to eq(1)
  
    expected_time = reminder.next_trigger_time
    scheduled_time = Time.at(ActivateRelayJob.jobs.first['at'])
  
    expect(scheduled_time.to_i).to eq(expected_time.to_i)
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

  it "does not schedule job if start_time is in the past for repeat_type once" do
    # Giả sử start_time đã qua (ví dụ là 1 giờ trước)
    past_time = 1.hour.ago
  
    reminder = Reminder.create!(
      relay_index: 0,
      start_time: past_time,
      repeat_type: 'once',
      duration: 5000,
      device: device
    )
  
    # Gọi ActivateRelayJob
    ActivateRelayJob.new.perform(reminder.id)
  
    # Kiểm tra rằng job không được lên lịch (không có job trong hàng đợi)
    expect(ActivateRelayJob.jobs.size).to eq(0)
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

  it 'schedules next job correctly for monthly repeat' do
    # Setup: thời gian nhắc hiện tại là hôm nay ngày 3
    start_time = Time.zone.now.change(day: 3, hour: 8, min: 0)
    reminder.update(repeat_type: 'monthly', start_time: start_time)
  
    # Kích hoạt job
    expect {
      ActivateRelayJob.new.perform(reminder.id)
    }.to change(ActivateRelayJob.jobs, :size).by(1)
  
    next_job = ActivateRelayJob.jobs.last
  
    next_time = reminder.next_trigger_time
    expect(Time.at(next_job['at']).to_i).to eq(next_time.to_i)
  
    # Đồng thời lên lịch tắt relay (TurnOffRelayJob)
    expect(TurnOffRelayJob.jobs.size).to eq(1)
  end

  it 'schedules next job for monthly repeat when day exists in next month' do
    reminder.update(
      repeat_type: 'monthly',
      start_time: Time.zone.parse('2025-01-15 08:00')
    )
  
    ActivateRelayJob.new.perform(reminder.id)
  
    job = ActivateRelayJob.jobs.last
    expected_time = reminder.next_trigger_time
  
    expect(Time.at(job['at']).to_i).to eq(expected_time.to_i)
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

  it "schedules job again for next week if repeat_type is weekly" do
    # start_time set to next Sunday
    next_sunday = Time.zone.now.next_occurring(:sunday).change(hour: 8, min: 0)

    reminder = Reminder.create!(
      relay_index: 0,
      start_time: next_sunday,
      repeat_type: 'weekly',
      duration: 10_000,
      device: device
    )

    ActivateRelayJob.new.perform(reminder.id)

    expect(ActivateRelayJob.jobs.size).to eq(1)

    scheduled_job_time = Time.at(ActivateRelayJob.jobs.first['at'])
    expected_next_time = reminder.next_trigger_time

    expect(scheduled_job_time.to_i).to eq(expected_next_time.to_i)
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

  it 'activates relay and schedules turn off job' do
    ActivateRelayJob.new.perform(reminder.id)
    updated_device_info = JSON.parse(device.reload.device_info)
    relay = updated_device_info["relays"][0]

    expect(relay["switch_value"]).to eq(1)
    expect(updated_device_info["update_at"]).to be_present
    expect(TurnOffRelayJob.jobs.size).to eq(1)
  end

  it 'schedules TurnOffRelayJob immediately if duration is 0' do
    reminder.update!(duration: 0)
  
    # Clear any previous jobs
    TurnOffRelayJob.clear
  
    ActivateRelayJob.new.perform(reminder.id)
  
    expect(TurnOffRelayJob.jobs.size).to eq(1)
    expect(TurnOffRelayJob.jobs.first['args']).to eq([device.chip_id, reminder.relay_index])
  end

  it 'schedules TurnOffRelayJob 10 seconds later if duration is 10_000ms' do
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
  
    reminder.update!(duration: 10_000)
  
    ActivateRelayJob.new.perform(reminder.id)
  
    scheduled_job = TurnOffRelayJob.jobs.find do |job|
      job['args'] == [device.chip_id, reminder.relay_index]
    end
  
    expect(scheduled_job).to be_present
  
    time_diff = scheduled_job['at'].to_i - Time.now.to_i
    expect(time_diff).to be_within(1).of(10)
  end
  
  
  
end

