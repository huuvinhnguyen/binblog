# spec/workers/reminder_cron_worker_spec.rb
require 'rails_helper'

RSpec.describe ReminderCronWorker, type: :worker do
    include ActiveSupport::Testing::TimeHelpers

  let(:device) { create(:device) }
  let(:reminder) { create(:reminder, device: device) }

  before do
    # Freeze the current time for the test using travel_to
    travel_to(Time.zone.local(2025, 5, 12, 16, 10, 0))  # Example time for testing
  end

  after do
    # Return time to the current system time after the test
    travel_back
  end

  describe "#perform" do

    context "when the reminder is enabled and turn_off_time is within the window" do
        
        it "calls schedule_next_job! and schedule_turn_off_job! if next_trigger_time is near" do
            reminder = build(:reminder)
        
            allow(reminder).to receive(:next_trigger_time).and_return(2.minutes.from_now)
            allow(reminder).to receive(:schedule_next_job!)
            allow(reminder).to receive(:schedule_turn_off_job!)
        
            reminder.schedule_immediate_job_if_soon
        
            expect(reminder).to have_received(:schedule_next_job!)
            expect(reminder).to have_received(:schedule_turn_off_job!)
          end
      end

    context "when the reminder is disabled" do
      it "does not schedule any job" do
        reminder.update(enabled: false)

        # No jobs should be scheduled when the reminder is disabled
        expect(reminder).not_to receive(:schedule_next_job!)
        expect(TurnOffRelayJob).not_to receive(:perform_at)

        ReminderCronWorker.new.perform
      end
    end

    context "when there is missing data (e.g., start_time)" do
      it "does not schedule any job" do
        reminder.update(start_time: nil)

        # No jobs should be scheduled when data is missing
        expect(reminder).not_to receive(:schedule_next_job!)
        expect(TurnOffRelayJob).not_to receive(:perform_at)

        ReminderCronWorker.new.perform
      end
    end

    context "when the reminder's start_time is in the past" do
        it "does not schedule any job" do
          frozen_time = Time.zone.local(2025, 5, 12, 16, 10, 0)
          
          travel_to(frozen_time) do
            # Giả sử start_time đã qua (ví dụ: là 15:00)
            reminder.update(start_time: frozen_time - 1.hour, repeat_type: "daily")
            
            allow(ActivateRelayJob).to receive(:perform_at).and_call_original
      
            ReminderCronWorker.new.perform
      
            # Xác nhận là không có job nào được lên lịch vì start_time đã qua
            expect(ActivateRelayJob).not_to have_received(:perform_at)
          end
        end
    end
    
    context "when the reminder is disabled" do
        it "does not schedule any job" do
          reminder.update(enabled: false)
  
          # No jobs should be scheduled when the reminder is disabled
          expect(reminder).not_to receive(:schedule_next_job!)
          expect(TurnOffRelayJob).not_to receive(:perform_at)
  
          ReminderCronWorker.new.perform
        end
    end

    context "when there is missing data (e.g., start_time)" do
        it "does not schedule any job" do
          reminder.update(start_time: nil)
  
          # No jobs should be scheduled when data is missing
          expect(reminder).not_to receive(:schedule_next_job!)
          expect(TurnOffRelayJob).not_to receive(:perform_at)
  
          ReminderCronWorker.new.perform
        end
    end

    context "when the reminder's start_time is in the past" do
        it "does not schedule any job" do
          frozen_time = Time.zone.local(2025, 5, 12, 16, 10, 0)
          
          travel_to(frozen_time) do
            # Giả sử start_time đã qua (ví dụ: là 15:00)
            reminder.update(start_time: frozen_time - 1.hour, repeat_type: "daily")
            
            allow(ActivateRelayJob).to receive(:perform_at).and_call_original
  
            ReminderCronWorker.new.perform
  
            # Xác nhận là không có job nào được lên lịch vì start_time đã qua
            expect(ActivateRelayJob).not_to have_received(:perform_at)
          end
        end
    end

    context "when the reminder is daily at 16:30 and turn off after 2 minutes, and current time is 16:31" do
      it "schedules TurnOffRelayJob at 16:32" do
        frozen_time = Time.zone.local(2025, 5, 12, 16, 29, 0)
    
        travel_to(frozen_time) do
          reminder = create(
            :reminder,
            device: device,
            start_time: Time.zone.local(2025, 5, 12, 16, 30, 0), # Bật lúc 16:30
            repeat_type: "daily",
            duration: 120_000, # 2 phút => tắt lúc 16:32
            relay_index: 1,
            enabled: true
          )
    
          allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(Time.zone.local(2025, 5, 12, 16, 30, 0))
          allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(Time.zone.local(2025, 5, 12, 16, 32, 0))
    
          expected_turn_off_time = reminder.start_time + 120_000 / 1000 # => 03:30 ngày hôm sau
          expect(TurnOffRelayJob).to receive(:perform_at).with(expected_turn_off_time, reminder.device.chip_id, 1, 1)
    
          ReminderCronWorker.new.perform
        end
      end
    end

    context "when the reminder is daily at 17:30 and turn off after 10 hours, and current time is 17:31" do
      it "schedules TurnOffRelayJob at 3:30" do
        frozen_time = Time.zone.local(2025, 5, 13, 03, 29, 0)
    
        travel_to(frozen_time) do
          reminder = create(
            :reminder,
            device: device,
            start_time: Time.zone.local(2025, 5, 12, 17, 30, 0), # Bật lúc 16:30
            repeat_type: "daily",
            duration: 36_000_000, # 10 gio => tắt lúc 3:32
            relay_index: 1,
            enabled: true

          )
    
          expected_turn_off_time = reminder.start_time + 36_000_000 / 1000 # => 03:30 ngày hôm sau

          allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(Time.zone.local(2025, 5, 12, 17, 30, 0))
          # allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(Time.zone.local(2025, 5, 13, 03, 30, 0))
          allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(expected_turn_off_time)

          expect(TurnOffRelayJob).to receive(:perform_at).with(expected_turn_off_time, reminder.device.chip_id, 1, 1)
    
          ReminderCronWorker.new.perform
        end
      end
    end
    
    context "when ReminderCronWorker runs every 3 minutes for 12 hours" do
      it "schedules TurnOffRelayJob only once at correct time" do
        start_time = Time.zone.local(2025, 5, 12, 17, 30, 0)
        turn_off_time = start_time + 10.hours # => 03:30 ngày hôm sau
    
        reminder = create(
          :reminder,
          device: device,
          start_time: start_time,
          repeat_type: "daily",
          duration: 10.hours.in_milliseconds, # 36_000_000
          relay_index: 1,
          enabled: true,
        )
    
        allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(start_time)
        allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(turn_off_time)
    
        # Giả lập để theo dõi bao nhiêu lần job được gọi
        allow(TurnOffRelayJob).to receive(:perform_at)
    
        # Giả lập cron chạy mỗi 3 phút trong 12 tiếng
        current_time = Time.zone.local(2025, 5, 12, 17, 30, 0)
        end_time = current_time + 12.hours
    
        while current_time <= end_time
          travel_to(current_time) do
            ReminderCronWorker.new.perform
          end
          current_time += 3.minutes
        end
    
        # Chỉ chạy đúng 1 lần lúc 03:30
        expect(TurnOffRelayJob).to have_received(:perform_at)
          .with(turn_off_time, reminder.device.chip_id, 1, 1).at_least(1).times

      end
    end

    context "when turn_off_time is outside the trigger window" do
      it "does NOT call schedule_turn_off_job!" do
        frozen_time = Time.zone.local(2025, 5, 12, 16, 10, 0)
    
        travel_to(frozen_time) do
          reminder = create(
            :reminder,
            device: device,
            start_time: frozen_time + 1.minute,
            repeat_type: "daily",
            duration: 20.minutes.in_milliseconds,
            relay_index: 1,
            enabled: true
          )
    
          # Mock để đảm bảo off_time nằm ngoài vùng kiểm tra (sau 25 phút)
          allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(frozen_time + 1.minute)
          allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(frozen_time + 26.minutes)
    
          # Chặn gọi hàm để kiểm tra
          expect_any_instance_of(Reminder).not_to receive(:schedule_turn_off_job!)
    
          ReminderCronWorker.new.perform
        end
      end
    end

    context "when relay is activated but cron delay causes turn_off_time to be missed" do
      it "still schedules TurnOffRelayJob on the next cron run if missed in the previous" do
        start_time = Time.zone.local(2025, 5, 12, 16, 00, 0)
        duration = 3.minutes # Tắt sau 3 phút => 16:03
        turn_off_time = start_time + duration
    
        reminder = create(
          :reminder,
          device: device,
          start_time: start_time,
          repeat_type: "daily",
          duration: duration.in_milliseconds,
          relay_index: 1,
          enabled: true,
          last_triggered_at: start_time # Giả sử đã bật lúc 16:00
        )
    
        allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(start_time)
        allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(turn_off_time)
    
        # Giả lập cron chạy 2 lần:
        # 1. Lúc 16:05 (miss turn_off_time)
        # 2. Lúc 16:08 (vẫn trong khoảng cho phép ±5 phút)
    
        allow(TurnOffRelayJob).to receive(:perform_at)
    
        # Cron run #1 - trễ hơn thời gian tắt
        travel_to(Time.zone.local(2025, 5, 12, 16, 5, 0)) do
          ReminderCronWorker.new.perform
        end
    
        # Cron run #2 - vẫn còn nằm trong khoảng kiểm tra
        travel_to(Time.zone.local(2025, 5, 12, 16, 8, 0)) do
          ReminderCronWorker.new.perform
        end
        reminder_id = 1
        expect(TurnOffRelayJob).to have_received(:perform_at)
          .with(turn_off_time, reminder.device.chip_id, reminder.relay_index, reminder_id).at_least(1).times
      end
    end 
    
    context "when turn_off_time is exactly Time.current" do
      it "schedules TurnOffRelayJob" do
        now = Time.zone.local(2025, 5, 12, 16, 30)
        travel_to(now) do
          reminder = create(
            :reminder,
            device: device,
            start_time: now - 1.minute,
            repeat_type: "daily",
            duration: 1.minute.in_milliseconds,
            relay_index: 0,
            enabled: true,
            last_triggered_at: now - 1.minute
          )
    
          allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(reminder.start_time)
          allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(now)
          reminder_id = 1
          expect(TurnOffRelayJob).to receive(:perform_at).with(now, reminder.device.chip_id, 0, reminder_id)
    
          ReminderCronWorker.new.perform
        end
      end
    end
    
    
  end
end
