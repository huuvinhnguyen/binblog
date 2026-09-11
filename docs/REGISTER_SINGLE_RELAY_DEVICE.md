# Hướng dẫn thêm device relay 1 kênh

## Tổng quan

Tài liệu này hướng dẫn thêm một thiết bị relay 1 kênh vào Binblog, liên kết thiết bị với người dùng và cấu hình trigger qua MQTT.

Trong hệ thống:

- `chip_id` là mã duy nhất của thiết bị.
- Device relay dùng `device_type: "switch"`.
- Relay đầu tiên có index `0`.
- Device 1 kênh phải có đúng một phần tử trong `device_info.relays`.
- Thời lượng `longlast` được tính bằng mili giây.

> Không tạo thêm record nếu `chip_id` đã tồn tại. Hãy kiểm tra và cập nhật record hiện có.

## Rake task hiện có

Kiểm tra các task mà Rails đang nạp:

```bash
bundle exec rake -T device
```

Các task hiện có:

```text
rake device:create   # Tạo đầy đủ device relay 1 kênh
rake device:delete   # Sao lưu rồi xóa device cùng dữ liệu liên quan
rake device:link     # Liên kết device với user
rake device:list     # Liệt kê các device
rake device:trigger  # Cấu hình trigger cho device
```

Task `device:delete` đã có và là cách khuyến nghị để xóa device. Task sẽ hiển thị device cùng số lượng dữ liệu liên quan, yêu cầu xác nhận chính xác, tạo file backup JSON, rồi mới xóa trong transaction. Phần **10.5** có quy trình Rails console để tham khảo hoặc sử dụng khi cần xử lý thủ công.

Task `device:create` tạo đầy đủ một device relay 1 kênh, gồm `device_info.relays` với đúng một phần tử tại index `0`, trigger `relay_indexes: [0]`, và tùy chọn liên kết với user.

## 1. Mở Rails console

### Development

```bash
bundle exec rails console
```

### Production

Chạy tại thư mục deploy của ứng dụng:

```bash
RAILS_ENV=production bundle exec rails console
```

## 2. Kiểm tra device đã tồn tại chưa

Thay giá trị `chip_id` bằng mã thực tế của thiết bị:

```ruby
chip_id = "esp8266_14522670"
device = Device.find_by(chip_id: chip_id)
```

Kiểm tra kết quả:

```ruby
device&.attributes&.slice(
  "id",
  "name",
  "chip_id",
  "device_type",
  "status"
)
```

- Nếu kết quả là `nil`, tiếp tục phần **3. Tạo device mới**.
- Nếu đã tìm thấy device, bỏ qua bước tạo và xem phần **4. Cập nhật device đã tồn tại**.

## 3. Tạo device relay 1 kênh mới

`device:create` là cách khuyến nghị. Task tạo đầy đủ record, cấu hình một relay tại index `0`, trigger MQTT và liên kết user nếu được chọn. Phần **3.2** là cách Rails console để tham khảo hoặc sử dụng khi cần tạo thủ công.

### 3.1. Tạo đầy đủ bằng rake task

Development:

```bash
bundle exec rake device:create
```

Production:

```bash
RAILS_ENV=production bundle exec rake device:create
```

Task sẽ lần lượt yêu cầu:

1. `chip_id` — bắt buộc và phải là duy nhất.
2. Tên device — bắt buộc.
3. Ghi chú — có thể để trống.
4. `longlast` tính bằng mili giây — để trống sẽ dùng `6000`.
5. Có liên kết device với user hay không.
6. Email user nếu chọn liên kết.

Ví dụ không liên kết user:

```text
Enter chip_id (e.g., esp8266_12345678):
esp8266_CHIP_ID_MOI
Enter device name:
Relay 1 kênh
Enter note [optional]:
Device relay 1 kênh
Enter longlast in milliseconds (default: 6000):
6000
Do you want to link this device to a user? (y/n):
n
✓ Single-relay device 'Relay 1 kênh' (esp8266_CHIP_ID_MOI) was successfully created.
  Device ID: 60
  Relay index: 0
  Longlast: 6000 ms
```

Ví dụ có liên kết user:

```text
Do you want to link this device to a user? (y/n):
y
Enter user email:
trongtri@gmail.com
```

Nếu email không tồn tại, task dừng và không tạo device dang dở. `longlast` chỉ chấp nhận số nguyên không âm.

Task tự động lưu:

