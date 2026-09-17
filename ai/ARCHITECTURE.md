# Binblog Architecture

## Purpose

This document describes the current technical architecture of Binblog and the
boundaries to preserve when extending it. It is an implementation map, not a
deployment runbook; use `docs/RELEASE_PRODUCTION.md` for operational release
steps and `ai/CONVENTIONS.md` for coding rules.

## System overview

Binblog is a Rails 7 application that manages people, content and IoT devices.
The IoT domain supports relay switches, DHT sensors and PIR sensors. Devices
communicate with the Rails application over HTTP and MQTT; browser pages use
Rails views, Turbo, ActionCable and JavaScript dashboards.

```text
Browser
  │ Rails HTML, JSON API, ActionCable
  ▼
Rails 7 / Puma
  ├─ Controllers, models, services, jobs
  ├─ Devise session auth + JWT API auth
  ├─ Rswag UI and OpenAPI at /api-docs
  ▼                         │
MySQL                       Redis / Sidekiq
  │                         └─ scheduler + MQTT listener thread
  ▼
Users, devices, events, relay logs
                              │
                              ▼
                         MQTT broker
                              │
                     ESP8266 / ESP32 devices
```

## Runtime components

### Rails web application

- Rails 7 runs the web UI, JSON API, Rails Admin, ActionCable and device-facing
  HTTP endpoints.
- `ApplicationController` sets the Vietnamese locale and uses CSRF protection;
  JSON requests use a null session.
- Devise provides browser authentication. Selected API endpoints decode a JWT
  bearer token and may fall back to an authenticated browser session.
- Rswag serves API documentation and the generated OpenAPI document at
  `/api-docs`.

### Database

- Production and development use MySQL with `utf8mb4`.
- Test uses SQLite. Features using SQL functions, JSON querying, timestamps,
  indexes or migrations must therefore be verified against MySQL semantics.
- Application time zone is `Asia/Ho_Chi_Minh`; Active Record is configured to
  use local time. Persist/query time-series data through `Time.current` and
  `Time.zone`.

### Redis, Sidekiq and scheduler

- Sidekiq handles delayed/background work such as reminders and relay timing.
- Sidekiq Scheduler loads `config/sidekiq_scheduler.yml` at server startup.
- The Sidekiq server starts `Mqtt::DeviceListenerService` in a dedicated thread.
  The listener reconnects to MQTT and currently subscribes to the shared
  `device` topic.

### MQTT

- Rails publishes device commands and listens for telemetry/command-related
  messages.
- Existing relay commands use a per-device topic such as
  `{target_chip_id}/switchon`.
- The MQTT listener currently parses the shared `device` topic and creates
  `RelayLog` records from received relay-related messages.
- Broker configuration belongs in `config/mqtt.yml`; some older code still has
  broker connection details embedded in services/controllers and should not be
  copied into new code.

### Browser assets

- Rails views use ERB, Bootstrap and SCSS.
- Turbo/Stimulus are available; JavaScript is bundled with esbuild and CSS with
  Sass into `app/assets/builds`.
- Chart.js powers PIR motion charts. ActionCable distributes MQTT-related
  browser updates through `MqttChannel`.

## Primary domain model

### Users and authorization

`User` uses Devise and Rolify. Users have a many-to-many association with
`Device` through `devices_users`.

```text
User ──< devices_users >── Device
```

- Standard users access their associated devices.
- Administrators use `devices_for_current_user` to access all devices.
- Device ownership is an authorization boundary for user-facing pages and APIs.

### Devices

`Device` is the hardware aggregate. `chip_id` is unique and is the stable
external identifier used by ESP firmware and MQTT topics.

Important fields:

- `name`, `chip_id`, `device_type`, `status`, `note`, `url_firmware`.
- `device_info`: flexible JSON text for device configuration and relay details.
- `trigger`: flexible JSON text that describes a device-triggered MQTT command.
- `meta_info`: JSON text for information such as last seen, local IP and
  firmware version.

Current device types:

- `switch`: relay controller with one or more relay configurations.
- `dht`: temperature/humidity sensor.
- `pir`: motion sensor.
- `buzzer`: planned target device type for a relay-driven audible alert UI.

### Events and command history

```text
Device ──< DeviceEvent
Device ──< RelayLog
Device ──< Reminder
```

- `DeviceEvent` is append-only time-series history. Current event types include
  `motion_detected`, `buzzer_started`, `buzzer_finished`, `device_online`, and
  `device_offline`.
- `DeviceEvent.payload` is serialized JSON metadata. It is not a secret store.
- The main event lookup index is `(device_id, event_type, occurred_at)`.
- `RelayLog` records relay command/activity information including source,
  timestamps, status and errors.
- `Reminder` represents scheduled relay behavior and is coordinated with
  Sidekiq jobs.

## Device communication flows

### Device registration and heartbeat

Devices send initialization/metadata messages through existing endpoints and
MQTT. Rails can create or find a record from an incoming device identifier and
updates metadata such as local IP and firmware version through the last-seen
flow.

Incoming device traffic must not by itself grant a user ownership. Pairing is a
future onboarding boundary: a user creates a short-lived pairing request, the
ESP enters the code in its Wi-Fi captive portal, and Rails attaches the verified
device to that user.

