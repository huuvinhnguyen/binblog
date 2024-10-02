class ChangeFingerIdTypeInFingers < ActiveRecord::Migration[7.0]
  def up
    # Remove the index on the old finger_id column
    # remove_index :fingers, :finger_id

    # Add a new temporary column to hold integer finger_id values
    add_column :fingers, :new_finger_id, :bigint

    # Copy the data from the old string finger_id to the new integer column
    Finger.reset_column_information
    Finger.find_each do |finger|
      finger.update_column(:new_finger_id, finger.finger_id.to_i)
    end

    # Remove the old string finger_id column
    remove_column :fingers, :finger_id

    # Rename the new integer column to finger_id
    rename_column :fingers, :new_finger_id, :finger_id

    # Re-add the index on the new finger_id column
    add_index :fingers, :finger_id
  end

  def down
    # To reverse this, first remove the index
    remove_index :fingers, :finger_id

    # Add a temporary string column to restore the old data
    add_column :fingers, :old_finger_id, :string

    # Copy data back from the integer column
    Finger.reset_column_information
    Finger.find_each do |finger|
      finger.update_column(:old_finger_id, finger.finger_id.to_s)
    end

    # Remove the integer finger_id column
    remove_column :fingers, :finger_id

    # Rename the old string column back to finger_id
    rename_column :fingers, :old_finger_id, :finger_id

    # Re-add the index
    add_index :fingers, :finger_id
  end
end
