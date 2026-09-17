# Kiến trúc màn hình Buzzer được kích hoạt từ PIR

## Quyết định

Tái sử dụng nguyên `POST /api/devices/trigger`. Không đổi firmware PIR,
payload HTTP, topic MQTT hoặc firmware Buzzer trong luồng PIR → Buzzer.

Màn hình Buzzer có thêm chức năng **Test Buzzer** độc lập. Nó không dùng
`POST /api/devices/trigger`, mà dùng một web endpoint có Devise session, CSRF
và kiểm tra quyền sở hữu. Command test vẫn publish vào topic MQTT hiện có của
Buzzer và giữ nguyên các field firmware đang hỗ trợ.

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
5. Nút **Test Buzzer**, chỉ hiển thị với user có quyền trên Buzzer. Nút có xác
   nhận trước khi gửi lệnh và disabled/loading state để tránh bấm lặp.

Không gọi `POST /api/devices/trigger` với chip ID Buzzer: endpoint đó coi
`chip_id` là PIR nguồn nên sẽ ghi sai ngữ nghĩa event và đọc sai cấu hình
`trigger`.

## Test Buzzer thủ công

### Web endpoint

```http
POST /devices/:id/test_buzzer
```

Đây là web endpoint cho màn hình quản trị, dùng Devise session và CSRF, không
phải public firmware API. Vì vậy không thêm JWT, không thay đổi Swagger của
`POST /api/devices/trigger`, và không nhận `chip_id` từ browser.

Controller phải lấy device qua phạm vi thiết bị user được phép truy cập, ví dụ
`current_user.devices_for_current_user.find(params[:id])`, rồi xác minh
`device_type == "buzzer"`.

Response thành công có thể redirect lại Buzzer page với flash message. Các lỗi
config hoặc MQTT trả flash lỗi phù hợp; user không có quyền hoặc ID không tồn
tại nhận `404` để không lộ device khác.

### MQTT command

`BuzzerTestService` đọc relay mặc định từ `buzzer.device_info`, validate dữ
liệu và publish:

```text
{buzzer_chip_id}/switchon
```

```json
{
  "chip_id": "ESP32_BUZZER_02",
  "relay_index": 0,
  "switch_value": 1,
  "longlast": 1000,
  "sent_time": "2026-09-17 10:30:00"
}
```

- `relay_index`, `longlast` lấy từ cấu hình Buzzer, không nhận từ browser ở
  phiên bản đầu.
- Giới hạn duration an toàn cần được validate server-side.
- Dùng cooldown server-side ngắn (ví dụ 3 giây trên mỗi Buzzer) để giảm
  double-click/retry; browser không được là cơ chế chống trùng duy nhất.
- Service phải đóng MQTT client trong mọi trường hợp.
- Chưa có firmware ACK, nên publish không lỗi chỉ có nghĩa Rails đã gửi command
  tới broker; không khẳng định Buzzer đã phát âm.

### Audit

Sau khi MQTT publish không lỗi, có thể ghi một `DeviceEvent` mới trên Buzzer:

```text
event_type: "buzzer_test_requested"
payload: { relay_index, longlast, requested_by_user_id }
```

Event type này biểu thị yêu cầu test được gửi từ Rails, không được dùng các
event ACK như `buzzer_started` hoặc `buzzer_finished` khi firmware chưa xác
nhận. Nếu thêm event type, cần mở rộng validation của `DeviceEvent`; không cần
migration vì bảng event hiện có đã có payload linh hoạt.

## Giới hạn đã biết

- Event cũ chưa có `payload.target_chip_id` không thể gắn Buzzer đích chắc chắn.
- Một PIR retry request có thể làm Buzzer phát lại.
- Không có xác nhận Buzzer đã bật/tắt từ firmware.
- Endpoint hiện chưa xác thực firmware PIR; đây là rủi ro hiện hữu, ngoài phạm vi màn hình Buzzer.
- Test Buzzer thủ công chỉ chống request lặp ở Rails trong một khoảng ngắn;
  firmware hiện chưa có `command_id` để idempotent xuyên suốt MQTT.

## Kế hoạch triển khai

1. Thêm `buzzer` vào rake task tạo device; Buzzer không cần `trigger` riêng.
2. Cập nhật `Api::DevicesController#trigger`: parse `pir.trigger` trước, thêm `target_chip_id`, relay và duration vào event payload, rồi publish như cũ.
3. Trong `DevicesController#show`, tìm PIR có `trigger.chip_id` trỏ đến Buzzer hiện tại; tải tối đa 20 event của các PIR target Buzzer này.
4. Tạo `_buzzer_form.erb` và SCSS tương ứng.
5. Thêm request/UI specs cho source PIR, target Buzzer và event metadata.
6. Cập nhật tài liệu đăng ký Buzzer. Swagger không đổi vì request/response của `POST /api/devices/trigger` giữ nguyên.
7. Thêm route `POST /devices/:id/test_buzzer`, `BuzzerTestService`, kiểm tra
   ownership, validate cấu hình và cooldown server-side.
8. Thêm nút Test Buzzer cùng confirm/loading/empty/error states; thêm UI,
   request và service specs cho owner, non-owner, invalid config, MQTT failure
   và payload MQTT.
9. Cập nhật tài liệu đăng ký Buzzer; build asset, precompile và kiểm tra giao
   diện sau release.

## Rollback

Rollback Test Buzzer chỉ cần gỡ route/nút và ngừng gọi service; không cần flash
firmware hoặc đổi cấu hình PIR. Luồng PIR → `POST /api/devices/trigger` → MQTT
không đổi. Nếu đã ghi audit event, giữ lại lịch sử thay vì xóa.
