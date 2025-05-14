class AddJobJidToReminders < ActiveRecord::Migration[7.0]
  def change
    add_column :reminders, :job_jid, :string
  end
end
