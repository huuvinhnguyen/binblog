class RenameSerialNumberToChipIdInDevices < ActiveRecord::Migration[7.0]
  def change
    # Rename the serial_number column to chip_id
    rename_column :devices, :serial_number, :chip_id
    
    # Set chip_id to NOT NULL
    change_column_null :devices, :chip_id, false

    # Add a unique index on chip_id for faster searching
    add_index :devices, :chip_id, unique: true
  end
end
