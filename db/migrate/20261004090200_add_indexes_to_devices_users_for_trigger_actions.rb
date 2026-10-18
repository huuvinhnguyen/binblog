class AddIndexesToDevicesUsersForTriggerActions < ActiveRecord::Migration[7.0]
  def change
    add_index :devices_users,
              %i[device_id user_id],
              unique: true,
              name: 'idx_devices_users_unique_device_user'
    add_index :devices_users,
              %i[user_id device_id],
              name: 'idx_devices_users_user_device'
  end
end
