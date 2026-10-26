# Switch API — Backend Architect handoff

Task: [z8tvbhwpn1](https://app.clickup.com/t/z8tvbhwpn1)
Consumer: [Swift + Flutter parity](https://app.clickup.com/t/z8tvbhwpmy)
Baseline: `main@c10b0fac7730854fa9a63861384b83801b15c7d6`
Author role: `ai/agents/architect.md`. Date: 2026-10-26.

## 1. Decision and readiness

**CONTRACT CHỐT — READY FOR DEVELOPER, theo các phase bên dưới.**
Đây là thiết kế để triển khai, không phải chứng nhận backend đã hoạt động.
**Reminders execution release gate còn BLOCKED; mobile integration vẫn BLOCKED.**
Developer có thể bắt đầu facade, authorization, query, validation, command và
contract tests. Không bật reminder writes cho người dùng cho đến khi gate §8
được giải quyết bằng evidence; không bỏ qua gate để báo full parity.

Chọn facade `/api/switches` riêng, Bearer-only, JSON-only. Giữ legacy routes
web/ESP; không blanket-auth `device_info`, không đổi firmware payload ngầm định.
App không gọi MQTT trực tiếp, không fallback sang legacy API thiếu quyền.
Không mở rộng sang pairing, social auth, PIR/Buzzer hay refactor toàn bộ scheduler.

## 2. Current architecture and confirmed source findings

- `Api::DevicesController`: relay actions chưa dùng auth/ownership guard;
  add/remove reminder trả redirect HTML, remove dùng timestamp, list thiếu ID.
- `SwitchOnService` chỉ sửa JSON; controller gửi refresh sau đó. Index sai có thể
  rơi vào nhánh sửa toàn bộ relay. Không gọi nguyên trạng từ facade mới.
- `SwitchOnDurationService` sửa `switch_value` và `update_at` trước MQTT, mở
  listener threads và enqueue OFF job. Không tái sử dụng toàn bộ service này
  như một command có ACK hoặc để đo online.
- `Reminder::REPEAT_TYPES` dùng `once`; web và mobile enum cũ dùng `none`.
- `ReminderCronWorker` có thể publish duration trong cửa sổ ±5 phút trước khi
  enqueue `ActivateRelayJob`; job activate/off có `refresh` đã comment.
  Existing tests phần lớn kiểm tra DB/job calls, không chứng minh hardware chạy.
- `device_info` trả reminders cho firmware; chưa chứng minh firmware có tự chạy
  lịch hay không. Không thêm một publisher/scheduler thứ hai khi chưa rõ owner.
- `relay_statistics` action trống. `app/javascript/controllers/application.js`
  dựng `myChart` bằng `[12,19,3,5]`: đây là **sample data**, không phải thống kê thật.
- `confirmed_turn_*` tồn tại trong schema nhưng tìm trong app/lib không thấy
  writer. Không dùng chúng để tuyên bố thời gian chạy vật lý đã được xác thực.
- Có `Api::BearerAuthentication`, MQTT config, request/service specs và
  `DeviceTriggerAction::DURATION_RANGES['switch'] = 100..86_400_000` để tham khảo.

## 3. Trust boundary and common contract

Flow: mobile -> authenticated facade -> scoped query/service -> MySQL/MQTT.

- Dùng `Api::BearerAuthentication`, principal `@authenticated_user`; không session
  fallback. Chỉ skip CSRF trên controller Bearer-only mới, không đổi global policy.
- Resolve `@authenticated_user.devices_for_current_user.find_by(id: params[:id],
  device_type: 'switch')`; admin theo cơ chế hiện hữu. Không resolve global rồi
  kiểm tra quyền sau. Request không được cung cấp target chip_id/user_id/topic.
- Path `:id` là database Device ID, `:reminder_id` là database Reminder ID.
  ID serialize thành string, relay index là JSON integer 0-based.
- JSON request: `Accept: application/json`; mutation có body dùng
  `Content-Type: application/json`. Malformed JSON -> 400; media type sai -> 415.
  Bodyless chỉ hợp lệ cho DELETE và refresh POST; body không rỗng ở hai route đó
  phải là `{}`. Reject unknown input keys -> 422, không silent coercion.
- Auth trước lookup và side effect. 401 `authentication_required`; 404
  `switch_not_found` cho unknown/inaccessible/wrong type; reminder không thuộc
  device/relay -> 404 `reminder_not_found`; denied capability -> 403.
- Valid syntactic integer path index nhưng không tồn tại -> 422
  `invalid_relay_index`; âm/decimal/non-numeric cũng 422. JSON integer không
  nhận boolean/string/float/null. Không `.to_i` để validate input.
- Malformed stored JSON/non-array relays/non-object relay -> 422
  `invalid_configuration`, không biến thành empty success. Array rỗng hợp lệ
  -> relays `[]`; mọi relay mutation bị từ chối. Giới hạn 32 relay trong facade;
  cấu hình vượt giới hạn trả invalid_configuration, không silently truncate.
- Feature flag `SWITCH_MOBILE_API_ENABLED`: default false, true/1 bật; false/0
  tắt; malformed fail closed. Authenticated request khi tắt -> 503
  `feature_unavailable`. Không fallback client sang legacy.
- GET không DB write/job/MQTT, `Cache-Control: no-store` trên mọi response.
- Errors: `{"status":"error","code":"...","request_id":"..."}`;
  422 thêm `fields` map string -> array error codes khi hữu ích. Không secrets,
  broker address/topic, exception message/stack trace trong response.
- 503 dependency unavailable **trước side effect**: `outcome: "not_attempted"`.
  MQTT write error/timeout/disconnect không chứng minh chưa gửi -> 502
  `command_outcome_unknown`, `outcome: "unknown"`. Không automatic replay.

## 4. Routes frozen for implementation

Base `S = /api/switches/:id`, `R = S/relays/:relay_index`.

| Method | Path | Body/query | Success |
| --- | --- | --- | --- |
| GET | S | none | 200 detail |
| POST | R/state | `{"switch_value":0 or 1}` | 200 command result |
| POST | R/pulse | `{"duration_ms":integer}` | 200 command result |
| GET | R/reminders | `after_id`, `limit` | 200 list |
| POST | R/reminders | `start_time,duration_ms,repeat_type` | 201 reminder |
| DELETE | R/reminders/:reminder_id | no body or `{}` | 200 deleted ID |
| PUT | R/reminders-active | `{"active":true or false}` | 200 group state |
| GET | R/statistics | `from,to` date strings | 200 log statistics |
| POST | S/refresh | no body or `{}` | 200 command result |

No edit reminder, individual reminder enable, restart/reset-WiFi/OTA in this task.
No HTTP redirects or HTML in facade. Missing required POST/PUT body -> 422.
GET invalid/missing path -> JSON 404 when it matches this namespace.

### Detail schema

`{"status":"success","switch":{...},"server_time":"ISO8601+07:00"}`.
Switch object required keys:

| Field | Type / semantics |
| --- | --- |
| id, chip_id, name | strings; name may be empty |
| device_type | literal `switch` |
| timezone | literal `Asia/Ho_Chi_Minh` |
| last_seen | ISO8601 with offset or null, parsed metadata only |
| online | null for v1: no verified online contract from command-mutated update_at |
| state_source | literal `server_snapshot` |
| physical_state_verified | false |
| capabilities | object: manual_switch, pulse, reminders, statistics, refresh booleans |
| limits | duration_min_ms=1000, duration_max_ms=86400000, reminder_limit_per_relay=100 |
| relays | array in index order; each item below |

Relay: `index` integer, `switch_value` 0/1/null, `duration_ms` integer/null,
`reminders_active` boolean/null. Unknown/missing state stays null (not OFF).
Do not embed an unbounded reminder collection in detail.
Capabilities manual_switch/pulse/refresh/statistics true when valid config and
feature enabled. `reminders` additionally requires UserRelayFeature reminder
permission AND execution readiness flag in §8. Missing permission record keeps
existing default enabled (`!= false`); explicit false wins even for admin.
Only existing web reminder capability is enforced here; do not invent three new
UserRelayFeature gates from the comment-polluted FEATURES constant.

### Commands and firmware shape

Positive whole-second UI values map to 1000..86_400_000 ms, multiple of 1000.
This is a deliberate v1 switch UI bound, narrower than existing PIR switch pulse
range and within signed MySQL integer; does not restrict legacy stored values.
Existing out-of-bound duration is readable; don't silently normalize it.

- State: MQTT `<stored_chip_id>/switchon`, payload `relay_index`, `switch_value`,
  `sent_time` only; no extra duration to alter ON/OFF semantics.
- Pulse: same topic, payload `relay_index`, `longlast: duration_ms`, `sent_time`;
  no switch_value. Reuse compatible pulse payload convention from PIR publisher.
- Refresh: `<stored_chip_id>/refresh`, payload `action:refresh`, `sent_time`.
- No retain; preserve current publisher QoS 0 for this facade unless separately
  reviewed. Result says `acknowledgement:"none"`, **not broker ACK** or physical ACK.
  `publish_returned` only means the client publish call returned. Use config/mqtt.yml,
  bounded connect/write timeouts and ensure disconnect; never copy per-request
  subscribe threads. No delayed server OFF job for a pulse owned by firmware.
- New service takes already-authorized Device plus validated index/value. Recheck
  config under device lock before writes. No fallback to all relays. Keep network IO
  outside DB lock; do not hold a DB transaction through broker waits.
- Do not rewrite `device_info.switch_value`, `update_at`, metadata last_seen or
  online on command submission. GET may legitimately keep old snapshot.
- Before publish append `switch_command_requested` DeviceEvent on target device,
  with occurred_at and non-secret operation/index/value/duration/request ID.
  Append outcome event `switch_command_result` after publish; no telemetry fiction.
  Add both EVENT_TYPES deliberately. On missing audit persistence before publish,
  fail closed. Audit failure after publish is unknown; never resend automatically.
  Do not place unbounded request bodies in event payloads.
- Response: `{"status":"accepted","outcome":"publish_returned",
  "acknowledgement":"none","request_id":"...","event_id":"string"}`.
  `accepted` does not imply physical activation. No fake countdown/physical success.

Idempotency v1: no dedup key, no exactly-once promise. Each manual POST is a new
intent. Client must not retry a timed-out POST automatically. GET after timeout
can reconcile stored schedules but cannot prove physical relay state. UI stays
unknown/stale; a later explicit command must be a deliberate new user intent.

## 5. Reminder persistence contract

List returns `status`, `reminders`, `next_after_id` string/null. Default limit 50,
1..100, `after_id` non-negative integer decimal string; order ID ascending.
UI sorts the loaded collection by start_time then ID for display. Max 100 records
per relay, enforced under Device lock for every new creation. Existing >100 rows
remain paginated/readable, no truncation or deletion.

Reminder object: id/device_id strings, relay_index integer, start_time ISO8601
offset, duration_ms integer/null, repeat_type string, enabled boolean,
configuration_valid boolean. Unsupported old repeat/null duration remains visible
as invalid config; do not fabricate a valid schedule or silently delete it.
Delete reply `{"status":"success","deleted_reminder_id":"..."}`;
repeat DELETE of missing ID -> 404, no other row affected. Scope device+relay+ID,
not timestamp. Two schedules may share start_time and still have different IDs.

Create wire values: once/daily/weekly/monthly, no `none` in JSON. ISO8601 start_time
must include Z or numeric offset; normalize to Asia/Ho_Chi_Minh. Precision whole
minutes, seconds=0. Require start >= next whole minute after server now, <= now+366
days, for all repeats. This establishes a future first occurrence, not just a
time-of-day template. Reject timezone-free/invalid dates; do not parse guessed
local time. Duration uses §4 bound. New enabled mirrors relay group boolean;
missing/invalid group boolean -> invalid_configuration, not invented true.

Recurrence intended contract: first at start_time; daily then same local clock,
weekly same weekday, monthly same day-of-month. Skip invalid short months, never
clamp to last day. once runs at most once. Never execute before start_time.
**Existing scheduler does not yet prove this contract; §8 is mandatory.**

Group PUT sets active and enabled consistently for all relay reminders in a DB
transaction; don't invoke a due-now publish as a side effect of enabling. Disabling
cancels future queued starts, not an already-running pulse. Delete likewise does
not assert that current hardware activity stops. Snapshot persisted+dispatch
failure must be reported as unknown/failed sync, not as a rolled-back DB write.

Capability denied: reads may return stored schedules to the authorized owner;
all reminder mutations 403 `reminder_not_allowed`. When execution readiness is
off, mutations 503 `reminder_execution_unavailable`; capability false does not
hide existing history or make deletion silently succeed.

Web compatibility: map form `none` to canonical once on write and render old
none/once as the same label. No bulk rewrite/backfill. Keep HTML redirects for
legacy web. No global validation change that makes unrelated old data unsavable.

## 6. Statistics: actual log activity, not fabricated runtime

GET `from=YYYY-MM-DD&to=YYYY-MM-DD`; both optional together. Default today through
today-6 days, inclusive local dates, maximum 31 days; no future dates or reversed
range. Convert to `[from.beginning_of_day,(to+1.day).beginning_of_day)` in +07.

Source RelayLog scoped device+relay and created_at. Response: `status`, `timezone`,
`from`, `to`, `metric:"log_records"`, `total_records`, `days:[{date,count}]`,
`physical_runtime_seconds:null`, `physical_runtime_verified:false`.
Return every date including zero. Count persisted log records, not unique commands
or ON transitions; label clearly in web/mobile. No pairing arbitrary ON/OFF rows.
No synthetic numbers, no use confirmed timestamps until trusted writer exists.
Bounded aggregate query; add index `(device_id,relay_index,created_at)` via safe
MySQL-compatible migration. Verify MySQL grouping/timezone behavior, not just SQLite.

This changes the product meaning of the old sample chart to honest log activity.
Developer updates web relay statistics to the same query and permissions; no
second data definition. Remove the `myChart` sample handler only for this chart;
preserve unrelated homepage chart handlers. Asset build/precompile gates apply.

## 7. File plan / delivery slices

1. `Api::SwitchesController` (detail/refresh), relay controller actions or one
   coherent nested facade; routes before generic resources. Bearer guard reuse.
2. `SwitchDetailQuery`, `SwitchCommandService`, `SwitchReminderService`,
   `SwitchRelayStatisticsQuery` (names may follow local conventions). Stateless
   input validation + scoped services; no parallel authentication infrastructure.
3. DeviceEvent allowed types; index migration above; OpenAPI and JSON fixtures.
   No new commands/reminders ledger table or firmware migration approved here.
4. Web none/once adapter and statistics view/query; don't copy unsafe legacy
   auth into new facade. Legacy API security debt stays separately tracked at
   https://app.clickup.com/t/z8tvbht9vj; new facade does not fix old exposure.
5. Finalize reminder dispatch as §8 before enabling its writes. Reuse verified
   shared primitives; do not instantiate legacy service with mocked success and
   call the pipeline done. Any required scheduler redesign returns to Architect.
6. Rswag request specs for all routes/errors; regenerate full swagger/v1/swagger.yaml.
   Shared fixtures under spec/fixtures/switch_api/; mobile copies after approval.

## 8. Reminder execution gate — unresolved dependency, exact exit evidence

Source establishes multiple potential execution paths; firmware source/runtime
is not in this checkout. **Architecture does not authorize selecting a second
scheduler or promising exactly-once hardware behavior without that evidence.**
Use `SWITCH_REMINDER_EXECUTION_READY`, default false, true/1 only when all below
pass. Feature enabled alone must not enable reminder writes.

Developer first traces actual ESP `device_info` reminder consumer, deployed
firmware version and web behavior with owner-provided/accessible firmware source.
Record whether firmware, cron or scheduled job is the execution owner; one owner
per occurrence, not server+firmware both emitting independent commands. No real
device request or publish is authorized by this documentation task.

Required evidence: create/load/delete/enable/disable, no publish before due,
once at most one dispatch attempt, repeat first date honored, month 31 skipping,
cron+scheduled-job overlap, concurrent workers, delayed job, stale OFF following
new command, cancellation after claim and restart recovery. DB+fake MQTT tests
must assert actual publish payload/count/order, not only state/job enqueue.

If single ownership and the specified recurrence cannot be implemented through
bounded repairs preserving firmware compatibility, **stop this slice and return
to Architect with a concrete execution-owner/migration proposal**. Keep read/query
and manual commands independently deliverable. No new owner column, command
ledger or wholesale scheduler replacement is silently approved. Until resolved,
backend task stays open and mobile reminder integration remains blocked.

## 9. Verification and rollout gates

- Request tests: missing/expired/bad JWT; session-only rejection; other owner,
  wrong type; malformed stored relays; all body/key/type/index/duration bounds;
  denied capability; JSON-only/no redirect; bodyless forms; GET no side effects.
- Service tests fake all MQTT/HTTP; no broker/production access. Assert state
  commands never affect sibling relays; no fabricated update_at/last_seen/ACK;
  publish return, pre-connect failure, partial publish, disconnect/audit failure.
- Reminder scope and duplicate timestamps, persisted sync failure, concurrent
  limit enforcement, timezone +07 and non-+07 input, old malformed records.
- Statistics empty/mixed rows/day boundaries/31-day bound, scoped aggregate;
  never infer physical runtime from requested timestamps.
- Run focused RSpec + full Rswag generation/check, routes, diff hygiene. Check
  migrations and locking/concurrency against MySQL (SQLite suite is insufficient).
- Independent Reviewer -> Developer fixes -> targeted re-review -> Final Verifier
  read-only evidence gate per ai/WORKFLOW.md. Account untracked file contents too.
- Commit/push/PR/merge only per authorization. No commit authority is implied by
  an architecture readiness label. This handoff is uncommitted at authoring.
- Deploy backend before mobile, flags initially off. Verify DB migration,
  environment flag values, exact deployed SHA, auth/owner GET smoke. Commands and
  real schedule smoke require owner-authorized safe test device. Label mocks and
  hardware evidence separately. Enable manual facade only after command gate;
  reminder flag remains off until §8 and authorized hardware smoke pass.
- Rollback: disable flags, roll back app code if required; leave additive index
  migration/data intact. Never replay commands or auto-delete reminders to undo
  deployment. Already scheduled legacy jobs do not disappear when a flag is off;
  inventory/cancellation needs explicit operational authorization and evidence.
- Mobile readiness requires implemented contract, passing review/CI, verified
  deployed routes and required device/schedule acceptance. To Do stays open until
  these gates pass; do not remove ClickUp dependency merely because PR merged.

## 10. Developer prompt

Act as ai/agents/developer.md for z8tvbhwpn1. Read this handoff and canonical
workflow/project/conventions/architecture. Reconcile previous branch/worktree;
start from updated clean main and create feature/z8tvbhwpn1-switch-mobile-api.
Implement §3–7 in slices with focused specs and fake MQTT. Preserve firmware/web
legacy contracts; new facade is Bearer-only. Keep reminder writes disabled until
§8 is resolved. Report gate evidence or concrete blocker; do not invent ACKs,
schedule execution or production readiness. Request review of the entire file
set, route confirmed defects back to Developer, then Final Verification.

## 11. Evidence for this architecture handoff

- EXECUTED / PASSED: cloned clean main, verified HEAD, read source/docs/specs,
  created dedicated docs branch; source findings above are static inspection.
- NOT RUN: Rails specs, migrations, Rswag generation, builds (no executable change).
- NOT TESTED: production API, MQTT broker, firmware, actual device/scheduling.
- No source/config/schema/test implementation changed; no deploy/data/MQTT write.
- No independent implementation review or Final Verification claimed.
