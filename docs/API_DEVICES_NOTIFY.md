# API `POST /devices/notify`

Webhook để thiết bị IoT gửi một sự kiện đến Binblog. Server ghi nhận thiết bị (nếu cần), sau đó gửi nội dung sự kiện đến Slack của những người dùng đang liên kết với thiết bị.

## Endpoint

```text
POST https://<your-domain>/devices/notify
```

Swagger UI: `https://<your-domain>/api-docs`

OpenAPI document: `https://<your-domain>/api-docs/v1/swagger.yaml`

## Authentication và headers

Endpoint này được thiết kế cho thiết bị IoT gọi trực tiếp:

- Không yêu cầu JWT hoặc `Authorization: Bearer ...`.
- Không yêu cầu CSRF token.
- Bắt buộc gửi header:

```http
Content-Type: application/json
Accept: application/json
```

> Vì endpoint không yêu cầu xác thực, nên production nên giới hạn truy cập bằng network/IP allowlist, API key hoặc cơ chế xác thực khác trước khi public endpoint ra Internet.

## Request body

| Trường | Kiểu | Bắt buộc | Mô tả |
| --- | --- | --- | --- |
| `id` | string | Có | Chip ID duy nhất của thiết bị. Giá trị này được đối chiếu với `devices.chip_id`. |
| `message` | string | Có | Nội dung thông báo gửi đến Slack. |
| `model` | string | Không | Model thiết bị, ví dụ `ESP32` hoặc `ESP8266`. |
| `relay_state` | integer | Không | Trạng thái relay: `0` = tắt, `1` = bật. |
| `relay_index` | integer | Không | Vị trí relay, bắt đầu từ `0`. |
| `name` | string | Không | Tên thiết bị. Được dùng khi server tạo device mới lần đầu. |

### Ví dụ payload

```json
{
  "id": "ESP32_ABC123",
  "message": "Relay 1 đã bật",
  "model": "ESP32",
  "relay_state": 1,
  "relay_index": 0,
  "name": "Thiết bị phòng khách"
}
```

## Response

### Gửi thành công

HTTP `200 OK` với `status: "success"` khi thiết bị có ít nhất một user liên kết và tất cả Slack notifications gửi thành công:

```json
{
  "message": "Notification sent to Slack",
  "status": "success"
}
```

### Không có user liên kết hoặc Slack gửi thất bại

HTTP vẫn là `200 OK`, nhưng `status` là `"failure"` nếu thiết bị chưa được liên kết với user nào hoặc có ít nhất một Slack notification thất bại:

```json
{
  "message": "Notification sent to Slack",
  "status": "failure"
}
```

Ứng dụng gửi Slack đến `webhook_url` được lưu trong từng user liên kết với device.

### Payload không hợp lệ

Endpoint hiện chưa validate đầy đủ request body. Thiếu `id` có thể vẫn trả HTTP `200` với `status: "failure"`, còn JSON sai cú pháp có thể khiến Rails trả HTTP `500 Internal Server Error`. Client phải luôn gửi JSON hợp lệ, có `id` và `message` không rỗng theo contract tài liệu.

## Ví dụ gọi API

### cURL

```bash
curl -X POST "https://<your-domain>/devices/notify" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --data-raw '{
    "id": "ESP32_ABC123",
    "message": "Relay 1 đã bật",
    "model": "ESP32",
    "relay_state": 1,
    "relay_index": 0,
    "name": "Thiết bị phòng khách"
  }'
```

### Arduino/ESP32

Ví dụ dưới đây dùng thư viện `HTTPClient` và `WiFiClient` có sẵn trong Arduino core của ESP32:

```cpp
#include <HTTPClient.h>
#include <WiFiClient.h>

void sendDeviceNotification() {
  WiFiClient client;
  HTTPClient http;

  http.begin(client, "https://<your-domain>/devices/notify");
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Accept", "application/json");

  const String body = R"json({
    "id": "ESP32_ABC123",
    "message": "Relay 1 đã bật",
    "model": "ESP32",
    "relay_state": 1,
    "relay_index": 0,
    "name": "Thiết bị phòng khách"
  })json";

  const int statusCode = http.POST(body);
  const String response = http.getString();

  Serial.printf("notify status: %d\n", statusCode);
  Serial.println(response);
  http.end();
}
```

Với ESP8266, flow tương tự; thay `WiFiClient` bằng thư viện client phù hợp với firmware đang sử dụng và giữ nguyên URL, headers và JSON body.

## Luồng xử lý

1. Server parse request body thành JSON.
2. Server tìm device theo `id` (`chip_id`). Nếu chưa có, server tự tạo device mới và dùng `name` làm tên ban đầu.
3. Server tạo nội dung Slack gồm `name`, `id`, `model`, `message`, thời gian server, `relay_index` và `relay_state`.
4. Server gửi thông báo đến Slack webhook của các user liên kết với device.
5. Server trả JSON gồm `message` và `status`.

Lưu ý: thời gian trong thông báo được lấy từ `Time.current` của server; trường `time` do client gửi không được sử dụng.

## Troubleshooting

### Nhận HTTP 500

- Kiểm tra body có phải JSON hợp lệ không.
- Kiểm tra trường `id` có tồn tại và không rỗng.
- Kiểm tra log Rails để xem lỗi chi tiết.

### Nhận `status: "failure"`

- Kiểm tra device đã được liên kết với user chưa.
- Kiểm tra `webhook_url` của user.
- Kiểm tra log ứng dụng và Slack webhook.

### Device được tạo nhưng tên không đúng

`name` chỉ được sử dụng khi tạo device lần đầu. Với device đã tồn tại, endpoint không cập nhật lại tên; hãy sửa tên trong trang quản trị ứng dụng.

## Bảo mật và vận hành

Endpoint hiện là public webhook để tương thích với firmware thiết bị. Không đưa Slack webhook URL vào payload. Nếu endpoint được expose trực tiếp trên Internet, nên bổ sung một trong các lớp bảo vệ sau:

- API key riêng cho từng device.
- Allowlist địa chỉ IP/network của thiết bị hoặc gateway.
- Rate limiting và logging theo `id`.
- HTTPS bắt buộc trong production.

Mở Swagger UI tại `/api-docs` trên cùng host với ứng dụng để xem schema hoặc dùng nút **Try it out**.
