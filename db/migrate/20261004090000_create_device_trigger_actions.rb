class CreateDeviceTriggerActions < ActiveRecord::Migration[7.0]
  def change
    create_table :device_trigger_actions do |t|
      t.references :source_device, null: false, foreign_key: { to_table: :devices, on_delete: :cascade }
      t.references :target_device, null: false, foreign_key: { to_table: :devices, on_delete: :cascade }
      t.string :action_type, null: false
      t.integer :relay_index, null: false
      t.integer :duration_ms, null: false
      t.integer :delay_ms, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false
      t.timestamps
    end

    add_index :device_trigger_actions,
              %i[source_device_id target_device_id action_type],
              unique: true,
              name: 'idx_trigger_actions_unique_target'
    add_index :device_trigger_actions,
              %i[source_device_id enabled position id],
              name: 'idx_trigger_actions_runtime_order'
  end
end
