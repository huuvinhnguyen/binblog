class CreateUsersEmployeesJoinTable < ActiveRecord::Migration[7.0]
  def change
    create_table :employees_users, id: false do |t|
      t.belongs_to :user
      t.belongs_to :employee
    end
    add_index :employees_users, [:user_id, :employee_id], unique: true
  end
end
