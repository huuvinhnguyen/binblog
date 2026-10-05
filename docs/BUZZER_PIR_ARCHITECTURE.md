# Kiến trúc PIR fan-out và Buzzer

## Contract firmware giữ nguyên

Firmware PIR tiếp tục gửi:

```http
POST /api/devices/trigger
Content-Type: application/json
```

```json
{ "chip_id": "ESP32_PIR_01" }
```

Response thành công giữ nguyên:

```json
{ "status": "success", "message": "Message sent successfully" }
```

Response này xác nhận Rails đã lưu event và enqueue các execution. Nó không xác
nhận broker hoặc thiết bị đã nhận command.

## Mô hình cấu hình

`DeviceTriggerAction` biểu diễn một action từ một PIR nguồn đến một Switch hoặc
Buzzer đích. Phiên bản hiện tại chỉ hỗ trợ `relay_pulse`:

- `relay_index` phải tồn tại trong cấu hình target.
- Buzzer duration: 100–10000 ms.
- Switch duration: 100–86400000 ms.
- Delay: 0–300000 ms.
- Tối đa 20 row cho một source, kể cả row disabled.
- Thứ tự chạy: `position`, rồi `id`; `position` không unique.
- Source và target phải khác nhau và còn dùng chung ownership.

`DeviceTriggerConfigurationResolver` là nơi duy nhất chọn mode:

- PIR có bất kỳ action row nào dùng mode `actions`; row disabled vẫn chặn
  fallback.
- PIR chưa có action row dùng `devices.trigger` hợp lệ ở mode `legacy`.
- PIR có JSON hỏng dùng mode `invalid_legacy`; PIR trống dùng `none`.
- Thiết bị không phải PIR tiếp tục dùng cấu hình legacy.

Không merge hai nguồn cấu hình trong cùng một request.

## Runtime

```text
PIR request
  -> DeviceTriggerDispatcher
     -> transaction: one DeviceEvent + N immutable execution snapshots
  -> commit
  -> enqueue one DeviceTriggerActionJob per pending_enqueue execution
  -> return existing HTTP success response

DeviceTriggerActionJob(execution_id)
  -> reject terminal/duplicate execution
  -> recheck action, target, ownership, target type and relay
  -> connect with config/mqtt.yml
  -> atomically mark publish_attempted immediately before publish
  -> publish
  -> mark publish_returned, or failed with a machine-readable error_code
```

Một execution hỏng hoặc enqueue thất bại không chặn execution khác. Nếu event
hoặc snapshot không lưu được, transaction rollback và không enqueue job nào.

Worker dùng `retry: false`: timeout sau khi publish bắt đầu có delivery outcome
không chắc chắn. Trạng thái `publish_attempted` cùng `publish_outcome_unknown` cho phép
vận hành điều tra mà không tự phát lại command vật lý.

## MQTT

Topic:

```text
<target_chip_id>/switchon
```

Payload action mới:

```json
{
  "chip_id": "ESP32_TARGET_01",
  "relay_index": 0,
  "switch_value": 1,
  "longlast": 1000,
  "sent_time": "unix-seconds"
}
```

`sent_time` được tạo ngay trước publish. Publish giữ `retain: false`. Hệ thống
không tuyên bố QoS/PUBACK hoặc device ACK. Legacy execution giữ nguyên payload
JSON cũ và chỉ thay `sent_time` mới.

## Event và execution audit

Mỗi request ghi đúng một `DeviceEvent(event_type: "motion_detected")` trên
source. Payload event chứa request metadata, configuration mode và số action đã
chọn. Mỗi target có `DeviceTriggerActionExecution` riêng với snapshot target,
relay, duration, delay, order và command.

Execution đi theo chiều:

```text
pending_enqueue -> queued -> publish_attempted -> publish_returned
                                  \-> failed
pending_enqueue/queued -> failed | skipped
```

Snapshot bất biến sau khi tạo. Các timestamp phân biệt enqueue, publish bắt đầu,
publish return và failure. Xóa action hoặc target không xóa audit snapshot;
foreign key tương ứng chuyển về NULL. Xóa request event sẽ cascade executions.
Relay không còn hợp lệ tại thời điểm chạy được ghi bằng error code chuẩn
`invalid_relay_index` và được trả nguyên trạng trong Buzzer history.

