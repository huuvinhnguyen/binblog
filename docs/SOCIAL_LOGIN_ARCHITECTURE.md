# Social Login Architecture

## Architecture Decision: Provider-neutral Social Login

**Status:** Architecture proposal ready for review

**Scope:** Rails web/API, native Swift, and Flutter clients

**Document ownership:** Binblog owns this canonical cross-platform Social Login architecture because it owns user identities, provider verification, account resolution, JWT issuance, Devise sessions, and link/unlink security. KVX Swift and Flutter implement the client portions of this backend contract.

**Providers:** Google first, Apple second, Facebook discovery only pending current official-flow verification

This document records the approved architecture decisions for adding social authentication to Binblog and KVX. It separates those decisions from implementation-time verification, which is listed at the end. It does not select provider SDK versions or add implementation details that depend on unverified provider flows.

## Context

Binblog already has Devise-backed web authentication, a username/password JSON login endpoint that issues a JWT, and device APIs that accept that JWT as a Bearer token. The Swift client has interactive username/password login and stores the Binblog JWT in `UserDefaults`. Flutter currently reads build-time credentials, logs in automatically through the shared datasource, and keeps the JWT in memory. Neither client has a real logout flow or a single app-wide authentication state.

Social login must resolve to the existing Binblog `User`, preserve device ownership and authorization, and continue using the existing JWT authorization boundary. Provider identity must be distinct from email, and matching an existing email must not silently merge accounts.

## Constraints

- Rails remains the authority for verifying provider credentials and resolving Binblog users.
- Provider credentials are exchanged for the normal Binblog JWT; provider credentials are not used to call device APIs.
- Existing password login, web Devise login, and device/PIR/Buzzer Bearer authorization remain supported.
- Provider email is contact and signup data, never the durable identity key.
- Account linking and unlinking require an authenticated Binblog user and careful handling of uncertain writes.
- SwiftUI and Flutter UI may differ while preserving the same authentication outcomes.

## APPROVED ARCHITECTURE DECISIONS

### 1. Identity model

Use a provider-neutral `UserIdentity` model conceptually related as:

```text
User has_many UserIdentities

UserIdentity
  user_id
  provider
  provider_uid
  last_authenticated_at
  timestamps
```

The initial database constraints are:

- Unique `(provider, provider_uid)` so one provider identity belongs to at most one Binblog user.
- Unique `(user_id, provider)` so one Binblog user links at most one identity for each provider.

Do not store provider access tokens, refresh tokens, or ID tokens unless a future, explicitly approved feature requires them. Never use provider email as the identity key.

### 2. Account resolution

Sign In and Link use separate account-resolution algorithms. They may share provider credential verification, a normalized verified identity representation, and low-level identity lookup, but must not share a resolver that can turn an authenticated Link into Sign In.

**Sign In**

1. Verify the provider credential server-side and derive `(provider, provider_uid)` and verified contact claims from it.
2. Look up `UserIdentity` by `(provider, provider_uid)`. If found, authenticate that identity's associated Binblog user and issue the normal Binblog session/JWT.
3. If not found, continue through the signup and verified-email conflict policy below. Do not automatically link by email.

**Link Provider**

1. Require User A to be authenticated before starting the link operation. Verify the new provider credential server-side and derive the normalized identity.
2. Look up the provider identity. If it is unowned, link it to authenticated User A, subject to uniqueness and other policy. If already owned by User A, return the endpoint's safe already-linked/idempotent result. If owned by User B, reject with a generic conflict that reveals no User B information.
3. Preserve User A as the authenticated principal throughout. A Link operation never authenticates User B, switches to User B, or issues User B's JWT/session.

The unique database constraints and transaction handling must protect concurrent claims. A provider identity already owned by another user cannot be reassigned through Link.

### 3. Email and local authentication policy

Initial social signup requires a usable verified contact email. If the provider cannot supply one, require a separate email entry and verification step before creating the Binblog account. Do not automatically replace `users.email` when a linked provider later reports a changed address.

Apple Hide My Email/private relay addresses are valid provider-verified contact addresses when returned by Apple. They remain contact data, not identity keys; users must be told that this address may relay mail and may differ from their usual address.