- `device_type: "switch"`.
- `status: 1` và `is_payment: false`.
- `device_info.relays` có đúng một relay với `switch_value: 0`, `is_reminders_active: true` và `reminders: []`.
- `trigger.relay_indexes` bằng `[0]`.
- `trigger.chip_id` và `device_info.device_id` khớp với `device.chip_id`.
- `meta_info` là JSON object rỗng.

### 3.2. Tạo thủ công bằng Rails console

Thay tên, chip ID, thời lượng và các thông tin khác cho phù hợp:

```ruby
chip_id = "esp8266_CHIP_ID_MOI"

raise "chip_id đã tồn tại" if Device.exists?(chip_id: chip_id)

device = Device.create!(
  name: "Tên thiết bị",
  chip_id: chip_id,
  device_type: "switch",
  status: 1,
  is_payment: false,
  note: "Device relay 1 kênh",
  device_info: {
    device_type: "switch",
    topic_type: "switchon",
    device_id: chip_id,
    switch_value: nil,
    update_at: Time.current.to_i,
    longlast: nil,
    timetrigger: nil,
    relays: [
      {
        switch_value: 0,
        longlast: 6000,
        is_reminders_active: true,
        reminders: []
      }
    ],
    local_ip: "",
    build_version: 0,
    app_version: "1.0.0"
  }.to_json,
  trigger: {
    relay_indexes: [0],
    chip_id: chip_id,
    longlast: 6000
  }.to_json,
  meta_info: {}.to_json
)

puts "Đã tạo device ID #{device.id}: #{device.chip_id}"
```

### Ý nghĩa cấu hình relay

```json
{
  "switch_value": 0,
  "longlast": 6000,
  "is_reminders_active": true,
  "reminders": []
}
```

| Trường | Ý nghĩa |
| --- | --- |
| `switch_value` | Trạng thái ban đầu: `0` = tắt, `1` = bật |
| `longlast` | Thời gian bật relay, tính bằng mili giây; `6000` = 6 giây |
| `is_reminders_active` | Cho phép sử dụng lịch hẹn với relay |
| `reminders` | Danh sách lịch cũ trong JSON; khi lấy thông tin device, server sẽ đồng bộ lịch từ bảng `reminders` |

## 4. Cập nhật device đã tồn tại thành relay 1 kênh

Ví dụ với `esp8266_14522670`:

```ruby
device = Device.find_by!(chip_id: "esp8266_14522670")
info = JSON.parse(device.device_info.presence || "{}")

info["device_type"] = "switch"
info["topic_type"] = "switchon"
info["device_id"] = device.chip_id
info["update_at"] = Time.current.to_i
info["relays"] = [
  {
    "switch_value" => 0,
    "longlast" => 6000,
    "is_reminders_active" => true,
    "reminders" => []
  }
]

device.update!(
  device_type: "switch",
  device_info: info.to_json,
  trigger: {
    relay_indexes: [0],
    chip_id: device.chip_id,
    longlast: 6000
  }.to_json
)
```

> Cảnh báo: đoạn trên thay `device_info.relays` bằng đúng một relay và đặt `reminders` trong JSON thành rỗng. Nếu device đang có lịch cần giữ lại, hãy kiểm tra bảng `Reminder` trước khi cập nhật:
>
> ```ruby
> device.reminders.order(:relay_index, :start_time).pluck(
>   :id,
>   :relay_index,
>   :start_time,
>   :duration,
>   :repeat_type,
>   :enabled
> )
> ```

## 5. Cấu hình trigger cho relay 1 kênh

Trigger đúng cho device 1 kênh:

```json
{
  "relay_indexes": [0],
  "chip_id": "esp8266_14522670",
  "longlast": 6000
}
```

Cập nhật riêng trigger mà không thay đổi `device_info`:

```ruby
device = Device.find_by!(chip_id: "esp8266_14522670")

device.update!(
  trigger: {
    relay_indexes: [0],
    chip_id: device.chip_id,
    longlast: 6000
  }.to_json
)
```

Các lỗi cần tránh:

- Không dùng `[0, 1, 2, 3]` cho device 1 kênh.
- Không dùng `relay_index` lớn hơn `0`.
- Không sao chép `chip_id` từ device khác.
- JSON phải hợp lệ.

## 6. Liên kết device với user

Device cần được liên kết với user để xuất hiện trong danh sách thiết bị của user và sử dụng các chức năng liên quan.

```ruby
user = User.find_by!(email: "trongtri@gmail.com")
device = Device.find_by!(chip_id: "esp8266_14522670")

device.users << user unless device.users.exists?(id: user.id)
```

Kiểm tra:

```ruby
device.users.pluck(:id, :email)
```

