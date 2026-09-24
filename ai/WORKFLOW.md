# Binblog Engineering Workflow

## Goal

Use this workflow for all feature work, bug fixes, documentation changes,
refactors, and operational changes.

The goal is to keep Rails, device firmware, MQTT, data, APIs, Web UI,
mobile clients, tests, documentation, and release steps aligned.

Core principles:

- One logical task = one dedicated branch.
- Define the contract before implementation.
- Preserve existing production behavior unless the task explicitly changes it.
- Keep controllers thin and business logic testable.
- Treat authentication, authorization, MQTT, and device ownership as security
  boundaries.
- Review before commit.
- Verify before push.
- Verify the pushed diff before creating a PR.
- Never claim hardware or production behavior that was not actually verified.


# 1. Start With the Boundary

Before editing code:

1. Follow the Branch Strategy defined in this document.
2. Read:
   - `ai/PROJECT.md`
   - `ai/CONVENTIONS.md`
   - the relevant section of `ai/ARCHITECTURE.md`
   - the relevant agent definition under `ai/agents/`
3. Read the task/issue and its acceptance criteria.
4. Inspect the current implementation relevant to the task:
   - routes
   - controllers
   - models
   - services
   - jobs
   - views
   - JavaScript
   - SCSS
   - migrations
   - request specs
   - service specs
   - Swagger/Rswag specs
   - relevant documentation
5. Identify whether the task changes:
   - browser behavior
   - public API
   - device firmware
   - MQTT topics/payloads
   - database schema
   - background jobs
   - authentication/authorization
   - Web/mobile contract
   - deployment behavior
6. For cross-cutting IoT or architecture changes, create or update a short
   decision record under `docs/` before implementation when appropriate.

Do not start implementation until the current behavior and task boundary are
understood.


# 2. Branch Strategy

Every implementation task MUST use a dedicated branch.

Never implement feature work, bug fixes, refactors, or documentation tasks
directly on `main`.

## Starting a New Task

Before starting:

1. Ensure the previous task/PR has been completed, or its current state is
   explicitly understood.
2. Check the working tree.
3. Checkout the intended base branch, normally `main`.
4. Pull the latest remote changes.
5. Verify the working tree is clean.
6. Create a dedicated branch for the task.
7. Verify the current branch.
8. Only then modify files.

Example:

```bash
git status

git checkout main
git pull origin main

git status

git checkout -b feature/<task-name>

git branch --show-current
git status
```

Expected state before implementation:

```text
On branch feature/<task-name>
nothing to commit, working tree clean
```

## Branch Naming

Prefer:

```text
feature/<task-name>
fix/<task-name>
docs/<task-name>
refactor/<task-name>
chore/<task-name>
```

Examples:

```text
feature/pir-buzzer-linking
feature/web-pir-buzzer-linking
fix/buzzer-cooldown
docs/buzzer-swagger-api
refactor/device-trigger-service
```

## Branch Rules

- NEVER implement a new task directly on `main`.
- NEVER reuse a branch from a previous completed task.
- One branch should represent one logical task or issue.
- Do not mix unrelated changes into the task branch.
- Verify the branch name before modifying files.
- Do not merge unrelated cleanup into a feature merely because it was
  discovered while working on the feature.
- Commit and push only after review/final verification unless explicitly
  instructed otherwise.

## Dirty Working Tree Safety

If the working tree contains unrelated uncommitted changes:

STOP before creating or switching branches.

Report:

- current branch
- modified files
- untracked files
- whether the changes appear related to the current task

Do NOT automatically:

- discard changes
- reset changes
- stash changes
- commit changes
- move changes to another branch
- carry them into the new task

without explicit approval.

Protect existing work first.


# 3. Define the Contract First

For any IoT/API feature, determine and document the contract before
implementation.

At minimum decide:

- source device identity
- target device identity
- ownership rules
- authorization rules
- HTTP method
- endpoint
- request shape
- response shape
- error responses
- nullable fields
- MQTT topic
- MQTT payload
- timeout/retry behavior
- acknowledgement semantics
- event owner
- event type
- event payload metadata
- timestamp/time-zone semantics
- loading state
- empty state
- error state
- idempotency
- cooldown behavior
- duplicate-message behavior
- cross-platform behavior where applicable

Do not change firmware payloads or MQTT topics implicitly.

Keep existing ESP/device contracts compatible until a coordinated firmware
rollout is explicitly approved.

The production implementation is the source of truth when documentation and
implementation disagree.

Do not silently change production behavior merely to make documentation or
tests easier to satisfy.


# 4. Architecture and Implementation Order

Preferred implementation order:

