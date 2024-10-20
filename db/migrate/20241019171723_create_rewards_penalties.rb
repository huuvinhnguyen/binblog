class CreateRewardsPenalties < ActiveRecord::Migration[7.0]
  def change
    create_table :rewards_penalties do |t|
      t.bigint :employee_id, null: false
      t.string :description
      t.decimal :amount, precision: 12, scale: 2, null:false
      t.boolean :penalty, default: false
      t.date :date, null: false

      t.timestamps
    end

    add_foreign_key :rewards_penalties, :employees
    add_index :rewards_penalties, :employee_id
  end
end