The system must reliably determine whether a user still has a usable local/password authentication method. Do not mandate a `has_local_password` boolean now. Backend Foundation must examine Devise password, reset, and existing-user lifecycle behavior and choose a representation. Unlink must never leave a user with zero usable authentication methods.

### 4. Provider trust boundary

Clients obtain provider credentials. Rails verifies provider credentials and derives provider, subject/UID, and verified contact data from the verified credential. Rails must not trust client-supplied email, provider UID, or a `verified` flag.

Verification must cover signature/JWKS, issuer, audience/client ID, expiry, subject, nonce/state where applicable, and replay protection. Google is the first provider. Apple follows. Facebook remains discovery/optional until the current official credential flow is verified.

### 5. Session contract

Preserve the existing contract:

```http
POST /api/login
Content-Type: application/json

{"username":"…","password":"…"}
```

Existing successful responses contain `status`, `token`, and `user`; invalid credentials return HTTP 401. Preserve existing Rails Web Devise login.

The proposed mobile provider exchange is:

```http
POST /api/auth/social_sessions
Content-Type: application/json

{"provider":"google","credential":"<provider credential>"}
```

Success returns HTTP 200 and the normal Binblog session identity:

```json
{
  "status": "success",
  "token": "<Binblog JWT>",
  "user": { "id": 123, "username": "…", "email": "…" }
}
```

The exact credential field and provider-specific verification contract must be finalized per provider during implementation. Do not accept client identity claims in place of a verifiable credential. Account-link-required, invalid credential, rejected identity conflict, and provider/network failures need stable, non-sensitive error outcomes. Existing device/PIR/Buzzer APIs continue to receive `Authorization: Bearer <Binblog JWT>`.

Web Social Login uses a provider callback, the common identity-resolution service, and Devise `sign_in`/session handling. Do not use a CSRF-bypassing mobile endpoint to manufacture a Web session. The API login endpoint currently skips authenticity-token verification; that existing behavior is not a precedent for weakening web callback protections.

The current Rails password endpoint signs an HS256 JWT containing `user_id` and a seven-day expiry. A social session must have compatible authorization semantics. Prefer a shared issuance path so password and social login do not drift in token claims, signing, expiry, or response shape.

### 6. Link and unlink

Linking requires an authenticated Binblog user, appropriate recent authentication or re-authentication, and a newly verified provider credential. Unlinking requires re-authentication and must be rejected if it removes the final usable authentication method. Identity-management endpoints must not reveal another user's identity information.

If a client loses the response after a link/unlink mutation, it must not blindly replay the write. Reconcile authoritative identity/session state or restart the provider flow as appropriate. Consumed authorization codes and nonces must not be reused automatically.

### 7. Cross-platform semantics

Web, Swift, and Flutter must agree on outcomes for returning social login, first signup, account-link-required, explicit linking, unlink, cancellation, provider error, Rails error, loading, duplicate submission, privacy, logout, and expired session. Presentation and navigation may be platform-specific.

## Approach

Rails owns identity resolution and session issuance. A shared identity-resolution service is used by the mobile exchange endpoint and the web provider callback, while transport-specific controllers handle API JSON versus Devise web sessions. Mobile auth components own provider SDK interaction and pass provider credentials to an auth repository/client. Device and feature repositories continue to send only the Binblog JWT and do not know which provider issued the identity.

### Layer changes

- **Rails domain/data:** Add provider-neutral identity persistence with database uniqueness constraints; implement transactional identity resolution; determine a reliable local-password-method representation; centralize compatible Binblog JWT issuance.
- **Rails application:** Define sign-in, signup, link, and unlink operations as distinct use cases/services with explicit results and authorization rules.
- **Rails transport:** Add a mobile social-session API action and web provider callbacks that call the common service. Preserve `/api/login`, Devise web login, and existing API JWT authentication.
- **Swift domain/application:** Add auth session/state and auth repository/use-case contracts independent of SwiftUI and provider SDKs.
- **Swift data/platform:** Add an auth repository for password and provider credential exchange, a token/session store behind an interface, and provider SDK adapters behind an auth component. Reuse the resulting Binblog JWT for Device/Buzzer/PIR clients. Assess migration from `UserDefaults` to Keychain during implementation; keep token access behind an abstraction.
- **Swift presentation:** Keep password login available; add social sign-in, linking, unlinking, logout, and consistent loading/cancellation/error states driven by shared auth state.
- **Flutter domain/application:** Add equivalent auth session/state, repository contracts, and auth operations.
- **Flutter data/platform:** Add provider adapters and a Rails auth repository. Introduce an explicit token/session store behind an interface; select and review secure persistence during implementation. Retire automatic build-time credential login from ordinary app behavior, while allowing it temporarily as an explicit compatibility/development mode.
- **Flutter presentation:** Add interactive auth UI and shared state consumed by device, PIR, and Buzzer features. A logout, account switch, or expired social session must not trigger automatic configured-credential login.

