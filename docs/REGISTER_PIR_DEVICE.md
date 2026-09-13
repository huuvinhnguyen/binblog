# Hướng dẫn đăng ký thiết bị PIR Motion Sensor

## Tổng quan

Tài liệu này hướng dẫn thêm một thiết bị cảm biến chuyển động PIR vào Binblog, liên kết thiết bị với người dùng và theo dõi các sự kiện phát hiện chuyển động.

Trong hệ thống:

- `chip_id` là mã duy nhất của thiết bị.
- Device PIR dùng `device_type: "pir"`.
- PIR không có cấu hình relay hoặc trigger.
- Mỗi lần phát hiện chuyển động, thiết bị gọi API `/api/devices/trigger` để ghi lại sự kiện.

> Không tạo thêm record nếu `chip_id` đã tồn tại. Hãy kiểm tra và cập nhật record hiện có.

## Rake task hiện có

Kiểm tra các task mà Rails đang nạp:

```bash
bundle exec rake -T device
```

Các task hiện có:

```text
rake device:create   # Tạo device (switch hoặc pir)
rake device:delete   # Sao lưu rồi xóa device cùng dữ liệu liên quan
rake device:link     # Liên kết device với user
rake device:list     # Liệt kê các device
```

Task `device:create` đã được cập nhật để hỗ trợ tạo cả switch và PIR. Khi chạy task, bạn sẽ được hỏi loại device muốn tạo.

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
chip_id = "esp32_87654321"
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

- Nếu kết quả là `nil`, tiếp tục phần **3. Tạo device PIR mới**.
- Nếu đã tìm thấy device, bỏ qua bước tạo và xem phần **4. Cập nhật device đã tồn tại**.

## 3. Tạo device PIR mới

Có thể tạo bằng rake task hoặc trực tiếp trong Rails console.

### 3.1. Tạo bằng rake task (Khuyến nghị)

Development:

```bash
bundle exec rake device:create
```

Production:

```bash
RAILS_ENV=production bundle exec rake device:create
```

Task sẽ hỏi:

```text
Select device type:
1. Switch (relay device)
2. PIR (motion sensor)
Enter choice (1 or 2):
2

=== Creating PIR Motion Sensor Device ===
Enter chip_id (e.g., esp32_87654321):
esp32_PIR_001

Enter device name:
Cảm biến phòng khách

Enter note [optional]:
PIR sensor phát hiện chuyển động

Do you want to link this device to a user? (y/n):
y

Enter user email:
trongtri@gmail.com
```

### 3.2. Tạo trực tiếp trong Rails console

```ruby
chip_id = "esp32_PIR_001"

raise "chip_id đã tồn tại" if Device.exists?(chip_id: chip_id)

device = Device.create!(
  name: "Cảm biến phòng khách",
  chip_id: chip_id,
  device_type: "pir",
  status: 1,
  is_payment: false,
  note: "PIR sensor phát hiện chuyển động",
  device_info: {
    device_type: "pir",
    device_id: chip_id,
    update_at: Time.current.to_i,
    local_ip: "",
    build_version: 0,
    app_version: "1.0.0"
  }.to_json,
  trigger: nil,
  meta_info: {}.to_json
)

puts "Đã tạo PIR device ID #{device.id}: #{device.chip_id}"
```

### Ý nghĩa cấu hình PIR

```json
{
  "device_type": "pir",
  "device_id": "esp32_PIR_001",
  "update_at": 1726124567,
  "local_ip": "",
  "build_version": 0,
  "app_version": "1.0.0"
}
```

| Trường | Ý nghĩa |
| --- | --- |
| `device_type` | Loại thiết bị: `pir` cho cảm biến chuyển động |
| `device_id` | Mã chip_id của thiết bị |
| `update_at` | Timestamp lần cập nhật cuối (Unix time) |
| `local_ip` | Địa chỉ IP local của thiết bị |
| `build_version` | Phiên bản build firmware |
| `app_version` | Phiên bản ứng dụng |

## 4. Liên kết Device với User

Để user có thể xem thông tin device và nhận thông báo:

```ruby
user = User.find_by(email: "your-email@example.com")
device = Device.find_by(chip_id: "esp32_PIR_001")

# Liên kết
device.users << user unless device.users.include?(user)

# Cấu hình Slack webhook cho user (nếu chưa có)
user.update(webhook_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL")
```

## 5. Cấu hình thiết bị ESP32 gửi motion event

### Code mẫu cho ESP32/ESP8266

```cpp
#include <WiFi.h>
#include <HTTPClient.h>

const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* serverUrl = "https://your-domain.com/api/devices/trigger";
const char* chipId = "esp32_PIR_001";

const int pirPin = 14; // GPIO pin cho PIR sensor

void setup() {
  Serial.begin(115200);
  pinMode(pirPin, INPUT);
  
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");
}

void loop() {
  int pirState = digitalRead(pirPin);
  
  if (pirState == HIGH) {
    Serial.println("Motion detected!");
    sendMotionEvent();
    delay(5000); // Đợi 5 giây trước khi phát hiện tiếp
  }
  
  delay(100);
}

void sendMotionEvent() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    
    http.begin(serverUrl);
    http.addHeader("Content-Type", "application/json");
    
    String payload = "{\"chip_id\":\"" + String(chipId) + "\"}";
    
    int httpCode = http.POST(payload);
    
    if (httpCode > 0) {
      String response = http.getString();
      Serial.printf("Server response: %d - %s\n", httpCode, response.c_str());
    } else {
      Serial.printf("Error: %s\n", http.errorToString(httpCode).c_str());
    }
    
    http.end();
  }
}
```

