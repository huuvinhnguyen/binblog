class AddEnabledToReminders < ActiveRecord::Migration[7.0]
  def change
    add_column :reminders, :enabled, :boolean, default: true, null: false
  end
end
