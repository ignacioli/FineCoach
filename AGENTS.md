# FineCoach Repository Instructions

## Project

FineCoach (精练教练) is intended to become a local-first mobile App for recording gym classes and serving Coaches and Students. The approved M1-A scope uses one Coach operator and Student records.

Outside approved M1-A behavior, do not infer whether Students directly use the App, receive exported records, use a separate client, or have accounts. Resolve those questions in the relevant product specification before designing behavior or architecture around them.

## Current Artifacts and Authority

- `specs/ideas.md` contains initial product ideas. It is not an approved specification or PRD and is not a source of binding requirements.
- Treat requirement-style language, scope boundaries, acceptance scenarios, and technical questions in `specs/ideas.md` as discovery input that still requires confirmation.
- `specs/CONTEXT.md` is the current working domain glossary. Use its terms consistently during discovery, but do not treat a term definition as proof that related product behavior has been approved.
- `specs/001-m1-a-core-session/spec.md` is the approved M1-A product specification; its approved `plan.md`, detailed design artifacts, and `tasks.md` describe the shipped M1-A slice.
- `specs/002-m1-b-coach-operations/spec.md` is the approved M1-B feature specification (`1.2-approved`; Revision 1.2 approved 2026-09-26), including §10 decisions. Its approved `plan.md` and `tasks.md` describe the M1-B slice, which is implemented. M1-B verification MUST follow that spec §2.3 (core-path unit and integration tests; no TDD/red-green gate).
- The approved M1-A artifacts override discovery input only within their explicit scope. Do not promote remaining ideas into requirements.
- `design/` in this repository is the single authoritative visual design baseline and source (product-owner decision, 2026-09-22): `design/design-system/README.md` defines color, typography, spacing, radius, icon, and component rules; `design/m1-b-hifi/` holds the approved hi-fi screens, equipment icons, and design notes; `design/12d-visual-scorecard.md` is the visual quality bar. They are backed by the Penpot file「M1-B G5 Design」, which must be kept in sync with any design-system change. The private specs repository keeps only design-discovery evidence and must not be used as a visual source.
- `design/design-system/components.md` is the component anatomy spec: stable `DS-*` component IDs, parts and reading order, variants, states, invariants, reuse boundaries, code mapping, and the visual workflow. Token and component values stay in `design/design-system/README.md`; structure lives in `components.md`.

## Visual Work: Component-First

Every task that creates or changes user-visible UI follows `design/design-system/components.md` §1 before editing:

1. **Read before editing.** Read the affected approved screens (`design/*/screens/*.png`), the relevant `README.md` sections, and the affected `components.md` entries. Tokens alone do not define layout; anatomy does.
2. **Classify by design delta, not by wording.** Decide per affected component whether the work is (A) 0→1 design, (B) revision of an approved design, (C) spec backfill for an unchanged approved design, or (D) implementation drift repair; then whether each component is reused, extended, newly shared, or feature-owned. State the rationale yourself; routine human confirmation of the classification is not required. A and B need product-owner design review in Penpot before code; C and D do not repeat visual approval. Never change the design to legitimize drifted code.
3. **Spec before code.** A component's `components.md` entry (or the milestone `implementation-map.md` entry for a feature-owned component) is finalized before code that depends on it. Feature views compose `DS-*` components and tokens only; repeated hand-built structure is a missing component — register it in `components.md` §5 instead of copying it again.
4. **Validate components first, then sample pages.** L0 token and L1 component-contract checks are automated and must pass first (add or update a component-level test for each automatable invariant you introduce). L2 page composition relies on `DesignValueScanTests` plus the composition list in the execution record. Each checkpoint carries an entry and layout map (one line per new interaction: screen, visible control, identifier, data mutation, width owner) instead of a human walkthrough. L3 human review is reserved for new design decisions, a spec's named core screens when first implemented, one consolidated walkthrough before the milestone acceptance gate, and specific doubts the agent names — not for every page or every checkpoint.
5. **Record the five-line execution record** (`components.md` §1.5) in the plan, tasks, or milestone implementation map, with actual results rather than intentions.

Ask the product owner one targeted question only for a real authority conflict, an undecidable design delta that changes the approach, or an unapproved substantive design decision; keep doing work that does not depend on the answer.

## Current Phase

