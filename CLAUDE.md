# FineCoach — Claude Code Project Instructions

This file is read automatically by Claude Code. `AGENTS.md` remains the
authoritative, tool-agnostic project charter (product scope, domain
language, full agent roster). This file ports the **enforceable
operational constraints** from `AGENTS.md` into a format Claude Code
loads by default, plus rules specific to Claude Code sessions. If the
two ever disagree, `AGENTS.md` wins for product and process questions;
this file wins for how a Claude Code session should behave mechanically.

## Stack (current, approved)

Shipped iOS: native Swift/SwiftUI, iOS 18.0+, Apple frameworks only, Core Data +
SQLite local persistence, no cloud, backend, or telemetry. Do not
introduce another stack, platform, or a network-dependent core
behavior unless the product owner decides and that decision is recorded
in this repository. See `AGENTS.md` §Change Workflow.

Android is approved by the product owner on 2026-11-02 (ADR-001 D1,
Q1–Q3, Q7, `specs/007-android-port/adr-001-android-and-macos-port.md`):
Kotlin + Jetpack Compose, `minSdk 31`, SQLite + Room, in `android/`;
shared test vectors and contract samples in `shared/`, using fictional
data only. Do not create the project before the S0 spec is approved.
Do not change iOS product code; interoperability and shared-vector tests
may be added. `targetSdk` and the token intermediate format are undecided
until S0; the Live Activity counterpart is undecided until S5 (Q5).
Gradle build and test commands will be added to `AGENTS.md` when S0-02
creates the project.

FCBK and FCPA are frozen, bidirectional iOS–Android formats (D2): the
existing iOS formats are the contract. Change the contract and raise its
version before changing both platforms. macOS is only TestFlight
validation of the iPhone app on Apple Silicon Macs (D3): no code changes
or Mac target; Mac Catalyst requires a later decision.

## Protected primary branch

Do not modify tracked files, stage, or commit on `main` or `master` in
this repository. The remote `origin` is the public GitHub repository;
do not push without product-owner approval. Before any
tracked-file edit, create or switch into a topic branch — prefer a
dedicated `git worktree` — and run the `ig-worktree-gate` skill before
editing. Gitignored or untracked local state on the primary checkout is
fine.

## Worktree bootstrap

After `git worktree add`, and before using project skills, `.handoff`,
or subagents in that worktree, run `scripts/bootstrap-local-worktree.sh`
with the worktree as `cwd`. It links ignored runtime subtrees from the
primary checkout and skips missing sources. Do not symlink entire
ignored toolchain directories; the script chooses the subtrees.

## Verification gates — what "done" actually means here

- The iOS automated acceptance gates remain: `xcodebuild
  build`, the `FineCoachTests` unit target, and the
  `FineCoachIntegrationTests` restart/persistence target. There is a
  narrow **Deterministic Vision Validation Harness**
  (`FineCoachTests/DesignSystem/VisionHarnessTests.swift`) but it only
  asserts design-token hex values and computed WCAG contrast ratios — it
  does **not** screenshot or pixel-diff any Feature UI screen. Do not
  describe Feature UI work as "visually verified" unless a human looked
  at the simulator, and say so explicitly when that hasn't happened.
- Do not run `xcodebuild test` as a substitute for physical-device
  acceptance; simulator and physical-device evidence are separate gates
  (`AGENTS.md` §iOS setup validation).
- Do not introduce a forced red/green test-order gate, a full UI
  automation matrix, a fault-injection matrix, a 20-restart matrix, or a
  new performance-stress matrix as a default verification gate.
  Core-path unit and integration tests are the bar unless the project
  owner explicitly asks for more.
- No ViewInspector-level structural assertions on Feature screens unless
  explicitly requested.
- Android adds the product-owner-approved gates in ADR-001 Q11/Q12:
  JVM screenshot regression tests against human-approved baselines, and
  Compose UI tests (Robolectric) for entry and layout assertions. These
  Android entry and layout tests are the explicitly requested exception
  to the Feature-screen structural-assertion restriction. iOS is unchanged.
  Android build and test commands will be recorded in `AGENTS.md` at S0-02.
