class AddDisabledAtToUserIdentities < ActiveRecord::Migration[7.0]
  def change
    add_column :user_identities, :disabled_at, :datetime
    add_index :user_identities, [:user_id, :disabled_at]
  end
end
