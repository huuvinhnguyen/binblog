class AddLastTriggeredOnToReminders < ActiveRecord::Migration[7.0]
  def change
    add_column :reminders, :last_triggered_on, :date
    add_index  :reminders, :last_triggered_on
  end
end