## API quản lý

Các endpoint dưới `/api/devices/:chip_id/trigger_actions` hỗ trợ:

- list mode và action
- list target hợp lệ
- create/update/delete
- thay toàn bộ order
- explicit legacy migration

List luôn trả một contract chung cho Web, Swift và Flutter:

```json
{
  "status": "success",
  "configuration_mode": "none|legacy|actions|invalid_legacy",
  "source_device": { "id": 1, "name": "Hall PIR", "chip_id": "PIR_01" },
  "actions": []
}
```

Action lưu trong database có `origin: "persisted"`; cấu hình JSON cũ hợp lệ
được chuẩn hóa thành một action chỉ đọc trong cùng mảng với `id: null` và
`origin: "legacy"`. Target list trả Rails ID, chip ID dùng để hiển thị, tên,
loại thiết bị, relay indexes và giới hạn duration theo loại. Client không được
chọn `position` khi create/update; server append khi create và chỉ endpoint
`order` được thay đổi thứ tự.

Các code ổn định để client xử lý là:

- `409 duplicate_action`, `action_limit_reached`,
  `configuration_mode_conflict`,
  `legacy_configuration_requires_reconciliation`,
  `trigger_actions_managed`.
- `422 invalid_action_type`, `invalid_relay_index`, `invalid_duration`,
  `invalid_delay`, `invalid_enabled`, `invalid_order`.
- `404 source_not_found`, `target_not_found`, `action_not_found`; target thiếu,
  không có quyền hoặc sai loại cùng dùng `target_not_found` để tránh tiết lộ.
- `503 feature_disabled`.

Authority giữ đúng code trên `main`: bearer JWT từ `POST /api/login`, hoặc
Devise session. Source và target đều được lấy qua
`User#devices_for_current_user`; inaccessible và missing dùng cùng contract
not-found. Endpoint quản lý chỉ sửa cấu hình, không publish MQTT.

Feature flag `DEVICE_TRIGGER_ACTIONS_ENABLED` mặc định bật ở non-production và
tắt ở production. Khi flag tắt, management trả `503 feature_disabled`. Action
mode không fallback về JSON legacy dù flag tắt.

## Legacy migration và Buzzer transition

Migration legacy là explicit và idempotent. Nó yêu cầu:

- source là PIR accessible
- chưa có action row, hoặc đúng một row đã migrate khớp hoàn toàn
- target accessible và thuộc loại hỗ trợ
- relay/duration trong JSON là integer hợp lệ

JSON cũ được giữ để rollback. Ngay khi action row đầu tiên tồn tại, action mode
thắng.

`BuzzerLinks` và `BuzzerDetails` dùng resolver chung. Link/Unlink cũ trả
`409 trigger_actions_managed` cho PIR đã vào action mode. Buzzer history kết hợp
execution snapshot mới với event payload legacy, tối đa 20 event mới nhất, và
trả execution status/error khi có.

Test Buzzer thủ công vẫn là luồng độc lập qua `BuzzerTestService`; nó không dùng
dispatcher fan-out.

## Rollout và rollback

1. Deploy schema, code và workers với production flag tắt.
2. Xác nhận worker, Redis, MQTT config và quan sát execution status.
3. Bật management cho nhóm vận hành phù hợp và migrate từng PIR explicit.
4. Bật runtime action mode, kiểm tra event/execution/target thực tế.
5. Mở rộng Web/Mobile dựa trên OpenAPI sau khi backend ổn định.

Rollback runtime bằng cách tắt flag. Không xóa execution audit. Chỉ xóa action
rows khi đã xác nhận JSON legacy của từng PIR vẫn hợp lệ; vì sự tồn tại của row
luôn chặn fallback, row disabled không phải cơ chế rollback.

## Giới hạn hiện tại

- Firmware trigger endpoint vẫn không xác thực thiết bị; đây là rủi ro legacy.
- Không có device ACK nên `publish_returned` chỉ có nghĩa lệnh publish đã return.
- Request PIR retry có thể tạo event/execution mới và phát lại command.
- Không lưu MQTT/provider credential trong action hoặc execution.
