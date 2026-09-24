# Web PIR ↔ Buzzer management

Task: `z8tvbhtj1r`. Backend source of truth: issue #105 / PR #106 and
[API_BUZZER_MOBILE.md](API_BUZZER_MOBILE.md).

## Integration

The existing Buzzer detail card renders `_buzzer_links.html.erb` and uses
`buzzer_links.js`, loaded by the existing esbuild entry point. No framework,
backend route, service, authentication, or MQTT changes are needed. The original
server-rendered linked list remains available when JavaScript is disabled.

The browser uses the signed-in Rails session with same-origin cookies, JSON
requests, and the page's CSRF token. Authorization remains on the server.
All names are rendered as text, never interpreted as HTML.

## Shared Web / Swift / Flutter semantics

- Load linked and available PIRs from the two existing GET endpoints. Show
  loading, empty lists, API errors and an explicit refresh action.
- Display linked PIR name, relay index and duration in milliseconds; null names
  fall back to the PIR chip ID, and unavailable legacy settings display `—`.
- “Liên kết” submits the selected PIR and integer settings. Relay index starts
  at zero; duration is 100–10000 ms inclusive. Existing current-Buzzer settings
  are prefilled when selecting an already linked PIR.
- For another accessible `linked_buzzer`, show its permitted name and require
  “Chuyển & liên kết” confirmation explaining that the previous Buzzer will no
  longer be triggered by this PIR.
- When `requires_confirmation` is true but `linked_buzzer` is null, require a
  generic “Thay thế & liên kết” confirmation. Do not infer an inaccessible
  target's identity. Both cases use the same POST endpoint.
- Unlink requires confirmation explaining that the PIR stops triggering this
  Buzzer and that the operation does not sound or test it. Use the existing
  DELETE endpoint. Its idempotent success is treated normally.
- After any successful mutation, close/reset the form and refresh **both**
  lists and the linked-PIR counters. Historical events remain the server-rendered
  page snapshot until a page reload.
- Disable management controls while a request is pending. A failed refresh
  leaves management disabled until both lists can be refreshed. A successful
  mutation followed by failed refresh is explicitly reported as saved, with
  stale-list guidance. After a mutation error (including an uncertain transport
  outcome), require refresh before another write. HTTP 401 asks for sign-in;
  HTTP 404 does not distinguish missing devices from inaccessible devices.
- Confirmation is a client interaction, not a backend concurrency token. Another
  client can change a link after this page loads; #105's last-write-wins behavior
  remains the shared contract.
- Test Buzzer remains a separate existing form/action. Management never calls
  Test Buzzer, the runtime trigger endpoint, or MQTT.

Turbo page transitions remove management listeners and abort pending fetches.
Restoring a cached page reloads both lists before enabling management.

## Verification

Rails request/view specs remain in `spec/features/buzzer_device_ui_spec.rb`.
Real browser behavior tests use the actual HTML partial and JavaScript with
mocked API responses:

```sh
node spec/javascript/buzzer_links_test.mjs
```

The test runner requires Chrome; set `CHROME_BIN` on systems where its path is
not `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`. It uses a
local fixture server and an isolated temporary browser profile. It never
contacts the application API or a real MQTT broker.

Build JavaScript/CSS and precompile assets before release as described in
[RELEASE_PRODUCTION.md](RELEASE_PRODUCTION.md). No migration is required.
