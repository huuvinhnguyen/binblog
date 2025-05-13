
# spec/controllers/devices_controller_spec.rb
require 'rails_helper'

RSpec.describe DevicesController, type: :controller do
  let(:device) { create(:device, chip_id: 'device123') }
  let(:device_info) { { "relays" => [{"is_reminders_active" => false}, {"is_reminders_active" => false}] }.to_json }
  
  before do
    # Giả sử device_info ban đầu có giá trị
    device.update(device_info: device_info)
  end

end