```text
Migration/index (only when required)
        ↓
Model validation/association
        ↓
Service / use case
        ↓
Controller / job
        ↓
Route / API contract
        ↓
Web UI / JavaScript / SCSS
        ↓
Tests
        ↓
Swagger / documentation
```

This is a guideline, not a reason to introduce unnecessary layers.

## General Architecture Rules

- Keep controllers focused on transport and orchestration.
- Put multi-step business/device/MQTT behavior in services.
- Prefer small Rails-native abstractions.
- Avoid introducing architecture that the feature does not need.
- Keep events append-only where practical.
- Limit history queries.
- Use authenticated-user scope for device authorization.
- Never trust a client-provided device/user ID without authorization.
- Keep secrets out of payloads, source code, logs, fixtures, screenshots,
  and documentation.
- Preserve backward compatibility unless breaking behavior is explicitly
  approved.


# 5. Device-Specific Workflow

## Adding a Device Type

1. Decide the `device_type`.
2. Define configuration shape.
3. Define ownership/access behavior.
4. Update creation/registration workflow.
5. Update relevant registration documentation.
6. Add the device detail UI under `app/views/devices/`.
7. Add scoped SCSS and Turbo-safe JavaScript where needed.
8. Add model/request/view specs.
9. Add loading/empty/error states where applicable.
10. Verify behavior with other device types.


## PIR Trigger Changes

Remember:

1. Request `chip_id` identifies the source PIR.
2. `motion_detected` belongs to the PIR.
3. Target relay/Buzzer command configuration is read from `PIR.trigger`.
4. Preserve the existing trigger contract required by the target
   device/runtime.
5. Do not add or remove command fields such as `switch_value` unless the
   production runtime and firmware contract require them.
6. Preserve `longlast`, relay information, or other command fields when they
   are part of the actual target contract.
7. Store only non-secret target metadata in event payloads when dashboard
   history needs to group events by target.
8. Do not claim that MQTT publication means the physical device executed the
   command unless an actual device acknowledgement exists.


## PIR ↔ Buzzer Configuration

Current phase-one architecture:

```text
PIR
  ↓
Device#trigger
  ↓
target Buzzer chip_id
+ relay_index
+ longlast
```

Unless a future architecture decision explicitly replaces this:

- `Device#trigger` remains the source of truth.
- One PIR targets at most one Buzzer.
- One Buzzer may be targeted by many PIRs.
- Link/relink/unlink are configuration operations.
- Configuration operations MUST NOT publish MQTT.
- Configuration operations MUST NOT invoke Test Buzzer.
- Relinking replaces the current target configuration.
- Unlinking must not remove a configuration belonging to another Buzzer.
- Existing runtime/firmware compatibility must be preserved.


## Device Pairing

1. User starts a pairing request while authenticated.
2. Rails creates a short-lived, one-time pairing code.
3. Store only the pairing-code digest server-side.
4. ESP receives the code through its Wi-Fi captive portal.
5. ESP sends its own chip ID plus the pairing code after Wi-Fi connects.
6. Rails validates:
   - expiry
   - use count
   - ownership
   - device identity
7. Rails links the device to the authenticated user.
8. ESP erases the pending code after success.
9. Failed requests must retry safely.


# 6. Web and Cross-Platform Features

When a feature exists on Web, Swift, and Flutter, define shared product
semantics before implementing platform-specific UI.

The clients do NOT need identical internal architecture or pixel-identical UI.

They SHOULD expose equivalent user-facing semantics for:

- available actions
- terminology
- validation
- loading
- success
- empty states
- authentication failure
- authorization failure
- not found
- service errors
- retry
- confirmations
- destructive actions
- cooldown
- post-mutation refresh
- privacy behavior

Platform-native presentation is encouraged.

Example:

```text
Web       → modal/dialog
SwiftUI   → sheet/confirmationDialog
Flutter   → dialog/bottom sheet
```

The behavior and resulting state should remain equivalent.

When backend contract is still being developed:

```text
Backend contract
      ↓
Backend review + merge
      ↓
Web/mobile implementation
```

Do not build multiple clients against guessed endpoints when the backend
contract can be stabilized first.


# 7. Test Before Handoff

Run the narrowest relevant checks first.

Examples:

```bash
bundle exec rspec path/to/focused_spec.rb

bundle exec rails routes | rg 'relevant_route'

bundle exec rake rswag:specs:swaggerize

yarn build

yarn build:css

git diff --check
```

Use mocks/stubs for MQTT and external HTTP calls.

Tests MUST NOT:

- publish to a real MQTT broker
- depend on production databases
- mutate production services
- require physical hardware unless explicitly running an integration test

## Minimum Device/API Coverage

Where applicable test:

