class RemoveUniqueConstraintFromFingerIdInFingers < ActiveRecord::Migration[7.0]
  def change
    # Remove the unique index on finger_id
    remove_index :fingers, :finger_id if index_exists?(:fingers, :finger_id)

    # Re-add the index without the unique constraint
    add_index :fingers, :finger_id unless index_exists?(:fingers, :finger_id)
  end
end
