require "rails_helper"

RSpec.describe ActivateRelayJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:device) do
    create(
      :device,
      device_info: {
        relays: [
          { "switch_value" => 0 },
          { "switch_value" => 0 }
        ]
      }.to_json
    )
  end

  let(:reminder) do
    create(
      :reminder,
      device: device,
      relay_index: 0,
      start_time: Time.zone.now.change(hour: 10, min: 0),
      repeat_type: "daily",
      enabled: true,
      last_triggered_on: nil
    )
  end

  before do
    # Không gọi MQTT / refresh thật
    allow_any_instance_of(ActivateRelayJob).to receive(:refresh)
  end

  describe "race condition" do
    it "triggers relay only once when 2 jobs run concurrently" do
      travel_to(Time.zone.now.change(hour: 10, min: 0)) do
        threads = []

        2.times do
          threads << Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.new.perform(reminder.id)
            end
          end
        end

        threads.each(&:join)

        reminder.reload
        device.reload

        device_info = JSON.parse(device.device_info)

        expect(device_info["relays"][0]["switch_value"]).to eq(1)
        expect(reminder.last_triggered_on).to eq(Date.current)
        expect(RelayLog.count).to eq(1)
      end
    end

    it "still triggers only once even with 5 concurrent jobs" do
      travel_to(Time.zone.now.change(hour: 10, min: 0)) do
        threads = []

        5.times do
          threads << Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.new.perform(reminder.id)
            end
          end
        end

        threads.each(&:join)

        reminder.reload
        device.reload

        device_info = JSON.parse(device.device_info)

        expect(device_info["relays"][0]["switch_value"]).to eq(1)
        expect(reminder.last_triggered_on).to eq(Date.current)
        expect(RelayLog.count).to eq(1)
      end
    end
  end
end
