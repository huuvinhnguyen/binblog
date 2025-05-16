class AddUrlFirmwareAndNoteToDevices < ActiveRecord::Migration[7.0]
  def change
    add_column :devices, :url_firmware, :string, comment: "URL dùng để tải firmware mới cho thiết bị"
    add_column :devices, :note, :text, comment: "Ghi chú thêm cho thiết bị"
  end
end