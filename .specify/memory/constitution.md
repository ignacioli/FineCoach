<!--
Sync Impact Report
- Version change: template -> 1.0.0
- Modified principles:
  - Template placeholders -> I. Approved Scope Before Implementation
  - Template placeholders -> II. Local-First Privacy by Default
  - Template placeholders -> III. Recoverability and Data Integrity
  - Template placeholders -> IV. iOS-First, Evidence-Driven Delivery
  - Template placeholders -> V. Accessible, Testable, and Honest Outcomes
- Added sections:
  - Project Constraints
  - Specification-Driven Workflow and Quality Gates
- Removed sections: none
- Follow-up TODOs: none
-->
# FineCoach Constitution

## Core Principles

### I. Approved Scope Before Implementation

- Product behavior MUST originate in an approved PRD and a traceable feature specification.
  Discovery notes, prototypes, glossary entries, and observed behavior are evidence, not approval.
- Roles, product surfaces, fields, permissions, lifecycle states, and exclusions MUST NOT be inferred
  by implementation. An unresolved product decision blocks the affected downstream artifact.
- Each delivery slice MUST follow the approved roadmap order and human-review gates. A later slice
  MUST NOT start merely because its PRD exists when an earlier dependency remains unaccepted.
- Technical plans and tasks MUST remain within the approved behavior. A technical decision that
  changes product behavior MUST return to the applicable PRD, specification, and design review.

Rationale: FineCoach handles sensitive real-world workflows. Separating approved requirements from
discovery evidence prevents accidental scope expansion and makes product-owner decisions auditable.

### II. Local-First Privacy by Default

- Core workflows MUST remain usable offline unless an approved requirement explicitly identifies a
  system boundary. Accounts, servers, cloud synchronization, telemetry, remote logging, and
  network-dependent core behavior require separate approval and a threat assessment.
- Coach and Student identity, contact details, body information, injuries, notes, schedules, and
  training history MUST be treated as sensitive by default.
- Every share, export, report, notification, diagnostic, and external handoff MUST use explicit
  allowlists and minimum-disclosure defaults. The product MUST distinguish App-controlled state from
  a system or third-party boundary and MUST NOT claim external delivery, deletion, or revocation that
  it cannot verify.
- Sensitive content MUST NOT appear in logs, notification bodies, readable filenames, analytics,
  App-switcher previews, fixtures, screenshots, or generated artifacts unless an approved product
  requirement explicitly allows that exact disclosure. Tests and documentation MUST use fictional,
  privacy-safe data.
- Exercise content and media MUST have reviewable provenance, authorship, license, version, and
  redistribution evidence before real distribution.

Rationale: Local ownership and minimum disclosure are product guarantees, not optional
implementation details.

### III. Recoverability and Data Integrity

- A confirmed business change MUST be durably recoverable within the documented fault model.
  Draft, pending, confirmed, saved, failed, and completed states MUST remain distinguishable.
- Failures MUST fail closed: the App MUST NOT report success, completion, delivery, import, restore,
  or deletion until the corresponding observable result is durable and verified.
- Restore, migration, replacement, and destructive operations MUST preserve the last valid state
  until the candidate state has passed integrity, compatibility, and completeness checks. Partial or
  corrupt state MUST NOT become user-visible business data.
- Every reliability claim MUST state its fault-model boundary and be validated with failure-path and
  process-lifecycle evidence. Conditions outside that boundary MUST be reported honestly rather than
  silently weakened.

Rationale: Classroom recording cannot rely on a happy-path save. Recovery and atomicity are part of
the user-visible contract.

### IV. iOS-First, Evidence-Driven Delivery

- FineCoach MUST build and validate the iPhone product first. Android implementation, scaffolding,
  dependencies, and compatibility work MUST wait for its approved phase and MUST NOT dictate the iOS
  architecture prematurely.
- Material choices involving platform support, persistence, concurrency, cryptography, file
  protection, sharing, notifications, dependencies, or distribution MUST be made in an approved
  technical plan with primary-source evidence, alternatives, risks, and a validation strategy.
- No application scaffold, runtime dependency, or production implementation MAY be introduced
  before the applicable technical plan is approved. Simplicity and platform-native capability are
  preferred; every additional dependency or abstraction MUST have a documented need.
- Simulator or configuration evidence MUST NOT be presented as physical-device, runtime,
  distribution, or acceptance evidence. Verification reports MUST name the environment and limits.

Rationale: Phase-specific evidence keeps the first product small and verifiable without imposing
speculative cross-platform costs.

