class AddStartTimeToAttendances < ActiveRecord::Migration[7.0]
  def change
    add_column :attendances, :start_time, :datetime
  end
end
