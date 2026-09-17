# Kiến trúc màn hình Buzzer được kích hoạt từ PIR

## Quyết định

Tái sử dụng nguyên `POST /api/devices/trigger`. Không đổi firmware PIR,
payload HTTP, topic MQTT hoặc firmware Buzzer trong phạm vi màn hình Buzzer.

`params[:chip_id]` là chip ID của **PIR nguồn**. Rails tìm PIR, lưu event
`motion_detected` cho PIR, đọc `trigger` của PIR và publish command tới Buzzer
đích được khai báo trong cấu hình đó.

```text
PIR ESP
  │ POST /api/devices/trigger
  │ { "chip_id": "ESP32_PIR_01" }
  ▼
Rails
  ├─ tìm PIR theo chip_id
  ├─ lưu DeviceEvent(motion_detected) cho PIR
  ├─ đọc devices.trigger của PIR
  ▼
MQTT Broker
  │ ESP32_BUZZER_02/switchon
  ▼
Buzzer ESP / relay
  ├─ switch_value: 1 → bật relay
  └─ longlast: 1000 → tự tắt sau 1 giây
```

## Logic hiện tại của `POST /api/devices/trigger`

Controller hiện thực hiện các bước sau:

1. Nhận `params[:chip_id]` từ PIR.
2. `Device.find_by(chip_id: params[:chip_id])` để tìm **PIR nguồn**.
3. Tạo `DeviceEvent(event_type: "motion_detected")` cho PIR.
4. Đọc JSON từ `pir.trigger`.
5. Thêm `sent_time`.
6. Publish JSON đó vào topic `#{trigger['chip_id']}/switchon`.

Vì topic được lấy từ `trigger['chip_id']`, Buzzer đích không nằm trong request
từ PIR; Buzzer đích nằm trong cấu hình `trigger` của PIR.

## Cấu hình device

### PIR nguồn

PIR giữ cấu hình `trigger` trỏ đến Buzzer:

```text
device_type: "pir"
chip_id: "ESP32_PIR_01"
```

```json
{
  "chip_id": "ESP32_BUZZER_02",
  "relay_index": 0,
  "switch_value": 1,
  "longlast": 1000
}
```

- `chip_id` trong JSON `trigger` là Buzzer đích.
- `relay_index` là relay nối với Buzzer.
- `switch_value: 1` bắt buộc giữ lại vì firmware Buzzer hiện parse field này để bật relay.
- `longlast` là thời gian Buzzer phát âm, tính bằng milliseconds.

### Buzzer đích

Buzzer là record riêng trong bảng `devices`:

```text
device_type: "buzzer"
chip_id: "ESP32_BUZZER_02"
```

Buzzer không cần `trigger` riêng cho luồng này. Nó nhận command MQTT từ cấu hình của một hoặc nhiều PIR.

## Payload từ firmware PIR

Firmware giữ nguyên request:

```http
POST /api/devices/trigger
Content-Type: application/json
```

```json
{
  "chip_id": "ESP32_PIR_01"
}
```

Trong `AppApi::sendTrigger(String deviceId)`, `chip_id` được gán trực tiếp từ đối số `deviceId`. Khi PIR gọi hàm với device ID của nó, `chip_id` chính là PIR nguồn.

## DeviceEvent và truy vết PIR nguồn

`motion_detected` thuộc về PIR. Vì vậy, Buzzer screen biết PIR nguồn trực tiếp từ `event.device`.

Để biết event nào đã target đúng Buzzer hiện tại, backend nên bổ sung metadata từ `pir.trigger` vào `DeviceEvent.payload` trước khi publish:

```json
{
  "target_chip_id": "ESP32_BUZZER_02",
  "relay_index": 0,
  "longlast": 1000,
  "triggered_from": "<remote_ip>",
  "user_agent": "<user_agent>"
}
```

Đây chỉ là thay đổi Rails, không đổi request PIR hay MQTT payload. Nó giữ đúng lịch sử nếu PIR sau này đổi target sang Buzzer khác.

Không có ACK từ firmware trong luồng hiện tại. `motion_detected` chỉ xác nhận Rails đã nhận request từ PIR; nó không chứng minh MQTT publish thành công hoặc Buzzer đã phát âm.

## UI Buzzer

Tạo `_buzzer_form.erb` và render khi:

```erb
<% if @device.device_type == "buzzer" %>
  <%= render "buzzer_form" %>
<% end %>
```

Màn hình gồm:

1. Tên Buzzer, `chip_id`, trạng thái online/offline và lần kết nối gần nhất.
2. Danh sách PIR có `trigger.chip_id` trỏ đến Buzzer này.
3. Lịch sử 20 event gần nhất với `payload.target_chip_id == @device.chip_id`; mỗi dòng hiển thị tên/chip ID PIR nguồn, thời điểm và duration.
4. Empty state khi chưa có PIR nào cấu hình trigger Buzzer.

Phiên bản đầu không thêm nút **Test Buzzer**. Gọi `POST /api/devices/trigger` với chip ID Buzzer là sai contract: controller sẽ coi Buzzer là PIR nguồn. Nếu cần test thủ công, thiết kế endpoint hoặc command riêng sau.

## Giới hạn đã biết

- Event cũ chưa có `payload.target_chip_id` không thể gắn Buzzer đích chắc chắn.
- Một PIR retry request có thể làm Buzzer phát lại.
- Không có xác nhận Buzzer đã bật/tắt từ firmware.
- Endpoint hiện chưa xác thực firmware PIR; đây là rủi ro hiện hữu, ngoài phạm vi màn hình Buzzer.

## Kế hoạch triển khai

1. Thêm `buzzer` vào rake task tạo device; Buzzer không cần `trigger` riêng.
2. Cập nhật `Api::DevicesController#trigger`: parse `pir.trigger` trước, thêm `target_chip_id`, relay và duration vào event payload, rồi publish như cũ.
3. Trong `DevicesController#show`, tìm PIR có `trigger.chip_id` trỏ đến Buzzer hiện tại; tải tối đa 20 event của các PIR target Buzzer này.
4. Tạo `_buzzer_form.erb` và SCSS tương ứng.
5. Thêm request/UI specs cho source PIR, target Buzzer và event metadata.
6. Cập nhật tài liệu đăng ký Buzzer. Swagger không đổi vì request/response của `POST /api/devices/trigger` giữ nguyên.
7. Build asset, precompile và kiểm tra giao diện sau release.

## Rollback

Rollback chỉ cần ngừng render Buzzer form và bỏ metadata event mới. Luồng PIR → `POST /api/devices/trigger` → MQTT không đổi, nên không cần flash lại firmware hoặc đổi cấu hình PIR.
