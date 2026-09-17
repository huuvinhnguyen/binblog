# Binblog Coding Conventions

## Purpose and scope

These conventions apply to all new and modified code in Binblog: Rails,
MySQL migrations, IoT devices, MQTT, APIs, JavaScript, SCSS, tests and
operational documentation. Follow existing code when a safe, compatible local
pattern already exists; use this document to resolve ambiguity.

## Core principles

- Prefer the smallest compatible change. Do not rewrite unrelated legacy code.
- Keep device commands safe, traceable and idempotent when retries are possible.
- Treat every client-provided device identifier and JSON field as untrusted.
- Preserve API compatibility unless a breaking change is explicitly approved.
- Do not mutate production data, publish MQTT commands, deploy, or run
  production migrations without explicit authorization.
- Do not commit credentials, JWTs, pairing codes, broker passwords, webhook
  URLs or production data dumps.

## Ruby and Rails

- Use Ruby 3.1+ and Rails 7 idioms. Use two-space indentation and descriptive
  `snake_case` names.
- New models inherit from `ApplicationRecord`; new controllers inherit from
  `ApplicationController` unless a framework requires otherwise.
- Keep controllers small: authenticate/authorize, validate input, call a
  service, and render one response. Put multi-step business logic, MQTT work,
  retries and transaction coordination in `app/services/`.
- Use guard clauses and explicit error responses. Do not rescue `StandardError`
  merely to hide errors; log useful context and return a deliberate status.
- Use `Time.current`, `Time.zone`, and ISO 8601 for application timestamps;
  do not use `Time.now` in application logic.
- Parse JSON defensively. Invalid or blank stored JSON must not crash a page or
  API; return a safe empty value and surface configuration errors appropriately.
- Avoid N+1 queries with `includes`, bounded queries, and targeted projections.

## Devices and ownership

- `devices.chip_id` is the stable external device identifier and must be unique
  and validated before a query or command.
- All user-facing device access must verify ownership through the authenticated
  user. Administrators may use the established admin access path.
- Do not link a device to a user merely because an ESP sends an online message.
  Device ownership must be created through an authenticated claim/pairing flow.
- New device types use a clear `device_type` value such as `switch`, `pir`,
  `dht`, or `buzzer`; their dedicated UI is rendered explicitly in
  `app/views/devices/show.html.erb`.
- Store non-secret device configuration as JSON text only when the shape is
  genuinely flexible. Use normal columns/tables for searchable, relational or
  security-sensitive data.

## PIR, Buzzer and trigger semantics

- In `POST /api/devices/trigger`, `params[:chip_id]` identifies the source
  device. For a PIR call, it is the PIR chip ID.
- The source PIR's `trigger` JSON identifies the target command. Its
  `trigger.chip_id` is the Buzzer/relay target and is used to build the MQTT
  topic.
- Keep the existing relay command fields when using existing firmware:
  `chip_id`, `relay_index`, `switch_value`, and `longlast` in milliseconds.
- A Buzzer is a `device_type: "buzzer"` target. It does not need its own
  `trigger` configuration for PIR-driven commands.
- Do not call the trigger endpoint with a Buzzer chip ID as if it were a PIR;
  the controller interprets the supplied chip ID as the source device.
- When recording a PIR-triggered command, persist `motion_detected` on the PIR.
  Include target metadata such as `target_chip_id`, `relay_index`, and
  `longlast` in `DeviceEvent.payload` when it is needed for Buzzer history.
- Never claim that a Buzzer activated unless firmware has supplied a reliable
  acknowledgement. Without ACK, use wording such as “command received” or
  “command sent”, not “Buzzer rang”.

## Device events

- Device events are append-only facts. Do not overwrite a Boolean state to
  represent event history.
- Use only allowed `DeviceEvent::EVENT_TYPES`. Add a type deliberately, update
  the model, tests, API documentation and UI labels together.
- Always set `occurred_at`; event payloads contain metadata, never secrets.
- Query event histories with a time range, order and limit. Do not load an
  unbounded device event collection into a controller or view.
- Add an index whenever a new dashboard/API query depends on device, event type
  and time. The standard access path is `(device_id, event_type, occurred_at)`.

## Database and migrations

- Binblog uses MySQL. Do not use PostgreSQL-only types or syntax such as
  `jsonb`; use `text` plus serialization where appropriate.
- Give migrations descriptive names, use Rails migration APIs, add foreign keys
  and indexes for lookup paths, and preserve existing data on deploy.
- Use `null: false` only when existing records and all creation paths can meet
  the constraint. Provide defaults only when they have valid business meaning.
- Do not use destructive data migrations or broad backfills without an explicit
  rollback and production approval.

## MQTT and background work

- Keep MQTT connection and publish behavior outside controllers where possible.
  Read broker configuration from configuration, not hard-coded new values.
- Validate a command before publishing: target chip ID, topic, payload shape,
  relay index and duration must be valid.
- Add a command/event identifier and deduplication strategy when a device or
  job can retry. Always disconnect clients in an `ensure`-style cleanup path.
- Log command outcomes with non-sensitive identifiers. Never log credentials or
  complete secret payloads.
- Use Sidekiq for delayed, retryable or potentially slow work; ensure jobs are
  safe to execute more than once.

## APIs and security

- Use RESTful routes and explicit HTTP status codes: `200/201` success,
  `401` unauthenticated, `403` unauthorized, `404` inaccessible/not found,
  `422` invalid input.
- Authenticate user-facing APIs with the established JWT/session mechanism and
  authorize the specific device after authentication.
- Device onboarding uses a short-lived, one-time pairing code. Store only a
  digest, expire it, rate-limit attempts, and erase it from device storage after
  successful pairing.
- Validate and permit only expected parameters. Do not trust user IDs, device
  IDs, timestamps, relay indexes or durations supplied by a client.
- Public API changes require a matching Rswag request spec and regenerated
  `swagger/v1/swagger.yaml` for `/api-docs`.

## Views, JavaScript and styles

- Use ERB partials by device type; keep presentation logic out of controllers.
- Scope styles with component classes such as `.pir-device` or `.buzzer-device`;
  avoid broad selectors that can alter unrelated Rails Admin or legacy pages.
- JavaScript must work with Turbo navigation: initialize on `turbo:load`, guard
  missing DOM elements, and avoid duplicate event listeners/charts.
- Chart code must handle loading, empty and API-error states. Destroy or update
  an existing Chart.js instance rather than creating duplicates.
- Use accessible labels, semantic buttons, confirm destructive UI actions, and
  support narrow screens.

## Testing and verification

- Add focused RSpec coverage for every behavior change: model validation,
  service logic, request authorization/error paths, and visible UI behavior as
  appropriate.
- Mock external MQTT/HTTP calls in tests. Tests must not publish to a real
  broker or depend on production services.
- For a new device flow, cover: valid input, unknown chip ID, inaccessible
  device, malformed JSON, retry/duplicate behavior, and the empty UI state.
- Run the narrow relevant specs first, then route/OpenAPI checks when APIs
  change. Always run `git diff --check` before handing off.

## Documentation and release

- Document user-visible device setup, MQTT/API contracts, firmware assumptions,
  rollback behavior and any operational risk under `docs/`.
- Update Swagger whenever a public endpoint changes.
- For JavaScript, SCSS or Chart.js changes, follow `docs/RELEASE_PRODUCTION.md`:
  build JavaScript and CSS before asset precompile, then verify the new
  fingerprint and hard-refresh behavior.
- State exactly what was verified and what remains an assumption. Do not present
  an unverified MQTT delivery or production result as completed.
