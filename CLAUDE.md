# FineCoach — Claude Code Project Instructions

This file is read automatically by Claude Code. `AGENTS.md` remains the
authoritative, tool-agnostic project charter (product scope, discovery
process, domain modeling, full agent roster). This file ports the
**enforceable operational constraints** from `AGENTS.md` into a format
Claude Code loads by default, plus rules specific to Claude Code sessions.
If the two ever disagree, `AGENTS.md` wins for product/process questions;
this file wins for how a Claude Code session should behave mechanically.

## Stack (current, approved)

Native Swift/SwiftUI, iOS 18.0+, Apple frameworks only, Core Data +
SQLite local persistence, no cloud/backend/telemetry. Do not introduce a
second stack, a new platform, or a network-dependent core behavior
without an approved spec — see `AGENTS.md` §Change Workflow.

## Protected primary branch

Do not modify tracked files, stage, or commit on `main` or `master` in
this repository. This repo currently has no remote. Before any
tracked-file edit, create or switch into a topic branch — prefer a
dedicated `git worktree` — and run the `ig-worktree-gate` skill before
editing. Gitignored/untracked local state on the primary checkout is
fine.

## Worktree bootstrap

After `git worktree add`, and before using project skills, SpecKit,
`.handoff`, or subagents in that worktree, run
`scripts/bootstrap-local-worktree.sh` with the worktree as `cwd` (it
relative-symlinks ignored runtime subtrees from the primary checkout;
never symlink all of `.specify/`, `.cursor/`, or `.codex/`). The private
specs repository (`specs/` symlink target) is a separate git repo and is
not wired by this script — `cd` into its resolved path before committing
there.

## Verification gates — what "done" actually means here

