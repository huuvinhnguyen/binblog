class AddTurnOffJidToReminders < ActiveRecord::Migration[7.0]
  def change
    add_column :reminders, :turn_off_jid, :string
  end
end
