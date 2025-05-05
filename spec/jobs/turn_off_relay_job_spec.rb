require 'rails_helper'

RSpec.describe TurnOffRelayJob, type: :job do
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

  it "turns off the relay by setting switch_value to 0" do
    TurnOffRelayJob.new.perform(device.chip_id, 0)

    device.reload
    info = JSON.parse(device.device_info)
    expect(info["relays"][0]["switch_value"]).to eq(0)
  end
  

end
