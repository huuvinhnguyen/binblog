# Binblog Project Guide

## What Binblog is

Binblog is a Ruby on Rails application for managing users, employees, content
and IoT devices. Its device domain manages ESP8266/ESP32 hardware such as relay
switches, DHT sensors and PIR motion sensors. The application provides browser
management screens, JSON APIs, MQTT integration, realtime updates and
time-series device history.

## Product goals

- Let authenticated users register, own and manage their devices.
- Control relays safely through stored configuration and MQTT.
- Record device activity as traceable history, especially PIR motion events.
- Present usable dashboards for device status, history and sensor analytics.
- Support operational workflows such as reminders, firmware metadata and
  notifications without exposing device infrastructure to browser clients.

## Primary users

- **Standard user**: manages only their associated devices.
- **Administrator**: manages all devices and administrative configuration.
- **ESP device**: calls device-facing HTTP endpoints and receives MQTT commands.
- **Operator/developer**: creates devices, runs migrations, monitors Sidekiq and
  MQTT, builds assets and releases the application.

## Domain glossary

- **Device**: a physical ESP-backed unit identified by a unique `chip_id`.
- **Device type**: the device role, including `switch`, `dht`, `pir` and the
  planned `buzzer` target type.
- **Source device**: a device that initiates an event or command. For PIR
  trigger requests, request `chip_id` is the source PIR.
- **Target device**: hardware receiving a command. For PIR-driven relay/Buzzer
  actions, the target is defined by `PIR.trigger.chip_id`.
- **Device event**: append-only, timestamped record of an observed occurrence.
- **Relay log**: command/activity history for relay behavior.
- **Trigger**: JSON command configuration stored on a source device and
  published by Rails through MQTT.
- **Pairing**: future verified onboarding that binds an ESP device to a user.

## Core device capabilities

### Relay switch

A switch stores relay configuration in `device_info`, can be controlled from
the web/API, and can run reminders through Sidekiq. Commands are published over
MQTT to a device-specific `switchon` topic.

### PIR motion sensor

A PIR reports motion through `POST /api/devices/trigger` using its own chip ID.
Rails stores `motion_detected` on the PIR, reads the PIR's optional trigger
configuration, and may publish a target relay/Buzzer command. The PIR screen
shows history, hourly statistics and a daily heatmap.

### Buzzer

A Buzzer is a target relay-driven device type planned for a dedicated screen.
It is triggered by a PIR's stored command configuration; it should not be
treated as the source of `motion_detected` events.

## Technology snapshot

- Ruby 3.1+, Rails 7, Puma.
- MySQL for development/production; SQLite for test.
- Devise, Rolify and JWT-based API authentication.
- Sidekiq, Sidekiq Scheduler and Redis.
- MQTT for device commands and telemetry.
- ActionCable for browser realtime updates.
- ERB, Bootstrap, SCSS, Turbo, Stimulus, esbuild and Chart.js.
- RSpec and Rswag for tests and OpenAPI documentation.

## Important source locations

```text
app/controllers/              web/API request orchestration
app/models/                   persisted domain objects
app/services/                 business logic and MQTT-facing behavior
app/jobs/, app/worker/        asynchronous and legacy worker code
app/views/devices/            device detail screens and partials
app/javascript/               Turbo, ActionCable and charts
app/assets/stylesheets/       application and device SCSS
config/routes.rb              route contract
config/mqtt.yml               MQTT configuration
config/sidekiq_scheduler.yml scheduled jobs
db/migrate/                   schema history
lib/tasks/                    operational rake tasks
spec/                         RSpec and Rswag tests
swagger/v1/swagger.yaml       generated OpenAPI document
docs/                         operational and user-facing documentation
ai/                           project guidance for humans and AI
```

## Project guidance hierarchy

Read these documents before making a cross-cutting change:

1. `ai/CONVENTIONS.md` — coding, security, test and release conventions.
2. `ai/ARCHITECTURE.md` — component boundaries, data flow and constraints.
3. `docs/` relevant to the feature — user/device/release contracts.
4. Existing route, controller, model and spec code — the executable behavior.

When documentation and executable behavior disagree, treat running code and
tests as the current behavior, flag the mismatch, and update documentation as
part of the change.

## Current product boundaries

- Binblog manages physical devices but does not guarantee device delivery merely
  because an HTTP request or MQTT publish succeeds.
- Device events are history; they are not a replacement for a realtime device
  state protocol.
- Existing device-facing endpoints are legacy and not uniformly authenticated.
  New sensitive device flows must use pairing/device credentials.
- Configuration stored as JSON text is suitable for small flexible payloads;
  query-heavy or governed relationships should move to relational tables.

## Related documents

- `docs/REGISTER_PIR_DEVICE.md`
- `docs/REGISTER_SINGLE_RELAY_DEVICE.md`
- `docs/API_DEVICES_TRIGGER.md`
- `docs/BUZZER_PIR_ARCHITECTURE.md`
- `docs/RELEASE_PRODUCTION.md`
