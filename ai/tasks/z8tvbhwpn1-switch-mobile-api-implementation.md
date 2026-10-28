# Developer handoff — Switch API phase 1

Task: https://app.clickup.com/t/z8tvbhwpn1
Branch: `feature/z8tvbhwpn1-switch-mobile-api`
Integration base: `main@47b6ca0` (merged handoff PR #119 verified).
Date: 2026-10-27. No commit/push or deployment claimed by this report.

## Result

Implemented the approved phase-1 Bearer-only JSON facade, scoped device reads,
ON/OFF and firmware-timed pulse commands, refresh, bounded reminder reads and
log statistics. Commands record requested/result DeviceEvents, do not fake
hardware ACKs, and do not rewrite device snapshots/online metadata. MQTT uses
configuration with bounded operation/cleanup and no automatic replay.

All new reminder mutations remain **hard-disabled**. They enforce ownership,
relay configuration and capability denial before reporting execution unavailable.
Setting an environment readiness flag cannot enable an unimplemented scheduler.
No scheduler, firmware projection or existing reminder data was changed.

Web statistics now show real scoped log counts with the same query as the API.
The old sample chart handler was removed. Legacy web none/once compatibility
was repaired without rewriting stored data.

API/rollout details: `docs/SWITCH_MOBILE_API.md`; synthetic consumer examples:
`spec/fixtures/switch_api/`; generated contract: `swagger/v1/swagger.yaml`.

## Verification evidence

All Rails commands below used **RAILS_ENV=test** and a dedicated SQLite database
under `/tmp`, never the tracked development/production database configuration.
MQTT was faked in feature tests. The wider generation run additionally loaded
an external test-only guard that rejects every live MQTT client connect.

| Check | Result |
| --- | --- |
| Ruby syntax checks for new implementation/spec files | EXECUTED / PASSED |
| Additive statistics index migration on isolated SQLite | EXECUTED / PASSED |
| Focused request, service, web and Switch Rswag specs | EXECUTED / PASSED — 75 examples, 0 failures |
| Full `rake rswag:specs:swaggerize`, RSWAG_DRY_RUN=0 | EXECUTED / PASSED — 367 examples, 0 failures, 12 existing pending Post scaffold cases |
| `npm run build` / `npm run build:css` | EXECUTED / PASSED (existing Sass deprecation warnings) |
| `rails assets:precompile`, test environment | EXECUTED / PASSED — compiled assets only, no browser/deployment proof |
| `rails routes -g switches` | EXECUTED / PASSED — all nine routes and namespace fallback present |
| Diff/whitespace checks including new files | EXECUTED / PASSED at Developer handoff |
| MySQL adapter/index migration and query verification | NOT TESTED — local MariaDB startup blocked by UNIX socket EPERM |
| Actual browser interaction / physical relay / reminder execution | NOT TESTED |
| Production API, migration, deployment, hardware MQTT | NOT TESTED |

Focused command:

```bash
bundle exec rspec \
  spec/requests/api/switches_spec.rb \
  spec/services/switch_api_publisher_spec.rb \
  spec/requests/switch_relay_statistics_spec.rb \
  spec/requests/api/switches_swagger_spec.rb
RSWAG_DRY_RUN=0 bundle exec rake rswag:specs:swaggerize
```

### Validation environment qualification

Ruby 3.1.2 was built in an isolated runtime because the workspace had no Ruby.
Repository Gemfile/Gemfile.lock/package.json/yarn.lock were not changed. The
original lock references unavailable ffi-1.17.0 platform packages; validation
used an **ignored temporary Gemfile/lock** containing the same ffi 1.17.0 built
from source instead of its prebuilt platform packages. Bundled application gem
versions otherwise follow the lock. This is not proof of a clean frozen install
of the original platform lock on the deployment host. Re-run required checks in
the normal developer/CI environment before release.

Initial full Swagger execution exposed a pre-existing missing Authorization
fixture in `spec/requests/api/devices_spec.rb`. Only the fixture setup and invalid
token override were added to make required full generation executable; no device
endpoint behavior changed. Final full generation passed after this repair.

## Review/fix evidence

Independent static Reviewer found a normal heartbeat timestamp format was lost:
`Time.current.to_s` output was not accepted by the first last_seen parser.
Developer added strict explicit-offset legacy parsing plus ISO8601, with a
passing regression for producer format, invalid dates and missing offsets.

Post-test independent Reviewer returned READY WITH NON-BLOCKING NOTES for the
bounded phase-1 source change (30 files before this report). No remaining
confirmed blocking code defect was found. Supplemental review of this report
and the final evidence gate are still separate steps. This is not release
approval or commit authority. Commit/push authority from the earlier
documentation-only delivery does not authorize code delivery.

## Open acceptance gates / release notes

- MySQL-compatible index migration still needs target-engine verification and
  operational DDL/locking assessment. SQLite success is not MySQL acceptance.
- Reminder execution-owner gate in architecture section 8 is unresolved. No new
  scheduler was added; reminder writes stay unavailable and full mobile integration
  remains blocked. The backend task must remain open.
- New facade defaults off. Backend rollout, exact-SHA checks and authorized safe
  device command smoke are required before enabling it for mobile.
- Existing legacy API access-control debt remains separate; this facade does not
  close old anonymous routes. No firmware/backfill/auth refactor was smuggled in.
- Statistics intentionally count RelayLog records; new DeviceEvent audits are
  a different stream. No physical-runtime or unique-operation claim is made.
- Existing tracked database configuration contains hard-coded credentials. This
  pre-existing risk was not reproduced here or changed in this scoped task.

## Complete changed-file set

The following list includes this report and every tracked/untracked deliverable;
ignored validation runtimes, DBs, compiled assets and logs are not deliverables.

- `ai/tasks/z8tvbhwpn1-switch-mobile-api-implementation.md`
- `app/controllers/api/devices_controller.rb`
- `app/controllers/api/switches_controller.rb`
- `app/controllers/devices_controller.rb`
- `app/javascript/controllers/application.js`
- `app/models/device_event.rb`
- `app/services/switch_api/configuration.rb`
- `app/services/switch_api/error.rb`
- `app/services/switch_api/features.rb`
- `app/services/switch_api/publisher.rb`
- `app/services/switch_command_service.rb`
- `app/services/switch_detail_query.rb`
- `app/services/switch_relay_statistics_query.rb`
- `app/services/switch_reminder_service.rb`
- `app/views/devices/_switchon_form.erb`
- `app/views/devices/relay_statistics.html.erb`
- `config/routes.rb`
- `db/migrate/20261027000000_add_switch_statistics_index_to_relay_logs.rb`
- `db/schema.rb`
- `docs/SWITCH_MOBILE_API.md`
- `spec/fixtures/switch_api/command.json`
- `spec/fixtures/switch_api/detail.json`
- `spec/fixtures/switch_api/reminder-write-disabled.json`
- `spec/fixtures/switch_api/reminders.json`
- `spec/fixtures/switch_api/statistics.json`
- `spec/requests/api/devices_spec.rb`
- `spec/requests/api/switches_spec.rb`
- `spec/requests/api/switches_swagger_spec.rb`
- `spec/requests/switch_relay_statistics_spec.rb`
- `spec/services/switch_api_publisher_spec.rb`
- `swagger/v1/swagger.yaml`