### V. Accessible, Testable, and Honest Outcomes

- Every approved requirement MUST trace through its plan, tasks, implementation, and verification.
  A task is complete only when its requirement-level acceptance evidence exists.
- Critical paths and all empty, error, interruption, recovery, destructive, privacy, and permission
  states MUST be testable. Relevant unit, integration, UI, accessibility, lifecycle, fault-injection,
  migration, and performance checks MUST be planned in proportion to risk.
- User-visible state, error, selection, danger, and statistical meaning MUST NOT rely only on color,
  motion, haptics, or a visual chart. iPhone interfaces MUST support VoiceOver, Dynamic Type, logical
  focus order, and touch targets of at least 44 by 44 points unless an approved exception documents
  equivalent accessibility.
- Validation MUST NOT be gamed by weakening assertions, shrinking the approved scope, substituting
  diagnostics for acceptance, or hiding known failures. Unverified claims and residual risks MUST be
  stated explicitly.

Rationale: Accessibility and evidence quality determine whether FineCoach is usable and whether a
milestone can truthfully be accepted.

## Project Constraints

- Product authority flows from the constitution and approved roadmap to PRD, feature specification,
  approved design evidence, technical plan, tasks, implementation, and verification. A downstream
  artifact MUST NOT contradict or silently amend an upstream authority.
- `specs/ideas.md`, `specs/CONTEXT.md`, low-fidelity prototypes, and evidence summaries remain
  discovery inputs unless their decisions are incorporated into an approved product artifact.
- Appointment and Session MUST remain distinct domain concepts. Domain terminology changes MUST be
  resolved in product artifacts and reflected in `specs/CONTEXT.md`, not decided only in code.
- The App MUST NOT add remote services, authentication, analytics, sensitive diagnostics, or
  distributable exercise assets without the approvals and evidence required by this constitution.
- Repository changes MUST preserve user-owned uncommitted work. Work begins with a Git status and
  diff audit; commits occur only at an authorized checkpoint or when explicitly requested under the
  repository instructions.

## Specification-Driven Workflow and Quality Gates

1. Audit repository state, current roadmap status, artifact authority, dependencies, and open
   decisions before starting a delivery round.
2. Approve the relevant PRD and feature specification before technical planning. Complete the
   required human review of critical journeys, states, privacy, and accessibility before planning.
3. Produce a technical plan that includes a Constitution Check, requirement traceability, material
   decision evidence, threat and privacy boundaries, reliability design, and validation strategy.
4. Obtain explicit product-owner approval of the plan before generating `tasks.md`, scaffolding,
   adding dependencies, or implementing code.
5. Generate dependency-ordered tasks with requirement references and validation gates, then run a
   non-destructive consistency analysis before implementation.
6. Implement in the approved slice order. Each story or phase checkpoint MUST update its task status
   together with the satisfying implementation and MUST run the narrowest relevant validation.
7. Use an independent privacy and security review for architecture and implementation milestones
   that handle sensitive data, storage, backup, sharing, permissions, or platform privacy controls.
8. Before milestone acceptance, converge remaining work, run the approved verification matrix, and
   record physical-device or external-system gaps without converting them into passes.

## Governance

- This constitution governs FineCoach specification, planning, implementation, review, and
  validation workflows. Repository and execution-environment safety instructions remain mandatory;
  when project artifacts conflict, the stricter privacy, safety, evidence, and approved-scope rule
  applies until the product owner resolves the conflict.
- Amendments require a written rationale, product-owner approval, a Sync Impact Report, and an
  assessment of affected roadmap, PRD, specification, design, plan, task, implementation, and test
  artifacts. Materially incompatible changes MUST include a migration or re-review plan.
- Semantic versioning applies: MAJOR removes or incompatibly redefines governance; MINOR adds a
  principle or materially expands obligations; PATCH clarifies wording without changing obligations.
- Every technical plan MUST perform a Constitution Check before design decisions and again before
  implementation authorization. Reviewers MUST block a gate on an unexplained violation.
- Exceptions MUST be explicit, narrowly scoped, time-bounded, approved by the product owner, and
  recorded with owner, rationale, risk, compensating controls, and removal criteria. An undocumented
  exception is a violation.
- Compliance MUST be rechecked at plan approval, task generation and analysis, implementation
  checkpoints, privacy/security review, and milestone acceptance.

**Version**: 1.0.0 | **Ratified**: 2026-08-26 | **Last Amended**: 2026-08-26