- Store distribution and a manual VoiceOver script are not acceptance
  gates unless the product owner adds them. Do not set
  `ITSAppUsesNonExemptEncryption` to `NO` or claim an encryption
  exemption.

## Checkpoint completion — structural evidence per checkpoint, human walkthrough per milestone

A checkpoint is not "done" when tests are green. It requires both:

1. For iOS, `xcodebuild build` + `FineCoachTests` + `FineCoachIntegrationTests`
   green (the automated gate — proves domain logic and persistence are
   correct). For Android, the slice's automated gates under ADR-001 and
   `specs/007-android-port/roadmap.md` §3 must pass.
2. An **entry and layout map** in the execution record
   (`design/design-system/components.md` §1.4): one line per new
   user-facing interaction — screen → visible control → accessibility
   identifier → whether it mutates data → which component or container
   makes it fill the width. Every line must point at real code. A
   missing entry, a gesture-only or contextMenu-only mutation, or a
   width that no component or container fills is a defect to fix, not
   something to leave for a human to find.

For Android, the entry and layout map is enforced by Compose UI tests
(Robolectric, ADR-001 Q12): data-changing controls must be visible,
clickable, and reachable without relying only on long-press; controls
required to fill the width must equal their parent container's width.
The map itself remains in the execution record. This is the explicitly
approved Android exception; the iOS map and gates are unchanged.

iOS unit and integration tests do not render SwiftUI views and
cannot detect a missing `.frame(maxWidth: .infinity)`, a control hidden
behind an undiscoverable gesture, or logic that is fully tested but has
no UI entry point. These are real defect classes — three shipped in an
earlier milestone despite green tests. The entry and layout map exists
to catch exactly these three structurally.

A human walkthrough is no longer required at every checkpoint. It
happens only under the L3 triggers in `components.md` §1.4:
product-owner review of new design decisions (in Penpot), a milestone's
named core screens once when first implemented, **one consolidated
walkthrough before milestone acceptance** (the agent seeds the simulator
and lists only new interactions and core screens), and specific doubts
the agent names that structural evidence cannot settle. Never describe
Feature UI as "visually verified" unless a human actually looked; say
explicitly when that has not happened yet.

## Discoverable affordances — no contextMenu-only actions

Any action that mutates data (marks something absent, cancelled, or
deleted, applies a charge, ends or starts a lifecycle state, and so on)
must be reachable from a visible, obviously tappable control — a button,
a swipe action, or a visible menu or "…" icon — not **only** a
`.contextMenu` triggered by long-press. A long-press-only trigger is
invisible to a first-time user and does not count as a UI path, even
though the code exists and is technically reachable.

## Ambiguous, consequential behavior — ask, don't silently pick one reading

When a required behavior is ambiguous between "the system does X
automatically as a side effect" and "the coach must explicitly do X
first, as a precondition, with its own confirmation," and X has a real
consequence that is not easily reversed (ends a course package's
credits, deletes something, changes billing-adjacent state), treat that
ambiguity as a question for the project owner. Do not resolve it as an
implementation detail. This applies whether the choice is made by a
subagent or by the orchestrating session.

A real instance: when a valid course package already exists, creating a
new one must not silently end the current package. The coach confirms
ending it first. An earlier implementation ended the old package
automatically, with no confirmation. That reading should have been
confirmed, not assumed.

## UX/UI acceptance — no screenshot-loop automation

**Never use a "screenshot → compare → fix" loop as the acceptance
mechanism for UX/UI work, at any time, unless the project owner
explicitly asks for it in that instance.** This applies to the iOS
Simulator control tool and any other screenshot-capable tool.

Android's approved regression gate (ADR-001 Q11) uses a human-approved
baseline plus deterministic automated pixel comparison. Only the product
owner may approve and update baselines; agents must not modify them.
Agents read test text results only (failed cases and difference ratios),
never screenshot or difference images. This is not a screenshot → judge
→ fix loop: no model judges the images. Baselines follow the owner's
first walkthrough of core screens against the approved iOS designs;
JVM regression results do not replace physical-device walkthroughs.

- A small number of manual screenshots taken *while debugging* a
  specific, already-identified visual issue is fine.
- Building an automated cycle that takes a screenshot, judges it,
  edits code, and repeats — as a general-purpose way to "verify the UI
  looks right" — is not fine. It did not exist as a gate before this
  rule and must not be reintroduced informally.
