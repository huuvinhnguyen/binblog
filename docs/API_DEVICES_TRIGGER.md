# API `/api/devices/trigger` - Tài liệu chi tiết

## Tổng quan

API endpoint này cho phép kích hoạt (trigger) một thiết bị IoT bằng cách publish một message MQTT đã được cấu hình trước trong database. Thay vì gửi toàn bộ payload mỗi lần, API chỉ cần `chip_id` và sẽ tự động lấy cấu hình trigger từ database để gửi qua MQTT broker.

---

## Thông tin cơ bản

- **URL**: `POST /api/devices/trigger`
- **Authentication**: Không yêu cầu (public endpoint)
- **Content-Type**: `application/json`

---

## Request Parameters

### Body Parameters

| Tham số | Kiểu | Bắt buộc | Mô tả |
|---------|------|----------|-------|
| `chip_id` | string | Có | Chip ID của thiết bị cần trigger (ví dụ: `ESP32_ABC123`) |

### Ví dụ Request

```json
POST /api/devices/trigger
Content-Type: application/json

{
  "chip_id": "ESP32_ABC123"
}
```

---

## Chi tiết luồng xử lý

### Bước 1: Nhận request và tìm thiết bị

```ruby
device = Device.find_by(chip_id: params[:chip_id])
```

- Controller nhận `chip_id` từ request body
- Tìm kiếm thiết bị trong database theo `chip_id`
- Nếu không tìm thấy → thiết bị không tồn tại → sẽ raise exception ở bước sau

### Bước 2: Gọi method `trigger_device`

```ruby
trigger_device device
```

Controller gọi private method `trigger_device(device)` để xử lý logic publish MQTT.

---

## Logic của method `trigger_device`

### Bước 2.1: Lấy cấu hình trigger từ database

```ruby
raw_message_trigger = device.trigger
```

- Lấy giá trị từ cột `trigger` trong bảng `devices`
- Cột này chứa một JSON string đã được cấu hình trước
- **Quan trọng**: Cột `trigger` phải chứa JSON hợp lệ

### Bước 2.2: Parse JSON

```ruby
json_params = JSON.parse(raw_message_trigger)
```

- Parse string JSON thành Ruby hash
- Nếu JSON không hợp lệ → raise `JSON::ParserError` → trả về lỗi 422

### Bước 2.3: Tạo MQTT topic

```ruby
topic = "#{json_params['chip_id']}/switchon"
raise "chip_id is missing" unless json_params['chip_id'].present?
```

- Tạo topic theo format: `<chip_id>/switchon`
- Ví dụ: `ESP32_ABC123/switchon`
- **Validate**: `chip_id` phải tồn tại trong JSON trigger
- Nếu thiếu `chip_id` → raise exception → trả về lỗi 500

### Bước 2.4: Thêm timestamp

```ruby
json_params["sent_time"] = Time.current.strftime('%Y-%m-%d %H:%M:%S')
message_with_timestamp = json_params.to_json
```

- Thêm field `sent_time` vào JSON params
- Format timestamp: `YYYY-MM-DD HH:MM:SS`
- Ví dụ: `"2026-09-04 15:30:45"`
- Convert lại thành JSON string để gửi qua MQTT

### Bước 2.5: Kết nối MQTT broker

```ruby
client = mqtt_client
```

Method `mqtt_client` tạo kết nối đến MQTT broker:

```ruby
MQTT::Client.connect(
  host: '103.9.77.155',
  port: 1883
)
```

- **Host**: `103.9.77.155`
- **Port**: `1883` (MQTT standard port, no TLS)
- Không có authentication (username/password)

### Bước 2.6: Publish message

```ruby
client.publish(topic, message_with_timestamp, retain: false) if topic.present?
```

- Publish message đến topic đã tạo
- **retain**: `false` → broker không giữ message cho subscribers mới
- Chỉ publish nếu `topic` có giá trị

### Bước 2.7: Đóng kết nối

```ruby
client.disconnect
```

- Ngắt kết nối với MQTT broker
- Giải phóng tài nguyên

