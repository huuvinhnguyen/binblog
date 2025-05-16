class CreateRelayLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :relay_logs do |t|
      t.references :device, null: false, foreign_key: true
      t.integer :relay_index, null: false, comment: "Chỉ số relay trên thiết bị"
      t.datetime :turn_on_at, comment: "Thời điểm bật relay"
      t.datetime :turn_off_at, comment: "Thời điểm tắt relay"
      t.string :triggered_by, comment: "Ai hoặc cái gì đã kích hoạt (user, schedule, mqtt)"
      t.string :command_source, comment: "Nguồn gửi lệnh thực tế (web_ui, api, fingerprint...)"
      t.boolean :relay_status, comment: "Trạng thái sau khi tác vụ xảy ra (true=bật, false=tắt)"
      t.references :user, foreign_key: true, comment: "Nếu có người dùng thao tác"
      t.text :note, comment: "Ghi chú thêm"
      t.boolean :processed, default: false, comment: "Đã xử lý xong chưa (dùng cho đồng bộ)"
      t.text :error_message, comment: "Lưu lỗi nếu có"
      
      t.timestamps
    end
    
    add_index :relay_logs, [:device_id, :relay_index]
  end
end