## 6. Kiểm tra Device hoạt động

### 6.1. Test gửi motion event bằng cURL

```bash
curl -X POST "https://your-domain.com/api/devices/trigger" \
  -H "Content-Type: application/json" \
  -d '{"chip_id":"esp32_PIR_001"}'
```

Kết quả mong đợi:

```json
{
  "status": "success",
  "message": "Motion event recorded"
}
```

### 6.2. Kiểm tra device events trong Rails console

```ruby
device = Device.find_by(chip_id: "esp32_PIR_001")

# Xem 10 sự kiện gần nhất
device.device_events.order(occurred_at: :desc).limit(10).each do |event|
  puts "#{event.occurred_at} - #{event.event_type}"
  puts "  Payload: #{event.payload}"
end
```

### 6.3. Xem giao diện web

Truy cập: `https://your-domain.com/devices/<device_id>`

Giao diện sẽ hiển thị:
- Trạng thái online/offline
- Thời gian phát hiện chuyển động cuối cùng
- Địa chỉ IP local
- Phiên bản firmware
- Bảng lịch sử 20 sự kiện gần nhất

## 7. Cấu trúc Database

### Bảng `devices`

| Trường | Kiểu | Bắt buộc | Mô tả |
|--------|------|----------|-------|
| `chip_id` | string | ✓ | ID duy nhất của thiết bị |
| `name` | string | | Tên hiển thị |
| `device_type` | string | | `"pir"` cho cảm biến chuyển động |
| `status` | integer | | Trạng thái device |
| `is_payment` | boolean | | Đã thanh toán hay chưa |
| `device_info` | text (JSON) | | Thông tin chi tiết về device |
| `trigger` | text (JSON) | | `null` cho PIR device |
| `note` | text | | Ghi chú |
| `meta_info` | text (JSON) | | Metadata bổ sung |

### Bảng `device_events`

| Trường | Kiểu | Bắt buộc | Mô tả |
|--------|------|----------|-------|
| `device_id` | integer | ✓ | Foreign key đến bảng devices |
| `event_type` | string | ✓ | Loại sự kiện: `"motion_detected"` |
| `occurred_at` | datetime | ✓ | Thời điểm xảy ra sự kiện |
| `payload` | text (JSON) | | Dữ liệu chi tiết (IP, user agent) |

## 8. API Endpoint

### POST `/api/devices/trigger`

**Request:**

```json
{
  "chip_id": "esp32_PIR_001"
}
```

**Response thành công (200):**

```json
{
  "status": "success",
  "message": "Motion event recorded"
}
```

**Response lỗi (404):**

```json
{
  "error": "Device not found"
}
```

**Xử lý:**

1. Tìm device theo `chip_id`
2. Tạo record `DeviceEvent` với:
   - `event_type: 'motion_detected'`
   - `occurred_at: Time.current`
   - `payload`: chứa IP và user agent
3. Nếu device có relay được cấu hình trong `trigger`, gửi MQTT message (tùy chọn)

## 9. Xóa Device PIR

Dùng rake task `device:delete`:

```bash
# Development
bundle exec rake device:delete

# Production
RAILS_ENV=production bundle exec rake device:delete
```

Task sẽ:
1. Liệt kê tất cả devices
2. Yêu cầu nhập chip_id
3. Hiển thị số lượng dữ liệu liên quan (device_events, relay_logs, reminders, user associations)
4. Yêu cầu xác nhận bằng cách nhập lại chip_id
5. Tạo file backup JSON
6. Xóa device và toàn bộ dữ liệu liên quan trong transaction

## 10. Lưu ý quan trọng

1. **chip_id phải unique**: Mỗi device cần một `chip_id` khác nhau
2. **PIR không có trigger config**: Trường `trigger` nên là `null` cho device PIR
3. **Device events được tự động ghi lại**: Mỗi lần gọi `/api/devices/trigger` tạo một `DeviceEvent`
4. **Liên kết với User**: Device cần được liên kết với user để hiển thị trong danh sách devices của user
5. **Slack notification**: Có thể cấu hình webhook để nhận thông báo khi có chuyển động

## 11. Ví dụ use case

### Use case 1: Cảm biến an ninh

Device PIR đặt tại cửa chính, mỗi khi phát hiện chuyển động:
- Gửi event lên server
- Server ghi lại thời gian và IP nguồn
- (Tùy chọn) Gửi thông báo Slack cho chủ nhà
- (Tùy chọn) Bật đèn qua relay device liên kết

### Use case 2: Thống kê lưu lượng người

Device PIR đặt tại lối vào cửa hàng:
- Đếm số lần có người đi qua
- Phân tích giờ cao điểm
- Tạo báo cáo theo ngày/tuần/tháng

### Use case 3: Tự động hóa nhà thông minh

Kết hợp PIR với relay devices:
- Phát hiện chuyển động → bật đèn
- Không có chuyển động sau 5 phút → tắt đèn
- Điều chỉnh nhiệt độ dựa trên sự hiện diện
