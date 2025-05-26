# spec/models/reminder_spec.rb
require 'rails_helper'
require 'active_support/testing/time_helpers'

RSpec.describe Reminder, type: :model do
  let(:device) { Device.create!(name: "Test Device", chip_id: SecureRandom.hex(4)) }
  include ActiveSupport::Testing::TimeHelpers

  let(:reminder) { create(:reminder, device: device) }


  around do |example|
    original_time_zone = Time.zone
    Time.zone = 'Asia/Ho_Chi_Minh'
    example.run
    Time.zone = original_time_zone
  end

  describe '#next_trigger_time' do
    it 'calculates next daily trigger correctly' do
      reminder = Reminder.new(
        start_time: Time.zone.now.change(hour: 10, min: 0),
        relay_index: 0,
        repeat_type: 'daily',
        device: device
      )

      expected_time = if Time.zone.now < reminder.start_time
                        Time.zone.now.change(hour: 10, min: 0)
                      else
                        Time.zone.now.change(hour: 10, min: 0) + 1.day
                      end

      expect(reminder.next_trigger_time.to_i).to eq(expected_time.to_i)
    end

    it "calculates next weekly trigger correctly" do
        # Giả định hôm nay là thứ Hai (wday = 1)
        travel_to Time.zone.local(2025, 5, 5, 10, 0, 0) do # Thứ Hai
          start_time = Time.zone.local(2025, 5, 6, 8, 0, 0) # Thứ Ba
          reminder = Reminder.new(
            start_time: start_time,
            repeat_type: "weekly",
            relay_index: 0,
            device: device
          )
      
          expected_time = reminder.next_trigger_time
          expect(expected_time.wday).to eq(2) # Thứ Ba là 2
          expect(expected_time.hour).to eq(8)
          expect(expected_time.min).to eq(0)
          expect(expected_time).to be > Time.zone.now
        end
    end
      

    it 'calculates next monthly trigger correctly for valid day' do
      today = Time.zone.today
      start_day = [today.day, 28].min # limit to 28 to avoid invalid date
      reminder = Reminder.new(
        start_time: Time.zone.local(today.year, today.month, start_day, 9, 0, 0),
        relay_index: 0,
        repeat_type: 'monthly',
        device: device
      )

      next_month = today.next_month
      expected_time = Time.zone.local(next_month.year, next_month.month, start_day, 9, 0, 0)

      expect(reminder.next_trigger_time).to eq(expected_time)
    end

    it 'returns nil if monthly repeat has invalid day (e.g. 31 Feb)' do
      reminder = Reminder.new(
        start_time: Time.zone.local(2025, 1, 31, 10, 0, 0),
        relay_index: 0,
        repeat_type: 'monthly',
        device: device
      )

      # February 2025 has only 28 days
      expect(reminder.next_trigger_time).to be_nil
    end

    it 'returns start_time for repeat_type once' do
      time = Time.zone.local(2025, 5, 5, 15, 0, 0)
      reminder = Reminder.new(
        start_time: time,
        relay_index: 0,
        repeat_type: 'once',
        device: device
      )

      expect(reminder.next_trigger_time).to eq(time)
    end

    it 'returns future time for once type if start_time is in future' do
      time = 1.day.from_now.change(hour: 12)
      reminder = Reminder.new(
        start_time: time,
        relay_index: 0,
        repeat_type: 'once',
        device: device
      )

      expect(reminder.next_trigger_time).to eq(time)
    end

    it 'returns past time for once type if start_time is in past' do
      time = 2.hours.ago
      reminder = Reminder.new(
        start_time: time,
        relay_index: 0,
        repeat_type: 'once',
        device: device
      )

      expect(reminder.next_trigger_time).to eq(time)
    end

    it 'returns nil for unknown repeat_type' do
      reminder = Reminder.new(
        start_time: Time.zone.now,
        relay_index: 0,
        repeat_type: 'yearly',
        device: device
      )

      expect(reminder.next_trigger_time).to be_nil
    end

    context "when start_time is invalid" do
        it "returns nil if start_time is not a valid time" do
          reminder.update(start_time: nil)
          next_time = reminder.next_trigger_time
          expect(next_time).to be_nil
        end
    end
  end

  describe "#turn_off_time" do
    context "when duration is nil" do
      it "returns nil" do
        reminder = Reminder.new(
          device: device,
          relay_index: 0,
          start_time: 10.minutes.from_now,
          repeat_type: "once",
          duration: nil,
          enabled: true
        )

        expect(reminder.turn_off_time).to be_nil
      end
    end

    context "when duration is less than or equal to 0" do
      it "returns nil" do
        reminder = Reminder.new(
          device: device,
          relay_index: 0,
          start_time: 10.minutes.from_now,
          repeat_type: "once",
          duration: 0,
          enabled: true
        )

        expect(reminder.turn_off_time).to be_nil
      end
    end

    context "when trigger time is nil" do
      it "returns nil" do
        reminder = Reminder.new(
          device: device,
          relay_index: 0,
          start_time: nil,
          repeat_type: "once",
          duration: 60,
          enabled: true
        )

        expect(reminder.turn_off_time).to be_nil
      end
    end
  end

  describe "#schedule_immediate_job_if_soon" do
    context "when next_trigger_time is within 5 minutes" do
      it "calls schedule_next_job!" do
        reminder = Reminder.new(
          device: device,
          relay_index: 0,
          start_time: 4.minutes.from_now,  # within 5 minutes
          repeat_type: "once",
          duration: 60,
          enabled: true
        )

        allow(reminder).to receive(:schedule_next_job!)
        reminder.send(:schedule_immediate_job_if_soon)

        expect(reminder).to have_received(:schedule_next_job!)
      end
    end

    context "when next_trigger_time is more than 5 minutes away" do
      it "does not call schedule_next_job!" do
        reminder = Reminder.new(
          device: device,
          relay_index: 0,
          start_time: 10.minutes.from_now, # beyond 5 minutes
          repeat_type: "once",
          duration: 60,
          enabled: true
        )

        allow(reminder).to receive(:schedule_next_job!)
        reminder.send(:schedule_immediate_job_if_soon)

        expect(reminder).not_to have_received(:schedule_next_job!)
      end
    end

    context "when next_trigger_time is nil" do
      it "does not call schedule_next_job!" do
        reminder = Reminder.new(
          device: device,
          relay_index: 0,
          start_time: nil,
          repeat_type: "once",
          duration: 60,
          enabled: true
        )

        allow(reminder).to receive(:schedule_next_job!)
        reminder.send(:schedule_immediate_job_if_soon)

        expect(reminder).not_to have_received(:schedule_next_job!)
      end
    end
  end

  describe '#schedule_turn_off_job!' do
        it 'schedules TurnOffRelayJob and sets turn_off_jid if duration is valid' do
            reminder = Reminder.create!(
            device: device,
            relay_index: 0,
            start_time: 1.minute.from_now,
            repeat_type: 'once',
            duration: 60_000, # 1 minute
            enabled: true
            )

            allow(reminder).to receive(:update)
            allow(TurnOffRelayJob).to receive(:perform_at).and_return("fake-turnoff-jid")

            reminder.send(:schedule_immediate_job_if_soon)

            expect(reminder).to have_received(:update).with(hash_including(turn_off_jid: "fake-turnoff-jid"))
        end
    end

    describe '#cancel_scheduled_job!' do
        it 'does nothing if jobs not found in Sidekiq' do
            reminder = Reminder.create!(
            device: device,
            relay_index: 0,
            start_time: 5.minutes.from_now,
            repeat_type: 'once',
            duration: 60_000,
            enabled: true,
            job_jid: "nonexistent-job-jid",
            turn_off_jid: "nonexistent-turnoff-jid"
            )

            scheduled_set = double("Sidekiq::ScheduledSet")
            allow(Sidekiq::ScheduledSet).to receive(:new).and_return(scheduled_set)
            allow(scheduled_set).to receive(:find).and_return(nil)

            expect {
            reminder.cancel_scheduled_job!
            }.not_to raise_error
        end
    end

    describe '#cancel_scheduled_job!' do
      let(:reminder) {
        Reminder.create!(
          device: device,
          relay_index: 0,
          start_time: 1.minute.from_now,
          repeat_type: 'once',
          duration: 60_000,
          enabled: true,
          job_jid: 'fake-activate-jid',
          turn_off_jid: 'fake-turnoff-jid'
        )
      }

      let(:scheduled_set) { instance_double(Sidekiq::ScheduledSet) }
      let(:fake_activate_job) { instance_double(Sidekiq::JobRecord, jid: 'fake-activate-jid', delete: true) }
      let(:fake_turnoff_job) { instance_double(Sidekiq::JobRecord, jid: 'fake-turnoff-jid', delete: true) }

      before do
        allow(Sidekiq::ScheduledSet).to receive(:new).and_return([fake_activate_job, fake_turnoff_job])
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
      end

      it 'deletes the scheduled ActivateRelayJob if it exists' do
        reminder.cancel_scheduled_job!
        expect(Rails.logger).to have_received(:info).with("Đã huỷ ActivateRelayJob fake-activate-jid cho reminder #{reminder.id}")
      end

      it 'deletes the scheduled TurnOffRelayJob if it exists' do
        reminder.cancel_scheduled_job!
        expect(Rails.logger).to have_received(:info).with("Đã huỷ TurnOffRelayJob fake-turnoff-jid cho reminder #{reminder.id}")
      end

      context 'when jobs are not found in the scheduled set' do
        before do
          allow(Sidekiq::ScheduledSet).to receive(:new).and_return([])
        end

        it 'logs warning for missing ActivateRelayJob' do
          reminder.cancel_scheduled_job!
          expect(Rails.logger).to have_received(:warn).with("Không tìm thấy ActivateRelayJob fake-activate-jid để huỷ cho reminder #{reminder.id}")
        end

        it 'logs warning for missing TurnOffRelayJob' do
          reminder.cancel_scheduled_job!
          expect(Rails.logger).to have_received(:warn).with("Không tìm thấy TurnOffRelayJob fake-turnoff-jid để huỷ cho reminder #{reminder.id}")
        end
      end
    end

    describe '#should_turn_on?' do
      let(:now) { Time.zone.local(2025, 5, 25, 12, 0, 0) }

      before { travel_to(now) }
      after { travel_back }

      shared_examples 'returns true' do
        it 'returns true' do
          expect(reminder.should_turn_on?(now)).to be true
        end
      end

      shared_examples 'returns false' do
        it 'returns false' do
          expect(reminder.should_turn_on?(now)).to be false
        end
      end

      context 'when repeat_type is once' do
        context 'within 5-minute window and not triggered' do
          let(:reminder) do
            Reminder.new(start_time: now, repeat_type: 'once', last_triggered_at: nil)
          end
          include_examples 'returns true'
        end

        context 'outside 5-minute window' do
          let(:reminder) do
            Reminder.new(start_time: now + 10.minutes, repeat_type: 'once', last_triggered_at: nil)
          end
          include_examples 'returns false'
        end

        context 'already triggered' do
          let(:reminder) do
            Reminder.new(start_time: now, repeat_type: 'once', last_triggered_at: now)
          end
          include_examples 'returns false'
        end
      end

      context 'when repeat_type is daily' do
        context 'start_time matches now time, and not triggered' do
          let(:reminder) do
            Reminder.new(start_time: now.change(hour: 12, min: 0), repeat_type: 'daily', last_triggered_at: nil)
          end
          include_examples 'returns true'
        end

        context 'already triggered today' do
          let(:reminder) do
            Reminder.new(
              start_time: now.change(hour: 12, min: 0),
              repeat_type: 'daily',
              last_triggered_at: now
            )
          end
          include_examples 'returns false'
        end
      end

      context 'when repeat_type is weekly' do
        context 'start_time matches current weekday and time' do
          let(:start_time) { now.change(hour: 12, min: 0).advance(days: -(now.wday)) }
          let(:reminder) do
            Reminder.new(start_time: start_time, repeat_type: 'weekly', last_triggered_at: nil)
          end
          include_examples 'returns true'
        end

        context 'already triggered for this week' do
          let(:start_time) { now.change(hour: 12, min: 0).advance(days: -(now.wday)) }
          let(:reminder) do
            Reminder.new(start_time: start_time, repeat_type: 'weekly', last_triggered_at: now)
          end
          include_examples 'returns false'
        end
      end

      # context 'when repeat_type is monthly' do
      #   let(:start_time) { Time.zone.local(2025, 5, 25, 12, 0, 0) }
      
      #   let(:now) { Time.zone.local(2025, 6, 25, 12, 0, 0) } # next month, same day/time
      
      #   let(:reminder) do
      #     Reminder.new(
      #       start_time: start_time,
      #       repeat_type: 'monthly',
      #       last_triggered_at: nil
      #     )
      #   end
      
      #   it 'returns true' do
      #     puts "Start time: #{start_time}"
      #     puts "Now: #{now}"
      #     puts "Next trigger: #{reminder.next_trigger_time}"
      #     expect(reminder.should_turn_on?(now)).to be true
      #   end
      # end
      
      

      context 'when start_time is not a valid time object' do
        let(:reminder) do
          Reminder.new(start_time: 'invalid', repeat_type: 'daily', last_triggered_at: nil)
        end
        include_examples 'returns false'
      end
    end
end