### Switch command

```text
User UI or API
  → Rails authorization and command/service logic
  → RelayLog
  → MQTT {chip_id}/switchon
  → ESP relay action
  → optional MQTT status message
```

The stored relay configuration determines relay index, state and duration;
web clients should not be allowed to bypass this configuration arbitrarily.

### PIR to Buzzer trigger

The current `POST /api/devices/trigger` contract treats request `chip_id` as
the **source device**. A PIR firmware call therefore submits its own chip ID.

```text
PIR ESP
  → POST /api/devices/trigger { chip_id: PIR chip ID }
  → Rails finds PIR and records motion_detected on PIR
  → Rails reads PIR.trigger JSON
  → MQTT {PIR.trigger.chip_id}/switchon
  → target Buzzer/relay receives switch_value and longlast
```

The `trigger.chip_id` is the target Buzzer/relay chip ID. Existing Buzzer
firmware expects `switch_value` and `longlast`; do not replace this command
shape without coordinating a firmware release.

For a future Buzzer screen, Rails should add `target_chip_id`, relay index and
duration to the source PIR event payload. This makes it possible to show which
PIR events targeted a particular Buzzer while retaining the correct event owner
(the PIR).

### PIR analytics

PIR pages load the latest motion events and fetch protected API statistics:

- `GET /api/devices/motion_stats`: 24 hourly buckets for a selected date.
- `GET /api/devices/motion_heatmap`: daily counts for a selected window.

The browser uses `pir_motion_chart.js` and Chart.js to render the hourly chart
and heatmap. Statistics use `occurred_at` in the application time zone.

## Request and API boundaries

### Web UI

- REST-style `resources :devices` pages are used for authenticated device
  management.
- Device-specific UI is selected in `app/views/devices/show.html.erb` and
  rendered through partials such as `_switchon_form`, `_dht_form` and
  `_pir_form`.

### JSON API

- API routes are under `/api` and are defined in `config/routes.rb`.
- `Api::DevicesController` currently contains both legacy relay actions and
  newer device/statistics actions. New multi-step behavior should be extracted
  into services rather than expanding this controller.
- Public API changes require matching Rswag request specs and regenerated
  `swagger/v1/swagger.yaml`.

### Trust boundary

- Browser/API users must be authenticated and authorized against device
  ownership before reading or changing device data.
- Existing device-facing endpoints are legacy and not uniformly authenticated.
  New device onboarding or command paths must introduce explicit device
  credentials/pairing rather than copying this limitation.
- MQTT delivery is asynchronous. A successful Rails response proves request
  handling, not necessarily physical device action, unless an acknowledgement
  is received and recorded.

## Code organization

```text
app/controllers/       HTTP orchestration and rendering
app/models/            Active Record domain models
app/services/          business services and MQTT-facing behavior
app/jobs/              Active Job background work
app/worker/            legacy Sidekiq workers
app/channels/          ActionCable channels
app/views/             ERB templates and device partials
app/javascript/        Turbo, ActionCable and Chart.js behavior
app/assets/stylesheets SCSS component styling
config/                routes, environment, MQTT and Sidekiq configuration
db/migrate/            schema changes
lib/tasks/             operational rake tasks
spec/                  RSpec request, model, service and feature tests
docs/                  user and production operational documentation
ai/                    architecture and engineering guidance
```

## Extension guidelines

### Adding a device type

1. Add/validate the `device_type` and device configuration shape.
2. Update the device creation rake task and user documentation.
3. Add a dedicated view partial and scoped SCSS/JavaScript if necessary.
4. Add ownership checks, tests, empty/error states and release asset steps.
5. Update the architecture/documents when MQTT/API semantics change.

### Adding an event-driven automation

1. Identify the source device and preserve it as the event owner.
2. Define the target command in a service/configuration boundary.
3. Record enough non-secret metadata to trace source, target and duration.
4. Decide retry, cooldown, idempotency and acknowledgement behavior.
5. Add indexes and bounded queries for every dashboard/reporting path.

### Adding a public API

1. Define request/response/error contracts and authentication first.
2. Authorize the specific device/entity, not just the signed-in user.
3. Write request specs and add Rswag documentation.
4. Preserve existing clients or introduce an explicitly versioned migration.

## Known architectural constraints

- Several legacy controller actions combine transport, business logic and MQTT
  publishing; new work should move complexity outward into services.
- Device JSON configuration is stored as text, so searching relationships inside
  it is limited. Use a relational table when a relationship must be queried or
  governed at scale.
- The test database is SQLite while runtime uses MySQL; test MySQL-specific
  migrations and queries before production release.
- MQTT listener availability depends on Sidekiq startup and broker connectivity.
  Monitor listener logs and reconnect behavior in production.
- Existing device APIs may lack device-level authentication. Pairing codes and
  device credentials should be introduced before exposing new sensitive flows.

## Change verification

For every architecture-affecting change:

1. Run focused RSpec tests and relevant route/OpenAPI generation.
2. Validate MySQL-compatible migrations and indexes.
3. Verify MQTT payload/topic behavior with a non-production device or mock.
4. Build JavaScript/CSS and precompile assets when frontend code changes.
5. Run `git diff --check` and update `docs/` plus this document if boundaries
   or data flows changed.
