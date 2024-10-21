class CreateDevicesUsersJoinTable < ActiveRecord::Migration[7.0]
  def change
    create_join_table :devices, :users do |t|
      # t.index [:device_id, :user_id]
      # t.index [:user_id, :device_id]
    end
  end
end