---

## Response Format

### Success Response (200 OK)

```json
{
  "status": "success",
  "message": "Message sent successfully"
}
```

### Error Responses

#### 422 Unprocessable Entity - JSON không hợp lệ

```json
{
  "status": "error",
  "message": "Invalid JSON format"
}
```

**Nguyên nhân**:
- Cột `trigger` trong database chứa string không phải JSON hợp lệ
- JSON bị lỗi cú pháp

#### 500 Internal Server Error

```json
{
  "status": "error",
  "message": "chip_id is missing"
}
```

**Nguyên nhân**:
- JSON trong cột `trigger` không có field `chip_id`

```json
{
  "status": "error",
  "message": "undefined method `trigger' for nil"
}
```

**Nguyên nhân**:
- Không tìm thấy device với `chip_id` đã cung cấp
- Device là `nil` → không thể gọi method `.trigger`

---

## Ví dụ đầy đủ

### 1. Dữ liệu trong database

```sql
-- Bảng devices
id  | chip_id        | trigger
----|----------------|--------------------------------------------------
1   | ESP32_ABC123   | {"chip_id":"ESP32_ABC123","relay_index":0,"switch_value":1}
```

### 2. Gửi request

```bash
curl -X POST https://example.com/api/devices/trigger \
  -H "Content-Type: application/json" \
  -d '{"chip_id":"ESP32_ABC123"}'
```

### 3. Quá trình xử lý

1. Tìm device có `chip_id = "ESP32_ABC123"`
2. Lấy `trigger = '{"chip_id":"ESP32_ABC123","relay_index":0,"switch_value":1}'`
3. Parse thành hash: `{ "chip_id" => "ESP32_ABC123", "relay_index" => 0, "switch_value" => 1 }`
4. Tạo topic: `ESP32_ABC123/switchon`
5. Thêm timestamp: `{ ..., "sent_time" => "2026-09-04 15:30:45" }`
6. Kết nối MQTT broker `103.9.77.155:1883`
7. Publish message:
   ```json
   {
     "chip_id": "ESP32_ABC123",
     "relay_index": 0,
     "switch_value": 1,
     "sent_time": "2026-09-04 15:30:45"
   }
   ```
8. Đóng kết nối MQTT
9. Trả về response: `{"status":"success","message":"Message sent successfully"}`

### 4. Thiết bị IoT nhận message

- Thiết bị ESP32 subscribe topic `ESP32_ABC123/switchon`
- Nhận message JSON
- Xử lý theo `relay_index` và `switch_value`
- Ví dụ: Bật relay số 0

---

## Lưu ý quan trọng

### 1. Cấu hình trigger trong database

Cột `trigger` phải chứa JSON hợp lệ với ít nhất field `chip_id`:

```json
{
  "chip_id": "ESP32_ABC123",
  "relay_index": 0,
  "switch_value": 1
}
```

### 2. Topic MQTT cố định

Topic luôn theo format: `<chip_id>/switchon`. Không thể thay đổi suffix `/switchon` qua API.

### 3. MQTT Connection

- Mỗi request tạo connection mới
- Connection được đóng ngay sau khi publish
- Không sử dụng connection pooling
- Không có retry mechanism nếu publish thất bại

### 4. Không có authentication

API này là public endpoint, không yêu cầu JWT token hay session authentication.

### 5. Timestamp format

`sent_time` luôn theo format `YYYY-MM-DD HH:MM:SS` theo timezone của server.

---

## Use Cases

### Use Case 1: Kích hoạt relay từ ứng dụng di động

1. App mobile gửi request với `chip_id`
2. Server lấy cấu hình trigger đã lưu
3. Publish MQTT message
4. Thiết bị IoT nhận và thực thi

### Use Case 2: Webhook integration

1. Dịch vụ bên thứ 3 (IFTTT, Zapier) gọi API
2. Trigger thiết bị dựa trên sự kiện (thời tiết, lịch, etc.)

### Use Case 3: Scheduled tasks

1. Background job (Sidekiq) gọi API định kỳ
2. Tự động trigger thiết bị theo lịch

### Use Case 4: PIR Sensor kích hoạt Buzzer (Cross-device trigger)

**Kịch bản**: Khi cảm biến chuyển động (PIR) phát hiện có người, bật buzzer cảnh báo trong 1 giây.

**Kiến trúc hệ thống**:
- **Device A** (ESP32_SENSOR_01): Thiết bị có cảm biến PIR
- **Device B** (ESP32_BUZZER_02): Thiết bị có buzzer kết nối với relay

**Các bước thực hiện**:

#### 1. Cấu hình trigger trong database

Device B (buzzer) phải có cấu hình trigger sẵn:

```sql
-- Bảng devices
id  | chip_id           | trigger
----|-------------------|--------------------------------------------------------
2   | ESP32_BUZZER_02   | {"chip_id":"ESP32_BUZZER_02","relay_index":0,"switch_value":1,"longlast":1000}
```

**Giải thích cấu hình**:
- `chip_id`: ID của thiết bị buzzer
- `relay_index`: 0 (relay đầu tiên)
- `switch_value`: 1 (bật relay)
- `longlast`: 1000 (milliseconds = 1 giây, buzzer sẽ tự tắt sau 1 giây)

#### 2. Device A (PIR sensor) phát hiện chuyển động

Firmware trên ESP32_SENSOR_01 xử lý sự kiện PIR:

```cpp
// Trên ESP32_SENSOR_01 (PIR sensor device)
void onPIRDetected() {
  Serial.println("Motion detected!");
  
  // Gọi API trigger để bật buzzer
  HTTPClient http;
  http.begin("https://example.com/api/devices/trigger");
  http.addHeader("Content-Type", "application/json");
  
  String payload = "{\"chip_id\":\"ESP32_BUZZER_02\"}";
  int httpCode = http.POST(payload);
  
  if (httpCode == 200) {
    Serial.println("Buzzer triggered successfully");
  }
  
  http.end();
}
```

#### 3. Server xử lý request

```ruby
# Controller nhận request từ Device A
params = { chip_id: "ESP32_BUZZER_02" }