M1-A (R1) is implemented and accepted (G4 passed 2026-08-30). M1-B (`002-m1-b`) is implemented: the G5 design review passed, and all `tasks.md` tasks through Phase 8 are complete, including the product-owner simulator walkthrough of the Phase 8 checkpoint (2026-10-03). The product owner passed G6 (M1-B implementation acceptance) on 2026-10-03 and decided not to run physical-device acceptance for M1-B; `ios/VALIDATION.md` records the evidence and its known gaps. M1-B is accepted (R2). M2 (R3) pre-spec open items were resolved on 2026-10-04 (M2 PRD revised to `1.1-approved`). The M2 spec (`specs/003-m2-personal-training-archive/spec.md`, now `1.1-approved` after the 2026-10-08 design-review revision; M2 PRD `1.2-approved`) passed the G7 spec half on 2026-10-04, and the product owner approved the M2 high-fidelity design carrier (`design/m2-hifi/`, Penpot page "M2 G7 Design"; core pages M2-02 and M2-11) on 2026-10-09, so G7 has passed in full. The M2 plan was approved on 2026-10-09 and `tasks.md` (T001–T070) was generated and passed `speckit-analyze`. The next step is M2 implementation, starting with Phase 1 (the components specified in `design/design-system/components.md` §4.7). M2 requires physical-device acceptance on the product owner's iPhone XS Max as the last step before the implementation acceptance gate (T070). The shipped stack is native Swift/SwiftUI on iOS 18.0+, using Apple frameworks and local Core Data persistence. Android and requirements outside approved specs remain in discovery.

Before implementing work outside approved M1-A scope:

1. Resolve the target users, Coach/Student responsibilities, product surfaces, and primary workflows.
2. Produce and approve a product specification or PRD with explicit goals, scope, exclusions, functional requirements, non-functional requirements, and acceptance scenarios.
3. Produce a technical plan based on that approved document, with evidence for material architecture and dependency choices.
4. Trace implementation tasks and validation back to approved requirements.

Do not add adjacent product behavior, platforms, or dependencies merely to make progress beyond the approved M1-A plan.

## Outside M1-A: Working Direction, Not Approved Scope

The confirmed working direction is a local-first gym-class record mobile App for Coaches and Students, delivered iOS first and Android later. Details in `specs/ideas.md`—including user access, platform implementation, scheduling, session recording, course packages, exercise content, sharing, privacy behavior, backup, and release boundaries—remain proposals until they are carried into an approved specification.

When refining the product, explicitly resolve at least:

- whether Coach and Student are both App users and which workflows each controls;
- what local-first means for data ownership, device boundaries, synchronization, export, backup, and recovery;
- which iOS versions and form factors are in scope for the first release, and what evidence will trigger the later Android phase;
- which class-planning, scheduling, in-class recording, history, package, and reporting workflows belong in the first release;
- which Student data is sensitive, which data may be shared, and how those rules are enforced;
- how exercise content is sourced, reviewed, licensed, versioned, and attributed.

## Domain Modeling

- Keep Appointment (a scheduled class) distinct from Session (an actual class record) while those working terms remain in use.
- Use stable, unambiguous terms for Coach, Student, class scheduling, completed training, exercises, sets, packages, and shared records.
- If discovery changes a term or relationship, update `specs/CONTEXT.md` when the decision is resolved.
- Keep `specs/CONTEXT.md` implementation-free. Product behavior belongs in the future approved specification; hard-to-reverse technical decisions belong in focused ADRs after a real trade-off is decided.
- Surface conflicts between the ideas document, glossary, approved requirements, and code. Do not silently choose one interpretation.

## Privacy and Safety

- Treat any Coach or Student identity, body information, injuries, notes, schedules, and training history as potentially sensitive until the approved specification defines handling rules.
- Do not expose sensitive content in logs, notification bodies, analytics, filenames, fixtures, screenshots, or generated share artifacts.
- Do not introduce telemetry, remote logging, cloud services, authentication, or network-dependent core behavior without an approved requirement and threat assessment.
- Exercise data and media require provenance and license verification before distribution. A repository or code license is not proof that included media may be redistributed.

## Change Workflow

1. Read `specs/ideas.md` and `specs/CONTEXT.md` for discovery context, then identify which statements are confirmed and which remain open.
2. Ask before decisions that alter product behavior, UX, roles, persistence, compatibility, dependencies, security, privacy, or domain language.
3. Update the appropriate product artifact when a decision is approved; do not leave the decision only in code or conversation.
4. After implementation begins, inspect the relevant execution path, call sites, data constraints, and tests before editing.
5. Make the smallest change that satisfies approved requirements and update tests whenever behavior changes.
6. Run the narrowest relevant validation discovered from repository tooling and state what was not verified.

