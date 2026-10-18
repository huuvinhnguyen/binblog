class CreateDeviceTriggerActionExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :device_trigger_action_executions do |t|
      t.references :device_event, null: false, foreign_key: { on_delete: :cascade }
      t.references :device_trigger_action, null: true,
                   foreign_key: { on_delete: :nullify },
                   index: { name: 'idx_trigger_executions_on_action' }
      t.references :target_device, null: true,
                   foreign_key: { to_table: :devices, on_delete: :nullify }
      t.string :action_key, null: false
      t.string :target_chip_id, null: false
      t.string :action_type, null: false
      t.integer :relay_index
      t.integer :duration_ms
      t.integer :delay_ms, null: false, default: 0
      t.integer :configured_position, null: false
      t.text :command_payload, null: false
      t.string :status, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :queued_at
      t.datetime :publish_attempted_at
      t.datetime :publish_returned_at
      t.datetime :failed_at
      t.string :error_code
      t.timestamps
    end

    add_index :device_trigger_action_executions,
              %i[device_event_id action_key],
              unique: true,
              name: 'idx_trigger_executions_event_action_key'
    add_index :device_trigger_action_executions,
              %i[target_device_id created_at],
              name: 'idx_trigger_executions_target_created'
    add_index :device_trigger_action_executions,
              %i[status created_at],
              name: 'idx_trigger_executions_status_created'
  end
end
