class CreateUserRecoveryCodes < ActiveRecord::Migration[7.0]
  def change
    create_table :user_recovery_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.binary :code_digest, limit: 32, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :user_recovery_codes, :code_digest, unique: true
    add_index :user_recovery_codes, [:user_id, :used_at]
  end
end
