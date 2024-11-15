class AddDeviceInfoToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :device_info, :text
  end
end