### Existing client behavior to preserve during migration

- Swift username/password login remains supported and writes a Binblog JWT readable by all existing Bearer clients.
- Flutter's configured username/password mode may remain temporarily, but must be explicit and must not silently override logout, an expired social session, or account switching.
- Existing device ownership and admin access behavior remain unchanged; a social session resolves to the same `User` and therefore the same authorization rules.
- Existing device/PIR/Buzzer requests retain their Bearer JWT contract and mutation retry safeguards.
- A Rails response with extra `status` and `user` fields remains compatible with current clients that extract `token`; current clients do not yet call `/api/auth/social_sessions`.

## Alternatives Considered

- **Use provider email as the account key:** Rejected because email can change, be private-relay, or collide with an existing account. It would also encourage unsafe implicit account linking.
- **Store provider tokens and call provider APIs from Binblog:** Rejected for the initial feature because the required product behavior is authentication; long-lived provider token storage adds risk and is unnecessary for issuing the Binblog session.
- **Use a separate authorization scheme for social users:** Rejected because existing device APIs and ownership checks are already based on the Binblog `User` and JWT.
- **Implement provider SDK calls inside device repositories:** Rejected because provider authentication is an auth/session concern and would couple unrelated feature data access to SDKs.
- **Replace password login during rollout:** Rejected because current web and mobile users rely on it and rollout must preserve it.

## Decision Rationale

The provider-neutral identity model permits adding providers without changing the account key. Explicit account-linking avoids account takeover through email matching. Server-side verification keeps user identity claims inside the trust boundary. Issuing the normal Binblog JWT preserves existing authorization and device ownership. Shared client auth state corrects current feature-local and automatic-login behavior without requiring device feature rewrites.

## Rollout and Implementation Task Decomposition

Recommended dependency sequence:

```text
Backend Identity Foundation
  establishes UserIdentity invariants, usable-local-auth determination,
  social-signup username policy, and stable identity/account-resolution boundaries
        ↓
Google Backend
  establishes stable API success and conflict contracts
        ↓
Google Web / Google Swift / Google Flutter integrations
```

Swift and Flutter Auth Session Foundations may proceed independently where work does not rely on an unfinished provider contract. Provider integrations must depend on the stable Google Backend contract.

1. **Backend Identity Foundation** — inspect Devise lifecycle and user data; design `UserIdentity` and constraints; determine usable local/password authentication; define stable identity/account-resolution service boundaries; and settle how social signup generates or collects a username, enforces its required presence, handles uniqueness/collisions deterministically (including retry behavior if generated), and tests assignment/collisions. Dependency: none. This task must complete these items before Google Backend implements signup behavior.
2. **Google Backend** — verify Google credential flow, add API exchange and web callback using the foundation, and cover account resolution. Publish the stable API success/conflict contract before dependent Web, Swift, or Flutter Google integration. Dependency: Backend Identity Foundation.
3. **Swift Auth Session Foundation** — introduce shared state, token/session store, password-login integration, logout/expiry/account-change behavior, and feature integration. May proceed independently of provider contracts; Google Swift depends on this task.
4. **Flutter Auth Session Foundation** — introduce shared state, store, explicit legacy credentials mode, logout/expiry/account-change behavior, and feature integration. May proceed independently of provider contracts; Google Flutter depends on this task.
5. **Google Web** — add provider UI and callback using the stable Google Backend contract. Dependency: Google Backend.
6. **Google Swift** — add provider adapter/UI and social exchange using the stable Google Backend contract and Swift Auth Session Foundation. Dependency: both.
7. **Google Flutter** — add provider adapter/UI and social exchange using the stable Google Backend contract and Flutter Auth Session Foundation. Dependency: both.
8. **Apple Backend** — add Apple verification and signup/email edge cases using Backend Identity Foundation. Dependency: foundation; can follow Google behavior.
9. **Apple Swift** — add Apple adapter/UI and shared session integration. Dependency: Apple Backend and Swift Auth Session Foundation.
10. **Apple Web/Flutter if required** — add Apple callback and/or client flow only for supported product surfaces. Dependencies: Apple Backend and the relevant client foundation.
11. **Facebook Discovery** — verify current official Meta credential requirements, supported clients, server validation, and policy constraints; propose a separate implementation task only if the flow is supportable. Dependency: discovery outcome.

