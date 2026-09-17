# Hướng dẫn đăng ký thiết bị Buzzer

## Mục đích

Buzzer là device có `device_type: "buzzer"`. Nó nhận MQTT command tại topic
`{chip_id}/switchon`; Buzzer không có `trigger` riêng. PIR là nguồn phát hiện
chuyển động và cấu hình `trigger` trên PIR sẽ trỏ đến Buzzer đích.

## Tạo Buzzer bằng rake

Tại thư mục ứng dụng, chạy:

```bash
bundle exec rake device:create
```

Chọn mục `3. Buzzer (alarm device)`, sau đó nhập `chip_id`, tên, ghi chú tùy
chọn, thời lượng mặc định (milliseconds) và user sở hữu nếu cần.

Ví dụ:

```text
Select device type:
1. Switch (relay device)
2. PIR (motion sensor)
3. Buzzer (alarm device)
Enter choice (1, 2, or 3):
3

Enter chip_id (e.g., esp32_buzzer_01):
ESP32_BUZZER_02
Enter device name:
Chuông phòng khách
Enter default sound duration in milliseconds (default: 1000):
1000
```

Task tạo `device_info` có `topic_type: "switchon"`, relay channel `0`, thời
lượng mặc định, và để `trigger: nil`.

## Pair một PIR với Buzzer

Pair được lưu trên PIR: `trigger.chip_id` là `chip_id` của Buzzer. Cả hai
device phải được liên kết với cùng user trước khi cấu hình.

```bash
bundle exec rails console
```

```ruby
pir = Device.find_by!(chip_id: 'ESP32_PIR_01', device_type: 'pir')
buzzer = Device.find_by!(chip_id: 'ESP32_BUZZER_02', device_type: 'buzzer')

pir.update!(
  trigger: {
    chip_id: buzzer.chip_id,
    relay_index: 0,
    switch_value: 1,
    longlast: 1000
  }.to_json
)
```

Khi PIR gọi `POST /api/devices/trigger` với `chip_id: ESP32_PIR_01`, hệ thống
lưu `motion_detected` trên PIR, bổ sung metadata Buzzer đích vào event rồi gửi
nguyên MQTT command hiện có đến `ESP32_BUZZER_02/switchon`.

## Kiểm tra giao diện

Mở trang chi tiết Buzzer. Trang hiển thị các PIR có `trigger` trỏ đến Buzzer và
20 motion event mới nhất nhắm đến chính Buzzer đó. Event lịch sử tạo
trước khi metadata `target_chip_id` được bổ sung sẽ không xuất hiện để tránh
gán nhầm PIR nguồn.

Trạng thái **Đã nhận motion** chỉ xác nhận Rails đã nhận request từ PIR và
lưu event. Nó không xác nhận MQTT publish thành công hoặc Buzzer đã phát âm;
firmware ACK là một hạng mục riêng.

## Test Buzzer thủ công

Trên trang chi tiết Buzzer, nhấn **Test Buzzer** và xác nhận thao tác. Hệ
thống dùng relay channel và thời lượng đã lưu khi tạo Buzzer để gửi MQTT command
đến `{chip_id}/switchon`.

- Chỉ user được liên kết với Buzzer (hoặc administrator) có thể dùng nút này.
- Có cooldown ngắn để tránh bấm lặp.
- Command test chỉ gửi `longlast`; firmware tự tắt Buzzer sau thời lượng đó.
- Thông báo thành công chỉ xác nhận Rails đã gửi lệnh tới MQTT broker, không
  xác nhận Buzzer đã phát âm vì firmware hiện chưa gửi ACK.
