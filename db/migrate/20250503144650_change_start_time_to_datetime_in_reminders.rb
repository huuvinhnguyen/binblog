class ChangeStartTimeToDatetimeInReminders < ActiveRecord::Migration[7.0]
  def change
    change_column :reminders, :start_time, :datetime
  end
end
