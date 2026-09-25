# Binblog Engineering Workflow

## Purpose and ownership

This is the canonical lifecycle for feature, fix, documentation and operational
tasks, for people and AI tools from any vendor. It defines delivery gates and
task transitions. Agent files define role-specific responsibilities;
`ai/CONVENTIONS.md` owns coding/repository conventions; `ai/ARCHITECTURE.md`
describes the system; `docs/RELEASE_PRODUCTION.md` owns production release
commands. Follow those documents instead of copying their detailed rules here.

Use judgment: trivial, low-risk work may combine roles and use a lighter review
path. Keep the safety gates that apply to the task.

## Task lifecycle

```text
Select task and reconcile tracker state
 → establish previous task state and clean task boundary
 → checkout/pull base, create and verify dedicated branch
 → architecture/contract pass when needed
 → implement → focused verification → independent review
 → fix confirmed findings → targeted re-verification
 → final verification: READY TO COMMIT
 → commit when authorized → READY TO PUSH → push when authorized
 → inspect remote branch → PR → required CI/review → merge
 → post-merge acceptance when required → reconcile tracker/GitHub/checklist
 → complete task → restart from updated base for the next task
```

Stop and clarify when scope, contract, authorization or a required acceptance
gate is materially unclear. Do not claim a gate passed without evidence.

## Task tracker state

Before work, identify the task ID and inspect its current state when tracker
access is available. Move it only to a valid existing active state. If the
tracker only has To Do and Complete, leave it open and record progress in an
available progress field or update; do not invent a state.

If tracker access is unavailable, do not claim the state was inspected or
changed. Report tracker reconciliation as pending and continue only when task
identity and scope are otherwise clear. If tracker state is necessary to
decide whether work may proceed, stop and ask. Reconcile later when authorized
tracker access or a human is available.

After merge, keep the task open while any stated acceptance gate remains, such
as production or deployment verification, migration verification, hardware or
device testing, or manual UI smoke testing. Mark it Complete only after its
acceptance criteria pass and the tracker was actually updated. If tracker
access is unavailable, report completion reconciliation as pending. Before
moving on, reconcile PR/GitHub state and task checklist/docs. Reconcile tracker
state when access is available; until then, report it as pending and proceed
only if tracker state is not required to decide whether the next task may start.
Record follow-up debt as separate work.

## Branch boundary

For every new implementation, documentation or fix task, complete or explicitly
reconcile the previous task first. Before switching away from the current
branch:

1. Inspect the current branch and run `git status`.
2. If the tree contains unexplained or unrelated changes, stop and understand
   them. Reconcile them only through an intentional, user-approved workflow;
   never stash or discard work automatically to satisfy this gate.
3. Once changes are deliberately reconciled, switch to the intended base branch
   (normally `main`) and pull its latest remote changes.
4. Verify the base branch worktree is clean.
5. Create a new dedicated task branch.
6. Verify the branch and clean state before editing.

Never start a new task on `main`, silently reuse a previous feature branch, or
inherit an unmerged branch unless this task explicitly depends on it. After a
merge, the next task starts from updated `main` by default.

```bash
git status --short --branch
# Stop and understand/reconcile any unexplained or unrelated changes first.
git switch main
git pull --ff-only origin main
# Continue only when the base branch worktree is clean.
git status --short
git switch -c docs/<task-name> # or feature/, fix/, refactor/, chore/
git branch --show-current
git status --short
```

## Architecture and implementation

Read `ai/PROJECT.md`, `ai/CONVENTIONS.md`, the relevant `ai/ARCHITECTURE.md`
sections, the task, and the appropriate role guide. Inspect executable code,
tests and relevant docs before deciding behavior. For meaningful boundary,
API/MQTT/data/device, concurrency, security or multi-component changes, agree
on architecture/contracts and dependencies before implementation. The
architect defines decisions and scope; the developer implements approved
scope. Do not require separate agents for trivial changes.

Preserve useful Binblog-specific rules in `ai/CONVENTIONS.md` and
`ai/ARCHITECTURE.md`: Rails and MySQL compatibility, MQTT/device contracts,
Swagger requirements, migration safety, asset release steps, and deployment
guidance. For API/device work, define source/target identity, auth, request and
response contracts, event ownership, retry/acknowledgement behavior, and UI
states as applicable. Do not change firmware contracts implicitly.

For Web + Swift + Flutter features, agree on shared semantics first: API,
validation, confirmation, privacy, loading/empty/error states, retry, uncertain
mutation handling, refresh and success. Prefer backend contract → Web reference
→ Swift/Flutter → cross-platform review when useful; this sequence is guidance,
not a requirement. Require semantic parity, not identical implementation.

For example, the recent Buzzer work used backend → Swagger → PIR/Buzzer
backend integration → Web → Swift/Flutter → review/fix/final verification →
PR/CI/merge → post-merge smoke test → task reconciliation. Reuse the order where
the dependencies fit; it is an example, not a mandatory platform sequence.

## Verification, review and fix pass

Run focused tests/builds during implementation. Have a reviewer independently
inspect the complete task diff, relevant contracts and test evidence. Review is
read-only. Classify findings by severity and separate confirmed defects from
hypotheses. A blocker/high finding needs a concrete code path, relevant
requirement and reproducible or logically demonstrated failure, supported by
source, tests or runtime evidence where possible.