- When a human needs to eyeball Feature UI, seed the simulator with
  data and hand control to them (as in the earlier manual acceptance
  walkthroughs) rather than iterating on screenshots yourself.
- The iOS Simulator control tool is token-expensive per round trip
  (each screenshot is an image, and coordinate-guessing loops multiply
  that). Treat it as a tool for a human-guided walkthrough, not a
  default verification step for routine changes.

## Visual design authority

`design/` is the single authoritative visual source (`AGENTS.md`
§What this repository contains). `design/design-system/README.md`
defines every color, type style, spacing, radius, icon, and component
value; Feature views consume those tokens and never introduce their own
values. `design/design-system/components.md` defines component anatomy
and the mandatory visual workflow (`AGENTS.md` §Visual work:
component-first): classify the design delta (A/B/C/D) and
reuse, extend, or new per component yourself, finalize the component
anatomy before dependent code, pass automated token and component
checks before sampling pages, and request human review only under its
L3 triggers. Human walkthroughs (only under the L3 triggers) never mean
comparing every page against its PNG. Compare a screen against its
approved `design/*/screens/*.png` target during such a walkthrough —
this is checking against a fixed approved image, not the forbidden
screenshot loop above. A design change goes into the design-system doc
and is backfilled into Penpot「M1-B G5 Design」 in the same round; never
let code, doc, and Penpot drift apart.

## Privacy and safety

- Treat Coach and Student identity, body data, injuries, notes,
  schedules, and training history as sensitive. Never expose them in
  logs, notification bodies, analytics, filenames, fixtures,
  screenshots, or generated share artifacts.
- Body data is permanently forbidden from share reports. There is no UI
  unlock path.
- No telemetry, remote logging, cloud services, or auth without a
  product-owner decision and a threat assessment recorded in this
  repository.
- Android follows the same privacy and offline rules as iOS (ADR-001
  Q8–Q10): no network calls, `INTERNET` permission, or network APIs;
  networking requires a product-owner decision and threat assessment.
  Disable Auto Backup and device migration with `allowBackup=false` and
  all-domain exclusions for cloud backup, device transfer, and iOS
  cross-platform transfer in `dataExtractionRules` (`AGENTS.md` §Privacy
  and safety; ADR-001 §6.1, cross-platform syntax to be validated in S0).
  Device replacement uses an explicitly exported FCBK encrypted backup.
  Cover recent-task thumbnails (API 33+ `setRecentsScreenshotEnabled(false)`,
  API 31/32 cover on `onPause`, validated in S0); do not use `FLAG_SECURE`
  or prohibit screenshots.

## Git

- Do not commit unless explicitly requested.
- Keep commits and pull requests scoped to one concern; reference the
  decision in this repository that drives the change.
- No `Co-Authored-By` or other AI-attribution trailers in any commit
  message or pull request description, anywhere in this repository.
- Preserve unrelated and untracked work; never discard uncommitted
  changes without explicit confirmation.

## Subagent dispatch discipline

- For Android slices (ADR-001 Q13), the product owner approves one run
  list at the start of each slice: task, agent, model, worktree, branch.
  Runs on that list do not need repeated approval; runs outside it still
  require approval first. Commit, merge, and push each still require
  product-owner approval every time.
- Never call the Agent tool a second time for a task whose subagent has
  not yet finished or been properly resumed. To correct or continue a
  running or completed background agent, use `SendMessage` to its agent
  ID — never spawn a fresh `Agent` call believing it continues the same
  work; that creates a second, untracked writer against the same files.
- Before and after any subagent resume, independently verify worktree
  state yourself (`git status --short`, `git log --oneline`) rather
  than trusting the subagent's self-reported completion summary.
- Do not point two concurrent subagents at the same worktree path.
  Tasks that are genuinely file-disjoint (no shared `project.pbxproj`
  or `.xcdatamodel` edits) may use the Agent tool's `isolation:
  "worktree"` option for true parallelism, with the primary agent
  merging the result back; tasks that touch either of those two files
  should stay strictly sequential — pbxproj and xcdatamodel files are
  XML and do not merge cleanly.
