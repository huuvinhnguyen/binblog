class CreateAttendances < ActiveRecord::Migration[7.0]
  def change
    create_table :attendances do |t|
      t.references :employee, foreign_key: true
      t.date :date
      t.float :weight
      t.timestamps
    end
  end
end
