class CreateDevices < ActiveRecord::Migration[7.0]
  def change
    create_table :devices do |t|
      t.string :name
      t.string :serial_number
      t.integer :status
      t.boolean :is_payment

      t.timestamps
    end
  end
end
