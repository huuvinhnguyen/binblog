# Buzzer Mobile API

These endpoints support the unified Swift and Flutter Buzzer screen. They use the
same JWT authentication as the other user-facing APIs and never expose MQTT
credentials.

## Authentication and authorization

Send the JWT returned by `POST /api/login` as:

```http
Authorization: Bearer <token>
```

The `:id` path value is the Rails `devices.id` of a device accessible through
the authenticated user. A missing, inaccessible, or non-Buzzer device returns
`404` with `{ "status": "error", "message": "Buzzer device not found" }`.
The API intentionally does not distinguish those cases.

## Detail

`GET /api/devices/:id/buzzer`

```json
{
  "status": "success",
  "buzzer": {
    "id": 42,
    "name": "Hall Buzzer",
    "chip_id": "ESP32_BUZZER_02",
    "device_type": "buzzer",
    "online": true,
    "last_seen": "2026-09-19T10:30:00+07:00",
    "linked_pir_count": 2,
    "last_triggered_at": "2026-09-19T10:29:00+07:00"
  }
}
```

`last_seen` and `last_triggered_at` may be `null`. `online` is derived from the
Buzzer's `device_info.update_at` and is true only when it is within five minutes.

## Linked PIRs

`GET /api/devices/:id/buzzer/linked_pirs`

Only accessible PIRs whose `trigger.chip_id` equals the Buzzer `chip_id` are
returned. Invalid trigger JSON is treated as an empty configuration. No matches return
`linked_pirs: []`. Names may be `null`. Relay index and duration are stored JSON
values returned without type coercion: `relay_index` defaults to `0` when null or
false, and missing `longlast` returns `null`.

```json
{
  "status": "success",
  "linked_pirs": [
    {
      "id": 7,
      "name": "Hall PIR",
      "chip_id": "ESP32_PIR_01",
      "relay_index": 0,
      "longlast": 1000
    }
  ]
}
```

## Recent history

`GET /api/devices/:id/buzzer/history`

Returns at most 20 newest `motion_detected` events from accessible linked PIRs
whose `payload.target_chip_id` equals the Buzzer `chip_id`. Ties are ordered by
`id` descending. Older events without target metadata are not attributed to a
Buzzer. No matches return `events: []`. Nested PIR names may be `null`.
`relay_index` and `longlast` are stored payload JSON values returned without type
coercion and are `null` when absent.

```json
{
  "status": "success",
  "events": [
    {
      "id": 123,
      "event_type": "motion_detected",
      "occurred_at": "2026-09-19T10:29:00+07:00",
      "pir": { "id": 7, "name": "Hall PIR", "chip_id": "ESP32_PIR_01" },
      "relay_index": 0,
      "longlast": 1000
    }
  ]
}
```

## Test action

`POST /api/devices/:id/buzzer/test`

The request has no body. Rails reuses `BuzzerTestService`, which reads the
configured relay duration from the Buzzer, applies validation and a three-second
per-Buzzer cooldown, publishes the existing MQTT command, and records a
`buzzer_test_requested` audit event.

A successful HTTP `200` response means Rails completed the existing MQTT publish
call and recorded the request. The current service does not explicitly request
QoS 1 or provide a broker `PUBACK` guarantee. It does **not** confirm that
the physical Buzzer received, activated, or produced sound. Mobile clients should
therefore display a command-sent state rather than a physical-execution state:

```json
{
  "status": "success",
  "message": "Command sent to MQTT broker",
  "relay_index": 0,
  "longlast": 1000
}
```

Authentication failures (`401`) return `{ "error": "Unauthorized" }`.
Other documented errors use `{ "status": "error", "message": "..." }`:

| Status | Meaning |
| --- | --- |
| `401` | Missing or invalid JWT |
| `404` | Missing, inaccessible, or non-Buzzer device |
| `422` | Invalid Buzzer relay configuration |
| `429` | Test cooldown is active |
| `503` | MQTT publish failed |

The existing web route and firmware trigger contract are unchanged.

## Manage PIR links (#105)

Phase 1 stores the relationship in the PIR's existing `Device#trigger` JSON text:
one PIR targets at most one Buzzer; one Buzzer can have many PIRs. No new table,
firmware change, or migration is required. All three management endpoints use the
existing JWT/session authentication and `devices_for_current_user` access scope
(including the established administrator behavior). Both the target Buzzer and
source PIR must be accessible and have the correct device type.

