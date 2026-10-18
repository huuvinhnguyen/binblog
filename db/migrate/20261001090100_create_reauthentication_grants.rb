class CreateReauthenticationGrants < ActiveRecord::Migration[7.0]
  def change
    create_table :reauthentication_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.binary :token_digest, limit: 32, null: false
      t.binary :session_binding_digest, limit: 32, null: false
      t.string :purpose, limit: 64, null: false
      t.string :method, limit: 32, null: false
      t.string :provider, limit: 32
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :reauthentication_grants, :token_digest, unique: true
    add_index :reauthentication_grants, :expires_at
    add_index :reauthentication_grants, [:user_id, :purpose]
  end
end