## 7. Kiểm tra dữ liệu sau khi thêm

```ruby
device.reload
info = JSON.parse(device.device_info)
trigger = JSON.parse(device.trigger)

raise "Sai device_type" unless device.device_type == "switch"
raise "Sai device_id" unless info["device_id"] == device.chip_id
raise "Device phải có đúng 1 relay" unless info["relays"].is_a?(Array) && info["relays"].length == 1
raise "Relay 1 kênh chỉ dùng index 0" unless trigger["relay_indexes"] == [0]
raise "Trigger trỏ sai chip_id" unless trigger["chip_id"] == device.chip_id

puts JSON.pretty_generate(info)
puts JSON.pretty_generate(trigger)
puts device.users.pluck(:email)
puts "Cấu hình device hợp lệ"
```

## 8. Kiểm tra điều khiển relay

### Bật relay 0

```bash
curl -X POST "https://<your-domain>/api/devices/switchon" \
  -H "Content-Type: application/json" \
  --data-raw '{
    "device_id": "esp8266_14522670",
    "relay_index": 0,
    "switch_value": 1
  }'
```

### Bật relay 0 trong 6 giây

```bash
curl -X POST "https://<your-domain>/api/devices/set_longlast" \
  -H "Content-Type: application/json" \
  --data-raw '{
    "device_id": "esp8266_14522670",
    "relay_index": 0,
    "longlast": 6000
  }'
```

### Gọi trigger đã lưu

```bash
curl -X POST "https://<your-domain>/api/devices/trigger" \
  -H "Content-Type: application/json" \
  --data-raw '{
    "chip_id": "esp8266_14522670"
  }'
```

Kết quả thành công mong đợi:

```json
{
  "status": "success",
  "message": "Message sent successfully"
}
```

Khi gọi trigger, server publish JSON đã lưu trong trường `trigger` lên MQTT topic:

```text
esp8266_14522670/switchon
```

> Các endpoint điều khiển trên hiện không yêu cầu xác thực ở controller. Không nên để public trực tiếp trên Internet nếu chưa bổ sung API key, network allowlist hoặc cơ chế xác thực phù hợp.

## 9. Theo dõi hoạt động MQTT

Theo dõi log ứng dụng hoặc Sidekiq:

```bash
tail -f log/production.log | grep --line-buffered '\[MQTT\]'
```

Hoặc:

```bash
sudo journalctl -u sidekiq -f
```

Có thể subscribe topic của device để kiểm tra message:

```bash
mosquitto_sub -h khuonvien.vn \
  -t 'esp8266_14522670/switchon' \
  -v -d
```

## 10. Xóa device an toàn

Task `device:delete` là cách khuyến nghị để xóa device. Task thực hiện các bước sau:

1. Tìm device theo `chip_id`.
2. Hiển thị tên, ID, loại device, user và số lượng dữ liệu liên quan.
3. Yêu cầu nhập chuỗi xác nhận chính xác `DELETE <chip_id>`.
4. Sao lưu dữ liệu vào file JSON trong thư mục `tmp/`.
5. Hủy reminders và các Sidekiq jobs liên quan.
6. Xóa relay logs, user relay features và liên kết user.
7. Xóa device trong database transaction.

> Cảnh báo: xóa device là thao tác không thể hoàn tác trong database. Hãy kiểm tra đúng `chip_id`, môi trường và file backup trước khi kết thúc công việc.

### 10.1. Chạy rake task xóa device

Development:

```bash
bundle exec rake device:delete
```

Production:

```bash
RAILS_ENV=production bundle exec rake device:delete
```

Task sẽ hỏi `chip_id`:

```text
Enter chip_id of the device to delete:
esp8266_14522670
```

Sau đó task hiển thị thông tin để kiểm tra, ví dụ:

```text
Device to delete:
  ID: 59
  Name: C Oanh- Loa buzzer
  Chip ID: esp8266_14522670
  Type: switch
  Users: trongtri@gmail.com

Related data:
  Reminders: 0
  Relay logs: 118
  User relay features: 0
  User links: 1
  Legacy user_devices links: 0
```

Để xác nhận, phải nhập đúng cả chữ `DELETE`, một dấu cách và `chip_id`:

```text
Type 'DELETE esp8266_14522670' to confirm:
DELETE esp8266_14522670
```

Nhập sai hoặc chỉ nhấn Enter sẽ hủy thao tác:

```text
Deletion cancelled.
```

Khi thành công, task in đường dẫn file backup:

```text
✓ Device 'esp8266_14522670' was successfully deleted.
  Backup: /path/to/binblog/tmp/device-59-20260911140000-backup.json
```

