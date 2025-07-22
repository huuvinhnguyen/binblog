class CreateUserRelayFeatures < ActiveRecord::Migration[7.0]
  def change
    create_table :user_relay_features do |t|
      t.references :user, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.string :feature, null: false
      t.boolean :enabled, null: false, default: true
      t.text :note

      t.timestamps
    end

    add_index :user_relay_features, [:user_id, :device_id, :feature], unique: true, name: "index_user_relay_features_on_user_device_feature"
  end
end