These are configuration operations only. They do not connect to MQTT, invoke
Test Buzzer, or sound a device. The existing four Buzzer APIs remain unchanged.

### Available PIRs

`GET /api/devices/:id/buzzer/available_pirs`

Returns `{"status":"success","available_pirs":[...]}`, ordered by PIR ID.
The list includes accessible PIRs already linked to this or another Buzzer and
is empty when none are accessible. Each entry contains:

```json
{
  "id": 7,
  "name": "Hall PIR",
  "chip_id": "ESP32_PIR_01",
  "linked_buzzer": { "id": 42, "name": "Hall Buzzer" },
  "requires_confirmation": true
}
```

`name` and `linked_buzzer.name` may be null. `linked_buzzer` is null when no
accessible Buzzer matches the stored target. A null value does not prove that
the PIR has no existing configuration. No inaccessible target's ID, name, chip
ID, or raw trigger is exposed.

`requires_confirmation` is false for an absent/empty configuration or a trigger
already targeting the selected Buzzer, and true when an existing configuration
would be replaced. Web, Swift and Flutter should show **Move & Link** when the
visible current Buzzer differs from the selected Buzzer. When confirmation is
required but `linked_buzzer` is null, show a generic replace-configuration
confirmation without claiming another device's identity. This is advisory UI
state, not a server confirmation token; a subsequent POST explicitly replaces
configuration. Refresh the list after mutations. Current relay/duration values
remain available through the existing `GET .../linked_pirs` API.

### Link / relink

`POST /api/devices/:id/buzzer/linked_pirs`

Send `Content-Type: application/json`:

```json
{ "pir_id": 7, "relay_index": 0, "longlast": 1000 }
```

All three fields are required JSON integers (numeric strings, fractions, nulls,
and booleans are rejected). `pir_id` must be positive, `relay_index` must be at
least zero, and `longlast` must be between 100 and 10000 milliseconds inclusive.
The backend does not infer a relay-count limit from device configuration.

Success (`200`):

```json
{
  "status": "success",
  "linked_pir": {
    "id": 7, "name": "Hall PIR", "chip_id": "ESP32_PIR_01",
    "relay_index": 0, "longlast": 1000
  }
}
```

The backend replaces the complete stored trigger with normalized JSON containing
only `chip_id` (the selected Buzzer), `relay_index`, and `longlast`. This also
replaces malformed or other existing configuration, so clients must honor the
confirmation guidance above. Repeating the same request produces the same
state; posting different settings updates them. Relinking removes the PIR from
the old Buzzer's linked-PIR list and adds it to the new one immediately.

The existing runtime reads and publishes this JSON plus its existing
`sent_time`, without firmware or MQTT changes. Management does not claim physical
device acknowledgement. Concurrent writes are serialized under a PIR row lock;
the last completed link determines the stored configuration.

### Unlink

`DELETE /api/devices/:id/buzzer/linked_pirs/:pir_id` (no body)

Success (`200`): `{"status":"success","pir_id":7}`.

Under a PIR row lock, remove `chip_id`, `relay_index`, `longlast`, `switch_value`,
and `sent_time` only when `trigger.chip_id` matches the selected Buzzer. Preserve
any other metadata. A normalized link becomes the JSON text `{}`. Repeating
unlink is a successful no-op. A different target, absent configuration, or
malformed JSON is also left untouched; no target identity is disclosed.

Unlink does not change the legacy motion endpoint's handling of an unconfigured
PIR: a subsequent trigger request can still return its existing missing-target
error. This issue does not add a new runtime no-op response for unlinked PIRs.

### Management errors

- `401`: missing/invalid authentication; `{"error":"Unauthorized"}`.
- `404`: missing, inaccessible, or wrong-type Buzzer/PIR. Response is
  `{"status":"error","message":"Buzzer device not found"}` or
  `{"status":"error","message":"PIR device not found"}`. The response does not
  distinguish absence, ownership, or wrong device type. Invalid DELETE PIR path
  IDs also return `404`.
- `422` (POST only): missing/invalid body fields;
  `{"status":"error","message":"..."}` explains the failed validation.

Management does not use the Test Buzzer cooldown, configuration, or publish
errors (`429`/`503`). Authentication and target authorization run before body
validation; a valid integer PIR ID is resolved through the access scope before
relay/duration validation.
