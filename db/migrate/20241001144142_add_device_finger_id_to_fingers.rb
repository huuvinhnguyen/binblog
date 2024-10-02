class AddDeviceFingerIdToFingers < ActiveRecord::Migration[7.0]
  def change
    add_column :fingers, :device_finger_id, :string, null: true
    add_index :fingers, :device_finger_id, unique: true
  end
end
