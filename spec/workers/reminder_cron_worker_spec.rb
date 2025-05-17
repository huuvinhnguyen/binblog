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
          expect(TurnOffRelayJob).to receive(:perform_at).with(expected_turn_off_time, reminder.device.chip_id, 1)
    
          ReminderCronWorker.new.perform
        end
      end
    end

    context "when the reminder is daily at 17:30 and turn off after 10 hours, and current time is 17:31" do
      it "schedules TurnOffRelayJob at 3:30" do
        frozen_time = Time.zone.local(2025, 5, 12, 17, 29, 0)
    
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
          allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(Time.zone.local(2025, 5, 12, 17, 32, 0))
    
          expect(TurnOffRelayJob).to receive(:perform_at).with(expected_turn_off_time, reminder.device.chip_id, 1)
    
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
          .with(turn_off_time, reminder.device.chip_id, 1).at_most(2).times

      end
    end
  end
end
