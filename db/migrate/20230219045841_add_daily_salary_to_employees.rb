class AddDailySalaryToEmployees < ActiveRecord::Migration[7.0]
  def change
    add_column :employees, :daily_salary, :decimal
  end
end