- The only automated acceptance gates in this repo are: `xcodebuild
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
  (`AGENTS.md` §M1-A Setup Validation).
- MUST NOT introduce a forced TDD red/green gate, a full UI automation
  matrix, a fault-injection matrix, a 20-restart matrix, or a new
  performance-stress matrix as a *default* verification gate (M1-B spec
  §2.3 / NFR-009 / D-010). Core-path unit + integration tests are the
  bar unless the project owner explicitly asks for more.
- No ViewInspector-level structural assertions on Feature screens unless
  explicitly requested.

## Checkpoint completion — manual walkthrough is not optional

A story/phase Checkpoint is not "done" when tests are green. It requires
BOTH:

1. `xcodebuild build` + `FineCoachTests` + `FineCoachIntegrationTests`
   green (the automated gate — proves domain logic and persistence are
   correct).
2. A human has actually opened the built app on a simulator (or real
   device) and operated every new user-facing interaction at least
   once, checking two things automated tests structurally cannot see:
   whether it renders at a sane layout/width, and whether a first-time
   user would ever find it without being told.

Unit/integration tests in this repo do not render SwiftUI views and
cannot detect a missing `.frame(maxWidth: .infinity)`, a control hidden
behind an undiscoverable gesture, or "this logic is fully tested but has
no UI entry point at all." These are real defect classes, not
hypothetical — three shipped in Phase 4 despite 100% green tests, found
only by a manual walkthrough. Do not report a phase/Checkpoint as
complete, or describe Feature UI as "done," until step 2 has actually
happened; say explicitly when it hasn't (see the existing rule below on
not claiming "visually verified" without a human having looked).

## Discoverable affordances — no contextMenu-only actions

Any action that mutates data (marks something absent/cancelled/deleted,
applies a charge, ends/starts a lifecycle state, etc.) MUST be reachable
from a visible, obviously-tappable control — a button, a swipe action,
or a visible menu/"…" icon — not **only** a `.contextMenu` triggered by
long-press. A long-press-only trigger is invisible to a first-time user
and does not count as "the feature has a UI path," even though the code
technically exists and is technically reachable.

## Ambiguous, consequential spec wording — ask, don't silently pick one reading

When a spec/task sentence describing a MUST behavior is ambiguous
between "the system does X automatically as a side effect" and "the
coach must explicitly do X first, as a precondition, with its own
confirmation," and X has a real, not-easily-reversed consequence (ends
a course package's credits, deletes something, changes billing-adjacent
state) — treat that ambiguity as a question for the project owner, not
an implementation detail to resolve silently. This applies whether the
choice is made by a subagent or by the orchestrating session itself
quoting the sentence into a task brief without flagging the ambiguity.
A real instance of this: M1B-FR-012's "已有有效课包时新建 MUST 先结束当前课包"
was silently implemented as an automatic, unconfirmed side effect of
creating a new package, silently ending the old one with no coach
confirmation — the reading that should have been confirmed, not assumed.

## UX/UI acceptance — no screenshot-loop automation

**Never use a "screenshot → compare → fix" loop as the acceptance
mechanism for UX/UI work, at any time, unless the project owner
explicitly asks for it in that instance.** This applies to the iOS
Simulator control tool and any other screenshot-capable tool.

- A small number of manual screenshots taken *while debugging* a
  specific, already-identified visual issue is fine.
- Building an automated cycle that takes a screenshot, judges it,
  edits code, and repeats — as a general-purpose way to "verify the UI
  looks right" — is not fine. It did not exist as a gate before this
  rule and must not be reintroduced informally.
- When a human needs to eyeball Feature UI, seed the simulator with
  data and hand control to them (as in the Phase 4-6 manual acceptance
  walkthroughs) rather than iterating on screenshots yourself.
- The iOS Simulator control tool is token-expensive per round trip
  (each screenshot is an image, and coordinate-guessing loops multiply
  that). Treat it as a tool for a human-guided walkthrough, not a
  default verification step for routine changes.

## Visual design authority

`design/` is the single authoritative visual source (`AGENTS.md`
§Current Artifacts and Authority). `design/design-system/README.md`
defines every color, type style, spacing, radius, icon, and component
value; Feature views consume those tokens and never introduce their own
values. Compare a screen against its `design/m1-b-hifi/screens/*.png`
target during the human walkthrough — this is checking against a fixed
approved image, not the forbidden screenshot loop above. A design
change goes into the design-system doc and is backfilled into Penpot
「M1-B G5 Design」 in the same round; never let code, doc, and Penpot
drift apart.

## Privacy and safety

- Treat Coach/Student identity, body data, injuries, notes, schedules,
  and training history as sensitive. Never expose it in logs,
  notification bodies, analytics, filenames, fixtures, screenshots, or
  generated share artifacts.
- Body data is permanently forbidden from Share Report (M1B-FR-030) —
  no UI unlock path, ever.
- No telemetry, remote logging, cloud services, or auth without an
  approved requirement and threat assessment.

## Git

- Do not commit unless explicitly requested.
- Keep commits and PRs scoped to one concern; reference the approved
  requirement or decision driving the change.
- No `Co-Authored-By` or other AI-attribution trailers in any commit
  message or PR description, anywhere in this repository.
- Preserve unrelated and untracked work; never discard uncommitted
  changes without explicit confirmation.

## Subagent dispatch discipline

- Never call the Agent tool a second time for a task whose subagent has
  not yet finished or been properly resumed. To correct or continue a
  running/completed background agent, use `SendMessage` to its agent
  ID — never spawn a fresh `Agent` call believing it "continues" the
  same work; that creates a second, untracked writer against the same
  files.
- Before and after any subagent resume, independently verify worktree
  state yourself (`git status --short`, `git log --oneline`) rather
  than trusting the subagent's self-reported completion summary.
- Do not point two concurrent subagents at the same worktree path.
  Tasks that are genuinely file-disjoint (no shared `project.pbxproj`
  or `.xcdatamodel` edits) may use the Agent tool's `isolation:
  "worktree"` option for true parallelism, with the primary agent
  merging the result back; tasks that touch either of those two files
  should stay strictly sequential — pbxproj/xcdatamodel are XML and do
  not merge cleanly.
