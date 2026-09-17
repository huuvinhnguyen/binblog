# Binblog Engineering Workflow

## Goal

Use this workflow for all feature work, bug fixes and operational changes. It
keeps Rails, device firmware, MQTT, data, APIs, UI and release steps aligned.

## 1. Start with the boundary

Before editing code:

1. Read `ai/PROJECT.md`, `ai/CONVENTIONS.md` and the relevant section of
   `ai/ARCHITECTURE.md`.
2. Inspect the current route, controller, model, service, view, JavaScript,
   migration and focused specs.
3. Check `git status` and preserve unrelated changes in a dirty worktree.
4. Identify whether the task changes browser behavior, public API, device
   firmware, MQTT payloads, database schema, background jobs or deployment.
5. For cross-cutting IoT changes, write/update a short decision record under
   `docs/` before implementation.

## 2. Define the contract first

For any IoT/API feature, decide and document:

- Source and target device identities.
- HTTP method, authentication, authorization, request and response shape.
- MQTT topic, payload, timeout/retry and acknowledgement semantics.
- Event owner, event type, payload metadata and time zone.
- Empty/loading/error UI behavior.
- Idempotency, cooldown and duplicate-message behavior when applicable.

Do not change a firmware payload or MQTT topic implicitly. Keep existing ESP
contracts compatible until a coordinated firmware rollout is approved.

## 3. Implement in layers

Preferred order:

```text
Migration/index (only if required)
  → model validation/association
  → service/use case
  → controller or job
  → route and API contract
  → view/JavaScript/SCSS
  → tests, Swagger and docs
```

- Keep controllers as transport/orchestration only.
- Put multi-step device/MQTT behavior in a service.
- Keep events append-only and limit history queries.
- Use the authenticated user to authorize devices server-side.
- Keep secrets out of payloads, source code, logs and docs.

## 4. Device-specific workflow

### Adding a device type

1. Decide the `device_type`, configuration shape and ownership behavior.
2. Update creation/rake workflow and relevant registration documentation.
3. Add the device detail partial in `app/views/devices/`.
4. Add scoped SCSS and Turbo-safe JavaScript when needed.
5. Add model/request/view specs and empty/error states.

### PIR trigger changes

1. Remember: request `chip_id` is the source PIR.
2. Store `motion_detected` on the PIR.
3. Read target relay/Buzzer command from `PIR.trigger`.
4. Preserve `switch_value` and `longlast` for existing relay firmware.
5. Store non-secret target metadata in the event payload when dashboard history
   needs to group events by Buzzer target.

### Device pairing

1. User starts a pairing request while authenticated.
2. Rails creates a short-lived, one-time pairing code and stores only its digest.
3. ESP receives the code in its Wi-Fi captive portal and sends its own chip ID
   plus the code after Wi-Fi connects.
4. Rails validates expiry, use count and ownership, then links device to user.
5. ESP erases the pending code after success; failed requests retry safely.

## 5. Test before handoff

Run the narrowest relevant checks first:

```text
bundle exec rspec path/to/focused_spec.rb
bundle exec rails routes | rg 'relevant_route'
bundle exec rake rswag:specs:swaggerize    # when public API changed
yarn build                                 # when JavaScript changed
yarn build:css                             # when SCSS changed
git diff --check
```

Use mocks for MQTT/HTTP in tests. Never let tests publish to a real broker or
depend on a production database.

Minimum coverage for a device/API change:

- Valid request and happy path.
- Unknown/missing device.
- Unauthorized or inaccessible device.
- Invalid JSON/parameters.
- Retry/duplicate behavior where a device can resend.
- UI empty state and visible success/error state when a screen changes.

## 6. Keep API documentation current

When a public API changes:

1. Add/update an Rswag request spec under `spec/requests/api/`.
2. Describe authentication, parameters, success and error responses.
3. Generate `swagger/v1/swagger.yaml` from the full Swagger spec set.
4. Open `/api-docs` and verify the endpoint remains discoverable.

Do not generate OpenAPI from only one spec file if it would replace unrelated
paths in the shared document.

## 7. Release workflow

For frontend changes, follow `docs/RELEASE_PRODUCTION.md` exactly. The minimum
asset sequence is:

```text
yarn build
yarn build:css
bundle exec rails assets:precompile
```

After release, hard refresh the browser and verify the new fingerprinted assets,
JavaScript console, target device UI and relevant Sidekiq/MQTT logs.

For migrations:

1. Review MySQL compatibility and indexes.
2. Confirm existing records can satisfy new constraints.
3. Run the migration during the approved release.
4. Verify application behavior and rollback procedure.

## 8. Handoff format

Every completed task should state:

- Outcome and affected user/device behavior.
- Files changed.
- Tests/builds actually run and their result.
- Documentation/Swagger updates.
- Required release steps, including assets or migrations.
- Known limitations or follow-up work.

Never state that an MQTT command reached hardware, an asset is deployed, or a
production migration completed unless it was verified in that environment.