Provider/client feature flags may control rollout. Preserve password authentication throughout. Do not create these implementation tasks as part of this architecture document.

## Testing Strategy

### Backend

- Test provider credential validation using fakes, fixtures, or local test keys; never call real production provider accounts.
- Test User A attempting to link an identity owned by User B: reject the request, leave identity ownership unchanged, keep User A authenticated, issue no User B JWT/session, and disclose no User B information.
- Test identity already linked to User A returns a safe/idempotent result without changing the principal.
- Test concurrent claims of an unused provider identity: database uniqueness and transaction handling leave exactly one owner.
- Test returning identity login, transactional signup, verified-email conflict requiring explicit linking, provider UID already owned, missing/unverified email, Apple private relay handling, invalid signature, wrong issuer/audience, expired credential, nonce/state mismatch, and replay rejection.
- Test uniqueness under concurrent link/signup attempts and ensure failed transactions create no partial user or identity.
- Test social-signup username collection/generation satisfies presence and uniqueness constraints, including deterministic collision handling or retry behavior when generation collides.
- Test link/unlink authorization, re-authentication, no cross-user identity disclosure, and refusal to remove the final usable auth method.
- Regress `/api/login`, Devise web login, JWT claims/expiry, Bearer authorization, user/device ownership, and admin access.

### Swift and Flutter

- Test password login and social exchange through fake HTTP/provider adapters; no real production accounts.
- Test shared state transitions for signed out, loading, authenticated user, account switch, logout, expired session, cancellation, duplicate submission, provider failure, Rails failure, and account-link-required.
- Test token storage and clearing, startup restoration if supported, and that all Device/PIR/Buzzer requests use the Binblog JWT.
- Regress existing password login, device list ownership, 401 data clearing, and no blind replay of link/unlink mutations.
- Test Flutter legacy credentials mode is explicit and cannot silently undo logout, social expiry, or account switching.

## IMPLEMENTATION-TIME VERIFICATION REQUIRED

The following are not fixed by this architecture decision and must be checked during implementation:

- Current official Google, Apple, and Meta provider SDK/API credential flows and platform requirements.
- Provider client IDs, audiences, redirect/callback configuration, key/JWKS rotation behavior, and production app registration.
- The exact Google/Apple token or authorization-code contract per client and provider, including nonce/state and replay controls.
- Facebook supportability and current official credential verification; implementation remains optional until discovery concludes.
- The safest representation of a usable local/password authentication method after examining Devise password/reset behavior and real account data.
- How social signup will satisfy the current required, unique `users.username` constraint without collisions; verify any username prompt or assignment policy alongside the email/user-data audit.
- Production user-data audit: duplicate/missing emails, usernames, password state, and any account migration or communication needs.
- Whether Swift JWT persistence should move from `UserDefaults` to Keychain and which secure store Flutter should use; no storage package is selected here.
- Exact stable API error codes and whether a dedicated authenticated link/unlink API surface is needed alongside web account management.
- Existing Rails API session/controller behavior is based on the current local checkout and should be rechecked before coding if that repository has changed.

## Acceptance Criteria

- The identity model is provider-neutral and has the documented uniqueness constraints.
- Social login never links by email alone and never trusts unverified client identity claims.
- Password login and web Devise login remain available.
- Social sessions resolve to the same Binblog user model and normal JWT authorization used by existing device APIs.
- Link is bound to its authenticated principal and cannot switch accounts; unlink requires appropriate re-authentication and preserves a usable authentication method.
- Backend Identity Foundation settles social-signup username assignment/collision behavior before Google signup work.
- Swift and Flutter share consistent auth outcomes while keeping provider integration out of device repositories.
- Rollout and task dependencies are documented; provider/version/data questions remain explicit for implementation-time verification.