# Tìm Device B (buzzer)
device = Device.find_by(chip_id: "ESP32_BUZZER_02")

# Lấy trigger config
trigger_json = device.trigger
# => '{"chip_id":"ESP32_BUZZER_02","relay_index":0,"switch_value":1,"longlast":1000}'

# Parse và thêm timestamp
json_params = JSON.parse(trigger_json)
json_params["sent_time"] = "2026-09-04 15:30:45"

# Tạo topic
topic = "ESP32_BUZZER_02/switchon"

# Publish qua MQTT
mqtt_client.publish(topic, json_params.to_json)
```

#### 4. Message MQTT được gửi

```json
{
  "chip_id": "ESP32_BUZZER_02",
  "relay_index": 0,
  "switch_value": 1,
  "longlast": 1000,
  "sent_time": "2026-09-04 15:30:45"
}
```

**Topic**: `ESP32_BUZZER_02/switchon`

#### 5. Device B (buzzer) nhận và xử lý

Firmware trên ESP32_BUZZER_02 subscribe topic và xử lý:

```cpp
// Trên ESP32_BUZZER_02 (Buzzer device)
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  if (strcmp(topic, "ESP32_BUZZER_02/switchon") == 0) {
    
    // Parse JSON
    DynamicJsonDocument doc(256);
    deserializeJson(doc, payload, length);
    
    int relay_index = doc["relay_index"];      // 0
    int switch_value = doc["switch_value"];    // 1
    int longlast = doc["longlast"];            // 1000
    
    // Bật relay (buzzer ON)
    digitalWrite(RELAY_PINS[relay_index], HIGH);
    Serial.println("Buzzer ON");
    
    // Tạo timer tắt sau 1 giây
    if (longlast > 0) {
      setTimeout([relay_index]() {
        digitalWrite(RELAY_PINS[relay_index], LOW);
        Serial.println("Buzzer OFF after 1 second");
      }, longlast);
    }
  }
}
```

#### 6. Timeline hoàn chỉnh

```
T=0ms:    PIR sensor phát hiện chuyển động
T=10ms:   Device A gửi HTTP POST /api/devices/trigger
T=50ms:   Server parse trigger config từ database
T=60ms:   Server publish MQTT message
T=80ms:   Device B nhận MQTT message
T=85ms:   Buzzer BẬT (relay ON)
T=1085ms: Buzzer TẮT (relay OFF) - sau đúng 1 giây
```

#### 7. Sơ đồ luồng

```
Device A (PIR Sensor)
ESP32_SENSOR_01
      ↓ [Phát hiện chuyển động]
      ↓
