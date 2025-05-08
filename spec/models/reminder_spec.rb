# spec/models/reminder_spec.rb
require 'rails_helper'
require 'active_support/testing/time_helpers'

RSpec.describe Reminder, type: :model do
  let(:device) { Device.create!(name: "Test Device", chip_id: SecureRandom.hex(4)) }


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
  end
end
