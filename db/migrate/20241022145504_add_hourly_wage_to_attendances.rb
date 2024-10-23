class AddHourlyWageToAttendances < ActiveRecord::Migration[7.0]
  def change
    add_column :attendances, :hourly_wage, :decimal, precision: 12
  end
end
