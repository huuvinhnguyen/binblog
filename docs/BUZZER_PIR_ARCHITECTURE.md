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

Response này được trả sau khi Rails đã lưu event, execution snapshots và đã thử
publish tuần tự từng action. Nó không xác nhận thiết bị đã nhận hoặc thực thi
command.

## Mô hình cấu hình

`DeviceTriggerAction` biểu diễn một action từ một PIR nguồn đến một Switch hoặc
Buzzer đích. Phiên bản hiện tại chỉ hỗ trợ `relay_pulse`:

- `relay_index` phải tồn tại trong cấu hình target.
- Buzzer duration: 100–10000 ms.
- Switch duration: 100–86400000 ms.
- Delay mới chỉ hỗ trợ `0`. Row cũ có delay khác 0 vẫn được hiển thị và quản lý,
  nhưng runtime ghi `skipped/delay_not_supported` thay vì chờ hoặc publish.
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
  -> execute each pending_publish snapshot sequentially in request process
     -> atomically claim publish_attempted before MQTT network work
     -> connect + publish with a hard 5-second bound per action
  -> return existing HTTP success response

DeviceTriggerActionExecutor(execution_id)
  -> reject terminal/duplicate execution
  -> recheck action, target, ownership, target type, relay and zero delay
  -> atomically mark publish_attempted before any MQTT network side effect
  -> connect with config/mqtt.yml and publish
  -> mark publish_returned, or failed with a machine-readable error_code
```

Một execution hỏng không chặn execution sau. Nếu event hoặc snapshot không lưu
được, transaction rollback và không publish action nào. `DeviceTriggerActionJob`
chỉ còn là compatibility wrapper gọi cùng executor, `retry: false`; request mới
không enqueue Sidekiq và không phụ thuộc Redis.

MQTT connect failure đã biết dùng `mqtt_connect_failed`. Lỗi hoặc timeout sau
khi connect dùng `publish_outcome_unknown`, vì delivery có thể đã xảy ra. Trạng
thái `publish_attempted` cho phép vận hành điều tra mà không tự phát lại command
vật lý.

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
  "longlast": 1000,
  "sent_time": "2026-10-06 09:50:01"
}
```

Payload `relay_pulse` dùng cùng contract duration hiện hữu cho Buzzer và Switch:
`longlast` điều khiển thời lượng pulse và không gửi `switch_value`, vì firmware
hiểu `switch_value: 1` là bật liên tục. `sent_time` được tạo ngay trước publish
theo format firmware hiện hữu `YYYY-MM-DD HH:MM:SS`. Publish giữ
`retain: false`. Hệ thống không tuyên bố QoS/PUBACK hoặc device ACK. Legacy
execution giữ nguyên payload JSON cũ và chỉ thay `sent_time` mới.

## Event và execution audit

Mỗi request ghi đúng một `DeviceEvent(event_type: "motion_detected")` trên
source. Payload event chứa request metadata, configuration mode và số action đã
chọn. Mỗi target có `DeviceTriggerActionExecution` riêng với snapshot target,
relay, duration, delay, order và command.

Execution đi theo chiều:

```text
pending_publish -> publish_attempted -> publish_returned
                         \-> failed
pending_publish -> failed | skipped
```

`pending_enqueue` và `queued` vẫn được đọc bởi executor để xử lý dữ liệu lịch sử;
request mới không tạo hai trạng thái này. Snapshot bất biến sau khi tạo. Các
timestamp phân biệt publish bắt đầu, publish return và failure. Xóa action hoặc
target không xóa audit snapshot;
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

Feature flag `DEVICE_TRIGGER_ACTIONS_ENABLED` mặc định bật ở development, test
và production; production không có default-off riêng. Có thể đặt explicit thành
`false` như một override vận hành tạm thời hoặc emergency kill switch; khi đó
management trả `503 feature_disabled`. Action mode không fallback về JSON legacy
dù flag tắt.

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

1. Deploy schema và code với default-on giữ nguyên ở mọi môi trường. Nếu cần
   kiểm soát rollout tạm thời, operator có thể đặt explicit
   `DEVICE_TRIGGER_ACTIONS_ENABLED=false`; đây không phải production default.
2. Xác nhận MQTT config, giới hạn thời gian request và quan sát execution status.
3. Cho nhóm vận hành phù hợp migrate từng PIR explicit.
4. Gỡ override explicit `false` nếu đã dùng, rồi kiểm tra
   event/execution/target thực tế.
5. Mở rộng Web/Mobile dựa trên OpenAPI sau khi backend ổn định.

Rollback runtime bằng cách tắt flag. Không xóa execution audit. Chỉ xóa action
rows khi đã xác nhận JSON legacy của từng PIR vẫn hợp lệ; vì sự tồn tại của row
luôn chặn fallback, row disabled không phải cơ chế rollback.

## Giới hạn hiện tại

- Firmware trigger endpoint vẫn không xác thực thiết bị; security hardening cho
  `POST /api/devices/trigger` được hoãn sang phase tương lai theo quyết định sản
  phẩm hiện tại.
- Không có device ACK nên `publish_returned` chỉ có nghĩa lệnh publish đã return.
- Request PIR retry có thể tạo event/execution mới và phát lại command.
- Không lưu MQTT/provider credential trong action hoặc execution.