HTTP POST /api/devices/trigger
{"chip_id": "ESP32_BUZZER_02"}
      ↓
      ↓
Server (Rails App)
      ↓
Find Device B by chip_id
      ↓
Get trigger config from DB:
{"chip_id":"ESP32_BUZZER_02",
 "relay_index":0,
 "switch_value":1,
 "longlast":1000}
      ↓
Add timestamp
      ↓
MQTT Broker (103.9.77.155:1883)
Topic: ESP32_BUZZER_02/switchon
      ↓
      ↓
Device B (Buzzer)
ESP32_BUZZER_02
      ↓ [Subscribe & receive]
      ↓
Parse JSON & Execute
      ↓
Relay 0 = HIGH (Buzzer ON)
      ↓
[Wait 1000ms]
      ↓
Relay 0 = LOW (Buzzer OFF)
```

#### 8. Lợi ích của kiến trúc này

**Tách biệt logic**:
- Device A chỉ cần biết `chip_id` của Device B
- Không cần hard-code thông tin relay, duration trong firmware
- Dễ dàng thay đổi cấu hình từ database

**Tái sử dụng**:
- Một PIR sensor có thể trigger nhiều devices khác nhau
- Một buzzer có thể được trigger từ nhiều nguồn (PIR, door sensor, app mobile, etc.)

**Quản lý tập trung**:
- Tất cả cấu hình trigger được lưu trong database
- Có thể thay đổi `longlast`, `relay_index` mà không cần flash lại firmware
- Có thể thêm logic phức tạp (rate limiting, scheduling, permissions) ở server

**Scalability**:
- Thêm nhiều sensors và actuators mà không cần sửa code
- Server làm trung gian, giảm coupling giữa các devices

---

## Sơ đồ luồng

```
Client Request
      ↓
[POST /api/devices/trigger]
      ↓
Find Device by chip_id
      ↓
Get device.trigger (JSON string)
      ↓
Parse JSON → Ruby Hash
      ↓
Extract chip_id from Hash
      ↓
Create topic: "{chip_id}/switchon"
      ↓
Add sent_time timestamp
      ↓
Connect to MQTT Broker
(103.9.77.155:1883)
      ↓
Publish message to topic
      ↓
Disconnect from Broker
      ↓
Return success response
      ↓
      End
```

---

## Error Handling Summary

| Lỗi | HTTP Code | Nguyên nhân | Giải pháp |
|-----|-----------|-------------|-----------|
| Device not found | 500 | `chip_id` không tồn tại trong DB | Kiểm tra `chip_id` đã đúng chưa |
| Invalid JSON | 422 | Cột `trigger` không phải JSON hợp lệ | Sửa dữ liệu trong database |
| Missing chip_id | 500 | JSON trigger thiếu field `chip_id` | Thêm `chip_id` vào JSON trigger |
| MQTT connection failed | 500 | Không kết nối được broker | Kiểm tra network/firewall |

---

## Tài liệu liên quan

- [MQTT Protocol Documentation](https://mqtt.org/)
- [Ruby MQTT Gem](https://github.com/njh/ruby-mqtt)
- [API Swagger Documentation](../swagger/v1/swagger.yaml)

---

**Cập nhật lần cuối**: 2026-09-04  
**Tác giả**: Vinh Nguyen
