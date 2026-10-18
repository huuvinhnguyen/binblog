# PR #118 conflict resolution

Integrate main `16c5947c55c1e5c0b71e952e2fd3cda38125ed57` into
feature/backend-social-login `68daae2a7c234f7cc308750413f718a28e9369ac`.
Scope is merge conflict resolution only; do not deploy, migrate production,
publish MQTT or merge the PR into main.

## Resolution

The only textual conflict is the schema version. Keep the newer migration
version `2026_10_04_090200`, preserving auth tables/foreign keys and PIR tables,
foreign keys and devices_users indexes. Routes, JavaScript imports and OpenAPI
merge automatically; verify both sets of additions survive. Remove one
incoming trailing-whitespace line in devices_controller.rb. No API contract,
authentication policy, migration or service implementation is redesigned.

## Verification

- EXECUTED / PASSED: compare changed schema table definitions against both
  parents/common base, preserve the union of foreign keys/tables, and confirm
  schema version matches the newest migration filename.
- EXECUTED / PASSED: strict YAML parsing (duplicate keys rejected) and compare
  changed OpenAPI paths/methods/components against both parents/common base.
- EXECUTED / PASSED: Ruby tree-sitter syntax parsing, 270 application/config/
  migration/spec files. This is not Ruby execution or Rails boot.
- EXECUTED / PASSED: JavaScript syntax checks for application.js, google_auth.js
  and pir_trigger_actions.js; npm run build; npm run build:css.
  Sass reports existing dependency deprecation warnings. Generated assets and
  node_modules are excluded from the commit; package/lock files are unchanged.
- EXECUTED / PASSED: git diff whitespace checks and unresolved-marker checks.
- EXECUTED / FAILED (environment): Node PIR browser test initially lacked sass;
  after installing existing npm dependencies, it could not launch the configured
  macOS Chrome binary (ENOENT). No browser behavior PASS is claimed.
- NOT RUN: RSpec, Rails routes, full Rswag regeneration, schema load/migrations
  and precompile. This host has no Ruby/Bundler runtime.
- NOT TESTED: production, real Google login, mail, database and physical devices.

Run relevant auth/PIR request/service/model specs, Rails route/schema checks,
full Rswag generation and browser verification in a configured environment
before merge/release. This mechanical resolution has self-check evidence;
independent Reviewer/Final Verifier approval is not claimed.
