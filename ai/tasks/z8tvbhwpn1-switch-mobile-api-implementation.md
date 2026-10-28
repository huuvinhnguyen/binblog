# Developer handoff — Switch API phase 1

Task: https://app.clickup.com/t/z8tvbhwpn1
Branch: `feature/z8tvbhwpn1-switch-mobile-api`
Integration base: `main@47b6ca0` (merged handoff PR #119 verified).
Date: 2026-10-27. No commit/push or deployment claimed by this report.

## Verification checkpoint continuation

The original phase-1 implementation was subsequently published at the owner's
request as Draft PR #120, commit `e05c4ac9a8878e8acb9d5df2d349e93fb0e383ab`.
The original final gate remains **BLOCKED — INSUFFICIENT EVIDENCE**, because
the MySQL checks below have not yet executed. Historical delivery/authorization
statements below describe the initial handoff, not the current PR state.

The follow-up adds only a MySQL verification checkpoint: a GitHub Actions job,
an isolated runner and a live-MQTT connection guard. No application behavior,
scheduler, reminder readiness or production configuration changes are included.
The job uses a disposable MySQL 8 service, Ruby 3.1.2, read-only token permissions,
no production secrets, and two process timezones (UTC and Asia/Ho_Chi_Minh).
The existing temporary source-built ffi workaround is explicit; repository
dependency files remain unchanged.

The runner requires an explicit test environment and local database named
`binblog_switch_api_test`. It checks migration down/up, ordered index and row
preservation; scoped/empty/31-day counts and midnight boundaries under two MySQL
session timezones; bounded metadata-lock contention; and two command connections
waiting on an actual InnoDB row lock. Publishers are fake and assert that the
database transaction has finished. CI also runs the focused request/service/web/
OpenAPI examples and uploads logs for independent verification. This proves
neither production DDL timing nor hardware acceptance.

Local checkpoint checks: Ruby syntax and fail-closed environment/database guards
**EXECUTED / PASSED**; workflow YAML and actionlint **EXECUTED / PASSED**.
MySQL execution and CI outcome are **NOT RUN** at checkpoint authoring. Publishing
this test checkpoint to collect evidence must not be reported as the application's
Final Verification passing or permission to merge/release. Keep PR Draft and the
backend task open until the appropriate gates actually pass.

The first CI run (`40715427890`) failed before application checks: setup-ruby
requires the configured temporary Gemfile to exist even with bundler caching off.
The workflow now prepares that file/lock before setup-ruby, then installs gems.
This is a CI setup fix, not evidence of a MySQL application test passing.

To reproduce on a disposable local MySQL database after loading `db/schema.rb`,
set `RAILS_ENV=test`, `TZ=UTC` (then `Asia/Ho_Chi_Minh`), an explicit
`DATABASE_URL=mysql2://<test-user>:<test-password>@127.0.0.1/binblog_switch_api_test?pool=10`,
and a non-production `SECRET_KEY_BASE`. Run:

```bash
bundle exec ruby script/verify_switch_mysql.rb
bundle exec rspec --require ./script/switch_verification_no_mqtt.rb \
  spec/requests/api/switches_spec.rb spec/services/switch_api_publisher_spec.rb \
  spec/requests/switch_relay_statistics_spec.rb spec/requests/api/switches_swagger_spec.rb
```

Use the guard for schema loading as shown in the workflow, too. Never point this
runner or a schema-load command at a shared or production database. MySQL's
`PROCESS` privilege is required to observe the worker transactions during this
disposable test; this is not a request to grant it to the application user.

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
- `.github/workflows/switch-mysql-verification.yml`
- `script/verify_switch_mysql.rb`
- `script/switch_verification_no_mqtt.rb`
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