> Thư mục `tmp/` không phải nơi lưu trữ bền vững. Trên production, hãy chép file backup sang nơi an toàn nếu cần giữ lâu dài.

### 10.2. Kiểm tra sau khi chạy rake task

Mở Rails console:

```bash
RAILS_ENV=production bundle exec rails console
```

Kiểm tra device không còn tồn tại:

```ruby
Device.exists?(chip_id: "esp8266_14522670")
# => false
```

Có thể kiểm tra file backup ở shell:

```bash
ls -lh tmp/device-*-backup.json
```

### 10.3. Trường hợp task dừng hoặc báo lỗi

- Nếu báo `Device ... not found`, kiểm tra lại `chip_id` và môi trường đang chạy.
- Nếu nhập sai chuỗi xác nhận, task chủ động hủy và không xóa dữ liệu.
- Nếu Redis/Sidekiq không kết nối được, callback xóa reminder có thể làm task thất bại. Hãy kiểm tra Redis/Sidekiq rồi chạy lại để scheduled jobs được hủy đúng cách.
- Nếu xảy ra lỗi trong transaction, thao tác xóa database sẽ được rollback. File backup có thể đã được tạo trước khi transaction bắt đầu.

### 10.4. Mở Rails console để xóa thủ công

Chỉ dùng phần này khi không thể chạy rake task hoặc cần kiểm soát từng bước.

Development:

```bash
bundle exec rails console
```

Production:

```bash
RAILS_ENV=production bundle exec rails console
```

### 10.5. Tìm và xác nhận device khi xóa thủ công

```ruby
chip_id = "esp8266_14522670"
device = Device.find_by!(chip_id: chip_id)

puts device.attributes.slice(
  "id",
  "name",
  "chip_id",
  "device_type",
  "status"
)
puts device.users.pluck(:id, :email)
```

Chỉ tiếp tục khi `name` và `chip_id` đúng với thiết bị cần xóa.

### 10.6. Kiểm tra dữ liệu liên quan khi xóa thủ công

```ruby
connection = ActiveRecord::Base.connection
quoted_device_id = connection.quote(device.id)

puts({
  reminders: device.reminders.count,
  relay_logs: device.relay_logs.count,
  user_relay_features: UserRelayFeature.where(device_id: device.id).count,
  user_links: device.users.count,
  legacy_user_devices: connection.select_value(
    "SELECT COUNT(*) FROM user_devices WHERE device_id = #{quoted_device_id}"
  ).to_i
})
```

Trong model hiện tại:

- `reminders` có `dependent: :destroy` nên được xóa khi gọi `device.destroy!`; callback của từng reminder cũng cố gắng hủy Sidekiq jobs liên quan.
- `relay_logs`, `user_relay_features` và bảng cũ `user_devices` không được khai báo tự động xóa cùng device.
- Liên kết HABTM trong `devices_users` nên được gỡ trước khi xóa để quy trình rõ ràng và an toàn.

### 10.7. Sao lưu record trước khi xóa thủ công

```ruby
backup = {
  device: device.attributes,
  user_ids: device.user_ids,
  reminders: device.reminders.map(&:attributes),
  relay_logs: device.relay_logs.map(&:attributes),
  user_relay_features: UserRelayFeature.where(device_id: device.id).map(&:attributes)
}

File.write(
  Rails.root.join("tmp", "device-#{device.id}-backup.json"),
  JSON.pretty_generate(backup)
)
```

Trên production, hãy chép file backup trong `tmp/` sang nơi lưu trữ bền vững nếu cần giữ lâu dài.

### 10.8. Xóa device và dữ liệu phụ thuộc thủ công

Chạy nguyên khối lệnh sau trong Rails console:

```ruby
chip_id = "esp8266_14522670"
device = Device.find_by!(chip_id: chip_id)
connection = ActiveRecord::Base.connection
quoted_device_id = connection.quote(device.id)

ActiveRecord::Base.transaction do
  # Hủy lịch và Sidekiq jobs thông qua callback Reminder#before_destroy.
  device.reminders.destroy_all

  # Xóa dữ liệu phụ thuộc không có dependent: :destroy trong Device.
  RelayLog.where(device_id: device.id).delete_all
  UserRelayFeature.where(device_id: device.id).delete_all

  # Xóa liên kết user ở cả bảng HABTM đang dùng và bảng user_devices cũ.
  device.users.clear
  connection.delete(
    "DELETE FROM user_devices WHERE device_id = #{quoted_device_id}"
  )

  device.destroy!
end
```

