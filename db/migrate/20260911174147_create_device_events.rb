class CreateDeviceEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :device_events do |t|
      t.references :device, null: false, foreign_key: true
      t.string :event_type, null: false
      t.text :payload
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :device_events, [:device_id, :event_type, :occurred_at]
    add_index :device_events, :occurred_at
  end
end
