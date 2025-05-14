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
        it "calculates and schedules the turn off job based on duration" do
          frozen_time = Time.zone.local(2025, 5, 12, 16, 10, 0)
      
          travel_to(frozen_time) do
            # Giả lập reminder sao cho turn_off_time nằm trong khoảng hợp lệ
            reminder = create(
              :reminder,
              device: device,
              start_time: frozen_time - 1.minute, # next_trigger_time = 16:09
              repeat_type: "daily",
              duration: 60, # => turn_off_time = 16:10
              relay_index: 1,
              enabled: true
            )
      
            allow_any_instance_of(Reminder).to receive(:next_trigger_time).and_return(frozen_time - 1.minute)
            allow_any_instance_of(Reminder).to receive(:turn_off_time).and_return(frozen_time)
      
            expect(TurnOffRelayJob).to receive(:perform_at).with(frozen_time, reminder.device.chip_id, reminder.relay_index)
      
            ReminderCronWorker.new.perform
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
      
  end
end