Lý do dùng hai kiểu xóa:

- `destroy_all` cho reminders để chạy callback hủy các scheduled jobs.
- `delete_all` cho logs và feature records vì các bảng này không cần callback khi dọn dữ liệu.

Nếu Redis/Sidekiq không kết nối được, callback xóa reminder có thể làm transaction thất bại. Khi đó không nên bỏ qua ngay; hãy kiểm tra Redis/Sidekiq để bảo đảm scheduled jobs được hủy trước khi xóa dữ liệu.

### 10.9. Xác nhận đã xóa thủ công

```ruby
raise "Device vẫn còn tồn tại" if Device.exists?(chip_id: chip_id)
puts "Đã xóa device #{chip_id}"
```

Kiểm tra thêm các record mồ côi bằng ID đã ghi nhận trước khi xóa:

```ruby
deleted_device_id = device.id
connection = ActiveRecord::Base.connection
quoted_device_id = connection.quote(deleted_device_id)

puts({
  reminders: Reminder.where(device_id: deleted_device_id).count,
  relay_logs: RelayLog.where(device_id: deleted_device_id).count,
  user_relay_features: UserRelayFeature.where(device_id: deleted_device_id).count,
  habtm_links: connection.select_value(
    "SELECT COUNT(*) FROM devices_users WHERE device_id = #{quoted_device_id}"
  ).to_i,
  legacy_user_devices: connection.select_value(
    "SELECT COUNT(*) FROM user_devices WHERE device_id = #{quoted_device_id}"
  ).to_i
})
```

Tất cả giá trị phải bằng `0`.

### 10.10. Chỉ gỡ device khỏi một user, không xóa device

Nếu mục tiêu chỉ là không cho một user quản lý device nữa, không chạy quy trình xóa ở trên:

```ruby
device = Device.find_by!(chip_id: "esp8266_14522670")
user = User.find_by!(email: "trongtri@gmail.com")

device.users.delete(user)
```

Kiểm tra:

```ruby
device.reload.users.pluck(:email)
```

Record device, cấu hình MQTT, reminders và relay logs vẫn được giữ nguyên.

## 11. Xử lý lỗi thường gặp

### `chip_id has already been taken`

Device đã tồn tại. Không tạo record mới; dùng `Device.find_by!` rồi cập nhật record hiện tại.

### `Invalid relay index`

Device 1 kênh chỉ có relay index `0`. Kiểm tra request và `device_info.relays`.

### API trigger gửi lệnh đến nhầm thiết bị

Kiểm tra `chip_id` nằm bên trong trường `trigger`:

```ruby
JSON.parse(device.trigger)["chip_id"]
```

Giá trị này phải bằng `device.chip_id`.

### `Invalid JSON format`

Kiểm tra JSON trong `trigger`:

```ruby
JSON.pretty_generate(JSON.parse(device.trigger))
```

### `Rack::Multipart::MultipartTotalPartLimitError` trong Rails Admin

Nếu form `/admin/device/:id/edit` có quá nhiều multipart fields, thao tác bằng Rails console theo hướng dẫn ở trên. Sau khi thay đổi cấu hình Rack, phải restart Rails application để cấu hình mới có hiệu lực.

### Device không xuất hiện với user

Kiểm tra quan hệ user-device:

```ruby
device.users.pluck(:email)
```

Nếu thiếu, liên kết theo phần **6. Liên kết device với user**.

## Checklist hoàn tất

- [ ] `chip_id` chính xác và duy nhất.
- [ ] `device_type` bằng `switch`.
- [ ] `device_info.device_id` bằng `device.chip_id`.
- [ ] `device_info.relays` có đúng một phần tử.
- [ ] Relay duy nhất sử dụng index `0`.
- [ ] `trigger.relay_indexes` bằng `[0]`.
- [ ] `trigger.chip_id` bằng `device.chip_id`.
- [ ] `longlast` được nhập theo mili giây.
- [ ] Device đã liên kết với đúng user.
- [ ] API/MQTT đã được kiểm tra sau khi cấu hình.

### Checklist trước khi xóa

- [ ] Đã xác nhận đúng `name`, `chip_id` và môi trường database.
- [ ] Đã kiểm tra số lượng reminders, relay logs, user features và liên kết user.
- [ ] Đã sao lưu dữ liệu cần giữ.
- [ ] Đã hủy reminders và các Sidekiq jobs liên quan.
- [ ] Đã xóa dữ liệu phụ thuộc và các liên kết user.
- [ ] Đã xác nhận device cùng toàn bộ record liên quan không còn trong database.
