class CreateFingers < ActiveRecord::Migration[7.0]
  def change
    create_table :fingers do |t|
      t.string :finger_id, null: false, unique: true # Finger ID from AS608
      t.references :employee, null: false, foreign_key: true # Employee association

      t.timestamps
    end
    add_index :fingers, :finger_id, unique: true # Ensure uniqueness of the finger_id
  end
end
