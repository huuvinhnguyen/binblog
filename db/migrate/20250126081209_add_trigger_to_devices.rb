class AddTriggerToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :trigger, :text
  end
end