When reviewers disagree, inspect executable code and tests, reproduce the
failure if practical, and compare it with the actual contract. Record the
outcome as **confirmed defect**, **false positive**, **unverified risk**, or
**unrelated existing issue**. Document false-positive resolution in the task or
review report. Fix confirmed findings only; avoid unrelated refactors and add
regression coverage for confirmed defects. Then run targeted re-verification.

Final Verification independently checks fixes and the complete diff, runs
required checks, distinguishes test execution from compile/build-only evidence,
and returns **READY TO COMMIT** when the commit gate passes. This is a readiness
result, not authority to commit. Commit and push only when the user/task
explicitly authorizes those actions or the established execution context clearly
grants that authority; an explicitly approved checkpoint workflow may authorize
them in advance. Without commit authority, stop at READY TO COMMIT, report the
next action, and wait. After an authorized commit, **READY TO PUSH** is likewise
readiness only; without push authority, stop, report the next action, and wait.

If staged and unstaged changes coexist, inspect the full
`HEAD`-to-working-tree delta (`git diff HEAD`), not only unstaged `git diff`.

### Test evidence

Reports label evidence precisely:

| Label | Meaning |
| --- | --- |
| `EXECUTED / PASSED` | The named test/check ran and passed. |
| `EXECUTED / FAILED` | It ran and failed; include the relevant result. |
| `COMPILED ONLY` | Compilation/build succeeded; behavior was not tested. |
| `NOT RUN` | The check was not run. |
| `MANUAL TESTED` | The named manual scenario was exercised in the stated environment. |
| `NOT TESTED` | The behavior/environment was not tested. |

Compilation, an existing test file, a related suite, or a simulator build alone
does not mean a behavior test passed. For async/state-machine behavior, test
observable transitions where practical (in-flight request, duplicate action,
completion, authoritative refresh, and recovery after refresh failure). For
HTTP/API changes, check method, path, authentication, body and bodyless requests,
response schema/nullability, and transport failures as applicable.

## Uncertain remote write outcomes

When a remote mutation may have succeeded but its response is lost, a timeout
or network failure does not prove the server rejected it. If duplicate writes
are unsafe, mark local state uncertain/non-authoritative, do not replay
automatically, block conflicting writes as needed, refresh authoritative server
state, and allow writes after reconciliation. Apply this to any remote system;
do not impose it on operations with explicitly safe idempotent retry semantics.

## Commit, remote review, PR and CI

Before a commit, inspect the full task diff (staged and unstaged), verify scope,
secrets/generated files, and actual required test execution. Run
`git diff --check` for unstaged changes. If any changes are staged, also run
`git diff --cached --check`; when nothing is staged, `git diff --check` covers
the task diff. Account for the complete change set before committing. A passed
final-verification gate means READY TO COMMIT; perform the
commit only with the authority described above. Then verify the commit and
report READY TO PUSH; push only with push authority. An explicitly approved
checkpoint may grant these actions in advance.

After push, compare the remote branch with its base and verify scope again.
Create a PR with a concise summary and actual verification evidence. Wait for
required CI and review gates; investigate failures and merge only when required
checks pass. Never report remote checks as passed until they completed.

## Post-merge and next task

Merge does not itself prove acceptance. Run required production, deployment,
migration, real UI/mobile, device/hardware or asset checks and label manual and
automated evidence separately. Then confirm PR/GitHub state, acceptance gates,
and checklist/docs; reconcile tracker state as described under Task tracker
state. Record follow-up debt separately and mark the task Complete only when
its gates pass and the tracker was actually updated.

Before the next task: confirm the current PR is merged/closed or reconciled and
confirm acceptance. Reconcile the current task and docs as described under Task
tracker state, then select the next task and establish its identity and scope.
Inspect and update its tracker state using valid existing states when access is
available. If access is unavailable, follow the pending-reconciliation path
above and proceed only when tracker state is not required for the go/no-go
decision. Then checkout updated base and pull; verify a clean tree; create and
verify a new dedicated branch. Reconcile pending tracker state later when access
is available. Never let the next task inherit the previous branch by accident.

## Capability selection

Choose the least expensive/capable reasoning level that can reliably do the
work; escalate when evidence shows it is insufficient. This is guidance, not a
quality gate, and does not prescribe vendor or model names.

| Level | Typical work |
| --- | --- |
| **Light** | Mechanical edits, tracker/branch/PR metadata, narrow tests, simple docs. |
| **Standard** | Normal features, focused fixes, test implementation, bounded final verification. |
| **Deep** | Architecture, concurrency/state machines, security-sensitive design, difficult cross-platform reasoning, conflicting findings. |

## Existing Binblog-specific release and API gates

- Public API changes require request specs, Rswag metadata and regeneration of
  `swagger/v1/swagger.yaml` from the full spec set; see `ai/CONVENTIONS.md`.
- Frontend asset build, precompile and production verification follow
  `docs/RELEASE_PRODUCTION.md`.
- Migrations, MQTT, device safety, Rails/MySQL constraints and firmware
  compatibility follow `ai/CONVENTIONS.md` and `ai/ARCHITECTURE.md`.
