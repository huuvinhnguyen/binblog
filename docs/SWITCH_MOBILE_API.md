# Switch facade — phase 1

Implementation task: https://app.clickup.com/t/z8tvbhwpn1.
Contract: `ai/tasks/z8tvbhwpn1-switch-mobile-api-architecture.md`.

The new `/api/switches` facade is separate from the existing web/device routes.
It requires a Bearer JWT, scopes database device IDs to the current user/admin,
and accepts only switches with valid relay configuration. Relay indices are
zero-based. Clients must not fall back to anonymous legacy routes.

`SWITCH_MOBILE_API_ENABLED` defaults to disabled. Only literal `true` or `1`
enables it; malformed values fail closed. Every response uses `no-store`.
Requests use `Accept: application/json`; nonempty mutation bodies use JSON.
See generated `swagger/v1/swagger.yaml` for the phase-1 executable contract.

## Available operations

- GET detail: stored server snapshot, nullable state/last_seen, `online:null`.
- POST per-relay state: integer switch_value 0/1, one relay only.
- POST pulse: integer duration_ms 1000..86400000, multiple of 1000.
- POST device refresh: bodyless or empty JSON object.
- GET persisted reminders: stable string IDs, cursor pagination, legacy-invalid
  rows remain visible. Defaults to 50, maximum 100 rows per page.
- GET statistics: inclusive +07 dates, default last 7 days, maximum 31 days.
  Counts **RelayLog records**, not DeviceEvent audit entries or physical cycles.

Command success means the QoS-0 publish call returned, not a broker or hardware
acknowledgement. It never changes device_info/update_at/last_seen to invent a
successful relay transition. Requested/result DeviceEvents record the API intent
and outcome. No listener thread or delayed server OFF job is started by this API.
Firmware retains pulse timing ownership for the duration-only payload.

Do not automatically retry commands. After timeout or a 502 unknown outcome,
GET can refresh the stored snapshot but cannot prove physical state. A later
command is a separate deliberate user intent, not an automatic replay.

## Reminder writes remain unavailable

POST/DELETE reminders and PUT reminders-active return 503
`reminder_execution_unavailable` without DB mutation, queueing or publish.
An explicit UserRelayFeature reminder denial returns 403 instead. Read access
is retained for authorized owners even while writes are disabled.

`SwitchApi::Features.reminders_ready?` is intentionally hard-disabled. Setting
`SWITCH_REMINDER_EXECUTION_READY=true` alone does not unlock anything: the cron,
job and firmware execution-owner gate has not been resolved. The write routes
are reserved and documented with their **current error behavior**, not a false
201 success contract. No scheduler, ownership-column or ledger migration was
added. Full mobile reminder integration and task completion remain blocked.

Legacy HTML creation maps `none` to `once`; no stored data is rewritten. The
existing scheduler behavior and firmware-facing projections remain unchanged.

## Web statistics

The existing relay statistics page uses the same scoped query and shows a
date/count table with an explicit metric label. The unrelated homepage charts
are preserved; the obsolete myChart sample handler was removed. Invalid dates
or relay configuration show an error, and foreign device IDs return 404.

Counts use at most 31 indexed range queries, avoiding loading all log rows and
database-session DATE/timezone assumptions. Each local date is converted to an
exclusive-end interval by Rails. Production and test adapters still need their
own verification; passing SQLite tests is not production MySQL acceptance.

## Release and rollback

Run the additive migration that creates
`index_relay_logs_for_switch_statistics(device_id,relay_index,created_at)` only
with production authorization. Assess table size/DDL locking on the target
MySQL server before scheduling it. No data backfill or destructive migration.
Build JavaScript/CSS before precompile per `docs/RELEASE_PRODUCTION.md`.

Deploy with the facade flag off. Verify the exact deployed SHA, index, JSON
routes, authentication/ownership and read responses before enabling it. Commands
need an explicitly authorized safe-device smoke test. Reminder writes stay off.
Rollback disables the facade flag and reverts application code if necessary;
leave additive data/index intact unless separately authorized. A flag does not
cancel existing legacy scheduler jobs or undo a command already sent.

Fixtures for consumer tests are in `spec/fixtures/switch_api/`; these are
synthetic examples, not production captures or hardware verification.
