class AddMetaInfoToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :meta_info, :text
  end
end
