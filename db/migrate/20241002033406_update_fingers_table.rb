class UpdateFingersTable < ActiveRecord::Migration[7.0]
  def change
    # Remove the unique index on fingerprint_template and finger_id
    remove_index :fingers, :fingerprint_template if index_exists?(:fingers, :fingerprint_template)
    remove_index :fingers, :finger_id if index_exists?(:fingers, :finger_id)

    # Change fingerprint_template to be nullable
    change_column_null :fingers, :fingerprint_template, true
  end
end
