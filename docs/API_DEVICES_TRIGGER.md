# API `POST /api/devices/trigger`

Endpoint kích hoạt command đã được cấu hình sẵn cho một device. Server tìm device theo `chip_id`, đọc JSON trong trường `devices.trigger`, thêm thời gian gửi và publish command qua MQTT.

## Endpoint

```text
POST https://<your-domain>/api/devices/trigger
```

Swagger UI: `https://<your-domain>/api-docs`

OpenAPI document: `https://<your-domain>/api-docs/v1/swagger.yaml`

## Authentication và headers

Theo implementation hiện tại, endpoint này không yêu cầu JWT hoặc phiên đăng nhập. Gửi các headers sau:

```http
Content-Type: application/json
Accept: application/json
```

> Endpoint có thể điều khiển relay qua MQTT nhưng hiện không yêu cầu authentication. Trước khi expose trên Internet, nên bổ sung API key/JWT, giới hạn quyền theo device và rate limiting.

## Điều kiện trước khi gọi API

Device phải tồn tại trong database và trường `trigger` phải chứa một JSON object hợp lệ. Ví dụ cấu hình được lưu trong `devices.trigger`:

```json
{
  "chip_id": "ESP32_ABC123",
  "relay_index": 0,
  "switch_value": 1
}
```

Có hai giá trị `chip_id` cần phân biệt:

1. `chip_id` trong HTTP request được dùng để tìm device trong database.
2. `chip_id` bên trong JSON `devices.trigger` được dùng để tạo MQTT topic `<chip_id>/switchon`.

Hai giá trị nên giống nhau. Endpoint hiện không kiểm tra chúng có khớp hay không.

## Request body

| Trường | Kiểu | Bắt buộc | Mô tả |
| --- | --- | --- | --- |
| `chip_id` | string | Có | Chip ID của device cần tìm trong database. |

```json
{
  "chip_id": "ESP32_ABC123"
}
```

Request chỉ chọn device. Command MQTT không được lấy từ request mà được đọc từ trường `trigger` đã lưu của device.

## Luồng xử lý

1. Server tìm device có `devices.chip_id` bằng `chip_id` trong request.
2. Server parse trường `devices.trigger` thành JSON.
3. Server lấy `chip_id` trong JSON này để tạo topic `<chip_id>/switchon`.
4. Server thêm `sent_time` theo giờ hiện tại của ứng dụng.
5. Server publish JSON qua MQTT với `retain: false`, rồi ngắt kết nối MQTT.
6. Server trả response JSON.

Ví dụ message thực tế được publish:

```text
Topic: ESP32_ABC123/switchon
```

```json
{
  "chip_id": "ESP32_ABC123",
  "relay_index": 0,
  "switch_value": 1,
  "sent_time": "2026-09-03 14:30:00"
}
```

## Response

### Thành công — HTTP 200

```json
{
  "status": "success",
  "message": "Message sent successfully"
}
```

Response thành công cho biết server đã gọi publish đến MQTT broker, không xác nhận thiết bị đã nhận hoặc thực thi command.

### Trigger không phải JSON hợp lệ — HTTP 422

Nếu nội dung `devices.trigger` không parse được thành JSON:

```json
{
  "status": "error",
  "message": "Invalid JSON format"
}
```

### Cấu hình device/trigger hoặc MQTT không hợp lệ — HTTP 500

Server trả HTTP `500 Internal Server Error` khi:

- Không tìm thấy device theo `chip_id`.
- Trường `trigger` rỗng hoặc không phải kiểu dữ liệu có thể parse.
- JSON `trigger` không có `chip_id`.
- Không thể kết nối/publish đến MQTT broker.

Response có dạng:

```json
{
  "status": "error",
  "message": "<chi tiết lỗi>"
}
```

Không nên phụ thuộc vào nội dung chính xác của `message`, vì hiện tại đó có thể là exception nội bộ.

## Ví dụ cURL

```bash
curl -X POST "https://<your-domain>/api/devices/trigger" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-raw '{
    "chip_id": "ESP32_ABC123"
  }'
```

## Ví dụ JavaScript

```javascript
const response = await fetch("https://<your-domain>/api/devices/trigger", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Accept: "application/json"
  },
  body: JSON.stringify({ chip_id: "ESP32_ABC123" })
});

const result = await response.json();

if (!response.ok || result.status !== "success") {
  throw new Error(result.message || "Không thể kích hoạt device");
}
```

## Troubleshooting

### HTTP 422 với `Invalid JSON format`

- Mở device trong trang quản trị.
- Kiểm tra trường `trigger` là JSON hợp lệ.
- Bảo đảm key và chuỗi đều dùng dấu nháy kép.

### HTTP 500 khi gọi với chip ID hợp lệ

- Kiểm tra device tồn tại và trường `trigger` không rỗng.
- Kiểm tra JSON `trigger` có `chip_id` không rỗng.
- Kiểm tra kết nối đến MQTT broker và log Rails.

### API trả 200 nhưng device không hoạt động

- Kiểm tra device đang subscribe đúng topic `<chip_id>/switchon`.
- Kiểm tra `chip_id` trong `devices.trigger` có đúng với thiết bị thực tế.
- Kiểm tra cấu trúc command (`relay_index`, `switch_value`, v.v.) có tương thích firmware.
- Kiểm tra MQTT broker logs và trạng thái kết nối của device.

Mở Swagger UI tại `/api-docs` trên cùng host với ứng dụng để xem schema hoặc dùng nút **Try it out**.
