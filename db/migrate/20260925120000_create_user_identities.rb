class CreateUserIdentities < ActiveRecord::Migration[7.0]
  def change
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.binary :provider_uid, limit: 1024, null: false
      t.datetime :last_authenticated_at

      t.timestamps
    end

    add_index :user_identities, [:provider, :provider_uid], unique: true,
              name: 'index_user_identities_on_provider_and_uid'
    add_index :user_identities, [:user_id, :provider], unique: true,
              name: 'index_user_identities_on_user_and_provider'
  end
end