- valid request
- happy path
- missing device
- unknown device
- unauthorized device
- inaccessible device
- wrong device type
- invalid JSON
- invalid parameters
- nullable values
- malformed stored configuration
- retry behavior
- duplicate behavior
- idempotency
- cooldown
- concurrent/stale requests where relevant
- no unintended MQTT side effects
- existing runtime compatibility

## UI Coverage

When a screen changes, cover relevant:

- loading state
- empty state
- success state
- error state
- validation state
- confirmation behavior
- retry behavior
- authentication/login behavior
- post-mutation refresh
- regression of existing actions

Prefer behavior tests over implementation-detail tests.


# 8. Keep API Documentation Current

When a public API changes:

1. Add/update an Rswag request spec under:

   `spec/requests/api/`

2. Document:
   - authentication
   - authorization-relevant behavior
   - path parameters
   - query parameters
   - request body
   - success responses
   - validation errors
   - authentication errors
   - not-found behavior
   - nullable fields
   - arrays/nested objects

3. Generate:

```bash
bundle exec rake rswag:specs:swaggerize
```

4. Inspect:

```text
swagger/v1/swagger.yaml
```

5. Verify existing unrelated paths were not removed or changed unexpectedly.

6. Open `/api-docs` when appropriate and verify the endpoint is discoverable.

Do not generate OpenAPI from only one spec file if that would replace unrelated
paths in the shared document.

Swagger must describe actual production behavior.

Do not invent fields, acknowledgements, or guarantees that the backend does
not provide.


# 9. Developer Handoff

The default Developer workflow is:

```text
Implement
   ↓
Run focused tests
   ↓
Inspect diff
   ↓
Report
   ↓
STOP
```

Unless explicitly instructed otherwise, the Developer MUST NOT:

- commit
- push
- create a pull request
- merge

The Developer handoff must include:

- architecture/contract confirmation
- changed files
- implemented behavior
- tests actually run
- test results
- Swagger/docs changes
- known unrelated failures
- remaining risks
- `git diff --check` result
- current branch
- working-tree state


# 10. Review Workflow

After Developer handoff:

```text
Developer implementation
        ↓
Reviewer
        ↓
Fix pass (only if required)
        ↓
Final verification
```

The Reviewer should inspect actual code and tests.

Do not rely solely on the Developer's implementation report.

Review:

- `git status`
- current branch
- diff against intended base
- changed files
- architecture
- authorization
- security/privacy
- business logic
- side effects
- tests
- Swagger/docs
- regressions
- scope

## Review Findings

Classify findings as:

### BLOCKER

A confirmed issue that must be fixed before commit/PR.

Examples:

- authorization bypass
- data loss
- incorrect API contract
- unintended MQTT command
- broken runtime compatibility
- destructive cross-device behavior
- test proving a required behavior is broken

### IMPORTANT

A worthwhile improvement that does not prevent the task from safely
progressing.

Examples:

- additional defensive validation
- documentation clarity
- missing non-critical test
- maintainability improvement

Do not classify speculative issues as blockers without evidence.


# 11. Conflicting AI Reviews

AI review findings are not automatically facts.

If reviewers disagree about a blocker:

1. Do not immediately modify production code.
2. Identify the exact disputed behavior.
3. Trace the executable call path.
4. Inspect the actual implementation.
5. Inspect existing tests.
6. Add/run a focused verification when needed.
7. Reproduce the concrete failure scenario.
8. Classify the finding as:
   - verified bug
   - false positive
   - unresolved

Prefer executable-code and test evidence over reviewer assertions.

Do not introduce production abstractions solely to satisfy an incorrect review
finding.

A false-positive review should be documented as resolved and should not block
the task unless new evidence appears.


# 12. Fix Pass

If the Reviewer finds confirmed blockers:

1. Return the task to the Developer.
2. Fix only confirmed findings.
3. Avoid unrelated refactors.
4. Add regression tests for the bug where appropriate.
5. Run focused tests again.
6. Review the resulting diff.
7. Repeat review when necessary.

Do not fix unrelated technical debt merely because it was discovered during
the task.

Create a separate task when appropriate.


# 13. Final Verification

Final verification happens BEFORE the checkpoint commit.

It must not modify production files.

Verify:

- correct branch
- expected changed files only
- `git diff --check`
- focused tests
- relevant regression tests
- route/API contract
- authorization/security
- required side-effect guarantees
- Swagger/OpenAPI where applicable
- runtime compatibility
- cross-platform contract where applicable
- known unrelated failures remain unrelated

Final verification should end with an explicit result such as:

```text
FINAL VERIFICATION PASSED — READY TO COMMIT
```

or:

```text
FINAL VERIFICATION FAILED — FIX REQUIRED
```


# 14. Commit and Push

Commit only after final verification passes unless explicitly instructed
otherwise.

Before commit:

```bash
git status
git diff --stat
git diff --check
```

Stage only task-related files.

Then inspect:

```bash
git diff --cached --stat
git diff --cached --check
```

Use a focused commit message.

Examples:

```text
feat: add PIR Buzzer link management
feat: add PIR Buzzer linking web UI
fix: enforce Buzzer cooldown
docs: document Buzzer mobile API
```

Push the dedicated branch:

```bash
git push -u origin <branch>
```

Do not push unrelated local branches or commits.


# 15. GitHub Final Review

After push and before PR creation:

1. Compare the pushed branch against the intended base branch.
2. Verify:
   - expected commits only
   - expected files only
   - no unrelated changes
   - no accidental secrets
   - no accidental generated artifacts
   - contract matches reviewed implementation
3. Re-check security-sensitive behavior.
4. Confirm final verification results still correspond to the pushed commit.

Only then create the pull request.


# 16. Pull Request Workflow

The PR should include:

- task/issue reference
- concise summary
- API/behavior changes
- architecture decisions when relevant
- tests run
- known unrelated issues
- documentation/Swagger changes
- deployment considerations

Link the issue using:

```text
Closes #<issue>
```

when appropriate.

After PR creation:

1. Check mergeability.
2. Check CI/workflow status.
3. Check required reviews.
4. Check unresolved comments.
5. Do not merge while required checks are failing or pending.
6. Do not treat absence of CI as proof that tests passed; rely on the verified
   local test evidence as well.


# 17. Merge and Post-Merge Verification

After merge:

1. Confirm the PR merged into the intended base branch.
2. Confirm the related issue closed when expected.
3. Update local `main` before starting the next task:

```bash
git checkout main
git pull origin main
```

4. Perform the relevant smoke test.
5. Verify production/staging behavior when deployment is part of the task.
6. Only then begin the next dependent task.

Do not reuse the merged feature branch for new work.


# 18. Release Workflow

For frontend changes, follow:

`docs/RELEASE_PRODUCTION.md`

The minimum asset sequence is:

```bash
yarn build
yarn build:css
bundle exec rails assets:precompile
```

After release:

- hard refresh the browser
- verify fingerprinted assets
- inspect the JavaScript console
- verify the target device UI
- verify relevant Sidekiq/MQTT logs when applicable

Do not claim an asset is deployed until verified in that environment.


## Migrations

For migrations:

1. Review MySQL compatibility.
2. Review indexes.
3. Confirm existing records satisfy new constraints.
4. Define rollback behavior.
5. Run migration during the approved release.
6. Verify application behavior afterward.
7. Verify rollback procedure where appropriate.

Do not claim a production migration completed unless it was actually verified.


# 19. Hardware and MQTT Verification

Distinguish these states clearly:

```text
Rails accepted request
        ≠
MQTT publish succeeded
        ≠
broker acknowledged message
        ≠
physical device received command
        ≠
physical device executed command
```

Only claim the strongest state actually verified.

Tests using a mocked MQTT client prove application behavior, not physical
hardware behavior.

When physical-device verification is required, report it separately as a
hardware smoke/integration test.


# 20. Task Completion / Handoff Format

Every completed task should report:

## Outcome

What changed for the user/device.

## Branch

The branch used for the task.

## Files Changed

Task-related files only.

## Tests

Commands actually run and their results.

## API / Swagger

Public contract changes and generated documentation.

## Security / Authorization

Relevant ownership/access behavior.

## MQTT / Device Behavior

What was verified and at what level.

## Release Requirements

Assets, migrations, services, restart/deploy steps.

## Known Limitations

Anything intentionally left for follow-up.

## Follow-Up Tasks

Technical debt or related work that should not be mixed into the current
task.


# 21. End-to-End Workflow Summary

The default engineering workflow is:

```text
Task / Issue
    ↓
Architecture / Contract
    ↓
Sync base branch
    ↓
Verify clean working tree
    ↓
Create dedicated task branch
    ↓
Developer implementation
    ↓
Focused tests
    ↓
Developer handoff
    ↓
Reviewer
    ↓
Fix pass (if required)
    ↓
Final verification
    ↓
Commit
    ↓
Push
    ↓
GitHub final review
    ↓
Create PR
    ↓
CI / review / merge readiness
    ↓
Merge
    ↓
Post-merge smoke test
    ↓
Next dependent task
```

For dependent cross-platform work:

```text
Backend contract
      ↓
Backend implementation
      ↓
Backend review / verification
      ↓
Backend merge
      ↓
Web reference semantics
      ↓
Web review / merge
      ↓
Swift + Flutter
      ↓
Cross-platform parity verification
      ↓
End-to-end device smoke test
```

Never skip a boundary merely because an AI agent reports that implementation
is complete.