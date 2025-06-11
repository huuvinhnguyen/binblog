# spec/services/switch_on_duration_service_spec.rb
require 'rails_helper'

RSpec.describe SwitchOnDurationService, type: :service do
  let(:device) do
    Device.create!(
      chip_id: "esp_test_123",
      device_info: {
        relays: [
          { switch_value: 0, longlast: 1000, is_reminders_active: true, reminders: [] }
        ]
      }.to_json
    )
  end

  describe "#call" do
    context "when longlast is zero" do
      it "immediately performs TurnOffRelayJob" do
        expect(SwitchOffDurationJob).to receive(:perform_async).with(device.chip_id, 0)

        service = SwitchOnDurationService.new(device.chip_id, longlast: 0, relay_index: 0)
        service.call

        info = JSON.parse(device.reload.device_info)
        relays = info["relays"]
        expect(relays).to be_an(Array)
        expect(relays[0]["switch_value"]).to eq(1)
        expect(info["update_at"]).to be_present
      end
    end

    context "when longlast is greater than 0" do
      it "schedules SwitchOffDurationJob with delay" do
        expect(SwitchOffDurationJob).to receive(:perform_in).with(5, device.chip_id, 0)

        service = SwitchOnDurationService.new(device.chip_id, longlast: 5000, relay_index: 0)
        service.call

        info = JSON.parse(device.reload.device_info)
        relays = info["relays"]
        expect(relays).to be_an(Array)
        expect(relays[0]["switch_value"]).to eq(1)
        expect(info["update_at"]).to be_present
      end
    end

    context "when relay_index is out of bounds" do
      it "does nothing" do
        expect(SwitchOffDurationJob).not_to receive(:perform_async)
        expect(SwitchOffDurationJob).not_to receive(:perform_in)

        service = SwitchOnDurationService.new(device.chip_id, longlast: 5000, relay_index: 5)
        service.call

        info = JSON.parse(device.reload.device_info)
        expect(info["relays"][0]["switch_value"]).to eq(0)
      end
    end
  end
end
