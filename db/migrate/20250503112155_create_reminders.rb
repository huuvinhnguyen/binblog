class CreateReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :reminders do |t|
      t.references :device, null: false, foreign_key: true
      t.integer :relay_index
      t.string :start_time
      t.integer :duration
      t.string :repeat_type
      t.datetime :last_triggered_at

      t.timestamps
    end
  end
end