When code is introduced, document the canonical setup, build, test, lint, and formatting commands here. Do not invent commands before the toolchain exists.

## Project Agents

- Use `mobile-ux-designer` during discovery and approved feature design for iOS-first journeys, interaction states, accessibility, prototypes, and usability validation.
- Use `mobile-solution-architect` after PRD approval, or for explicitly authorized architecture discovery, to produce the technical plan and focused ADRs.
- Use `ios-swiftui-dev` only if the approved technical plan selects native Swift and SwiftUI. Its existence does not pre-approve that stack.
- Use `mobile-code-reviewer` only when the user explicitly asks for a mobile code review. Do not launch it after ordinary implementation. When that explicit review is requested, use it instead of `code-reviewer` or `fs-reviewer` for mobile UI, lifecycle, persistence, or platform-API changes.
- Use `mobile-reliability-tester` after an executable mobile slice exists for lifecycle, migration, offline, permission, accessibility, and device/simulator evidence.
- Use `mobile-privacy-security-reviewer` as an independent read-only gate for architecture and implementation milestones involving sensitive data or platform privacy controls.
- Do not create or route work to an Android implementation agent until the Android phase starts and its stack and compatibility contract are approved.

## Git

- Do not commit unless explicitly requested.
- Keep commits and pull requests scoped to one concern and reference the relevant approved requirement or decision.
- Preserve unrelated and untracked work.

**Protected primary branch.** Do not modify tracked files, stage, or commit on `main` or `master`. This repository currently has no remote: use the local `main` tip, then create a topic branch (prefer a dedicated git worktree) before changing tracked files. Direct commits to the primary branch are forbidden. Gitignored local state on the primary checkout is allowed.

**Local toolchain bootstrap.** After `git worktree add`, and before using project skills, SpecKit, `.handoff`, Cursor subagents, or Codex project subagents in that worktree, run `scripts/bootstrap-local-worktree.sh` with the worktree as `cwd`. The script relative-symlinks ignored runtime subtrees from the primary checkout and skips missing sources. Do not symlink all of `.specify/`, `.cursor/`, or `.codex/`. Agents: run `ig-worktree-gate` before tracked-file edits. The private specs repository is a different git repo and is not wired by this script.

## M1-A Setup Validation (T001-T008)

The approved iOS implementation stack is native Swift/SwiftUI on iOS 18.0+, using Apple frameworks only. Run these commands from the repository root. Device SDK builds use `CODE_SIGNING_ALLOWED=NO` so setup validation does not require a signing team; use a real signing configuration separately for device installation.

```sh
xcodebuild -project ios/FineCoach.xcodeproj -list
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoach -showTestPlans
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachTests -showTestPlans
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachIntegrationTests -showTestPlans
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachUITests -showTestPlans
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoach -configuration Debug -sdk iphoneos -derivedDataPath /tmp/FineCoachDD-AppDebug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoach -configuration Release -sdk iphoneos -derivedDataPath /tmp/FineCoachDD-AppRelease CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachTests -configuration Debug -sdk iphoneos -derivedDataPath /tmp/FineCoachDD-Unit CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachIntegrationTests -configuration Debug -sdk iphoneos -derivedDataPath /tmp/FineCoachDD-Integration CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachIntegrationTests -configuration Release -sdk iphoneos -derivedDataPath /tmp/FineCoachDD-IntegrationRelease CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachUITests -configuration Debug -sdk iphoneos -derivedDataPath /tmp/FineCoachDD-UI CODE_SIGNING_ALLOWED=NO build-for-testing
! nm -j /tmp/FineCoachDD-AppRelease/Build/Products/Release-iphoneos/FineCoach.app/FineCoach | rg 'FaultInjection|FaultInjector|persistenceWriterSave|generationMetadataWrite|currentPointerReplace'
xcrun swift-format lint --configuration .swift-format --recursive --parallel --strict ios/FineCoachApp ios/FineCoachTests ios/FineCoachIntegrationTests ios/FineCoachUITests ios/TestSupport
xcrun swift-format format --configuration .swift-format --recursive --parallel --in-place ios/FineCoachApp ios/FineCoachTests ios/FineCoachIntegrationTests ios/FineCoachUITests ios/TestSupport
```

The four test plans are kept under `ios/FineCoach.xcodeproj/xcshareddata/xctestplans/` for project organization and mirrored at the Xcode project package root because Xcode 26 resolves the shared-scheme `container:` references from that package-root location. Do not run `xcodebuild test` as a substitute for physical-device acceptance; simulator/runtime availability and physical-device evidence are separate gates.
