class AddDeviceTypeToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :device_type, :string
  end
end
