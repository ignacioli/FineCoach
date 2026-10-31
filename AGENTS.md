# FineCoach Repository Instructions

## Project

FineCoach (精练教练) is a local-first iPhone app for recording gym classes. One coach keeps student records on the device. The app can also open a read-only personal training archive.

Do not infer accounts, a backend, cloud sync, telemetry, Android, or a separate student client. Do not add product behavior, fields, permissions, or lifecycle states that this repository does not already implement. Ask the product owner first, and record the decision in this repository before designing or building it.

## What this repository contains

M1-A (core class recording) was accepted on 2026-08-30. M1-B (coach operations) was accepted on 2026-10-03; the product owner did not run a separate physical-device acceptance for that slice. M2 (personal training archive) was accepted on 2026-10-11, including a simulator walkthrough and physical-device acceptance on the product owner's iPhone XS Max. `ios/VALIDATION.md` records the evidence and the known gaps.

The shipped stack is native Swift/SwiftUI on iOS 18.0+, using Apple frameworks only and local Core Data persistence. Android is not in this repository.

In-repository authority:

- `design/` is the visual source (product-owner decision, 2026-09-22). `design/design-system/README.md` defines color, typography, spacing, radius, icon, and component values. `design/m1-b-hifi/` holds the approved hi-fi screens, equipment icons, and design notes. `design/m2-hifi/` holds the M2 screens and the implementation map. The visual and experience scorecards are the product owner's private working documents and are not part of this repository.
- `design/design-system/components.md` is the component anatomy: stable `DS-*` ids, parts and reading order, variants, states, invariants, reuse boundaries, code mapping, and the visual workflow. Token values stay in `design/design-system/README.md`; structure lives in `components.md`.
- The Penpot file「M1-B G5 Design」must stay in sync with any design-system change. Code, `design/`, and that Penpot file must not drift apart.
- `ios/VALIDATION.md` is the acceptance record. Simulator results and physical-device results are separate.

## Visual work: component-first

Every task that creates or changes user-visible UI follows `design/design-system/components.md` §1 before editing:

1. **Read before editing.** Read the affected approved screens (`design/*/screens/*.png`), the relevant `README.md` sections, and the affected `components.md` entries. Tokens alone do not define layout; anatomy does.
2. **Classify by design delta, not by wording.** Decide per affected component whether the work is (A) 0→1 design, (B) revision of an approved design, (C) documentation backfill for an unchanged approved design, or (D) implementation drift repair; then whether each component is reused, extended, newly shared, or feature-owned. State the rationale yourself; routine human confirmation of the classification is not required. A and B need product-owner design review in Penpot before code; C and D do not repeat visual approval. Never change the design to legitimize drifted code.
3. **Anatomy before code.** A component's `components.md` entry (or the milestone `implementation-map.md` entry for a feature-owned component) is finalized before code that depends on it. Feature views compose `DS-*` components and tokens only; repeated hand-built structure is a missing component — register it in `components.md` §5 instead of copying it again.
4. **Validate components first, then sample pages.** L0 token and L1 component-contract checks are automated and must pass first (add or update a component-level test for each automatable invariant you introduce). L2 page composition relies on `DesignValueScanTests` plus the composition list in the execution record. Each checkpoint carries an entry and layout map (one line per new interaction: screen, visible control, identifier, data mutation, width owner) instead of a human walkthrough. L3 human review is reserved for new design decisions, a milestone's named core screens when first implemented, one consolidated walkthrough before milestone acceptance, and specific doubts the agent names — not for every page or every checkpoint.
5. **Record the five-line execution record** (`components.md` §1.5) with the change, in the milestone implementation map when that file exists. Record actual results, not intentions.

Ask the product owner one targeted question only for a real authority conflict, an undecidable design delta that changes the approach, or an unapproved substantive design decision; keep doing work that does not depend on the answer.

## Product rules

- Core workflows stay usable offline. Accounts, servers, cloud sync, telemetry, remote logging, and network-dependent core behavior need a product-owner decision and a threat assessment recorded in this repository.
- A confirmed change must be durably recoverable. Do not report success, completion, delivery, import, restore, or deletion until that result is durable and verified. Restore and other destructive operations keep the last valid state until the candidate has passed integrity checks.
- User-visible state, error, selection, and danger must not rely only on color. Touch targets are at least 44 by 44 points. Text scales with Dynamic Type.
- Store distribution and a manual VoiceOver script are not acceptance gates unless the product owner adds them. Do not add VoiceOver-only features. Personal Team local signing is an accepted install path; that does not authorize setting `ITSAppUsesNonExemptEncryption` to `NO` or claiming an encryption exemption.
- Simulator or configuration evidence is not physical-device, runtime, or acceptance evidence. Name the environment and its limits.
- Do not weaken assertions, shrink the agreed scope, or hide known failures to make a check pass.

## Domain language

- Keep Appointment (a scheduled class) distinct from Session (an actual class record).
- Use stable terms for Coach, Student, class scheduling, completed training, exercises, sets, packages, and shared records.
- If a term or relationship changes, record it in the in-repository document that uses it. Do not decide domain language only in code.
- When design notes, acceptance records, and code disagree, surface the conflict. Do not silently pick one reading.

## Privacy and safety

- Treat Coach or Student identity, body information, injuries, notes, schedules, and training history as sensitive.
- Do not expose sensitive content in logs, notification bodies, analytics, filenames, fixtures, screenshots, or generated share artifacts. Tests and documentation use fictional data.
- Share, export, notification, and other handoffs use an explicit allowlist and the smallest disclosure that the app already implements. Do not claim delivery, deletion, or revocation that the app cannot verify.
- Body data never appears in a share report, and there is no UI path that unlocks it.
- Exercise content and media need reviewable provenance and license evidence before distribution. A repository license is not that evidence.

## Change workflow

1. Read the relevant code, tests, and in-repository design notes. Use `ios/VALIDATION.md` as the acceptance record. Something that is not written in this repository is not approved.
2. Ask before decisions that alter product behavior, UX, roles, persistence, compatibility, dependencies, security, privacy, or domain language.
3. When a decision is approved, update the in-repository document that should carry it. Do not leave it only in code or conversation.
4. After implementation begins, inspect the relevant execution path, call sites, data constraints, and tests before editing.
5. Make the smallest change that satisfies the agreed behavior and update tests whenever behavior changes.
6. Run the narrowest relevant validation discovered from repository tooling and state what was not verified.

When code is introduced, document the canonical setup, build, test, lint, and formatting commands here. Do not invent commands before the toolchain exists.

## Operational constraints

These apply to every coding tool and are not stated in the sections above.

- No `Co-Authored-By` or other AI-attribution trailers in any commit message or pull request description.
- Do not discard uncommitted changes without explicit confirmation.
- Green unit and integration tests are not checkpoint completion without the entry and layout map in `design/design-system/components.md` §1.4. `VisionHarnessTests` asserts design-token hex values and WCAG contrast ratios only. Do not describe Feature UI as visually verified unless a human looked; say so when that has not happened.
- Do not add a forced red/green test-order gate, a full UI automation matrix, a fault-injection matrix, a 20-restart matrix, or a new performance-stress matrix unless the product owner asks. Do not add ViewInspector structural assertions on Feature screens unless explicitly requested.
- Do not accept UX or UI work with a screenshot-compare-fix loop unless the product owner asks for that instance.
- A data-changing action must be reachable from a visible control (a button, a swipe action, or a visible menu). A long-press `.contextMenu` alone is not a UI path.
- When a required behavior is ambiguous between an automatic side effect and an explicit coach confirmation, and the effect is hard to reverse (ending a course package's credits, deleting something, or changing billing-adjacent state), ask the product owner. Creating a new course package must not silently end the current package.
- A design-system change goes into `design/` and is backfilled into the Penpot file「M1-B G5 Design」in the same round.
- `project.pbxproj` and `.xcdatamodel` files are XML and do not merge. Do not edit them concurrently.
- A specification or design revision lists what it removes as well as what it adds: one line per difference with location, current state, target, rationale, and whether it changes or is deliberately kept. A revision that only adds controls is incomplete.
- Never launch the app with `-FineCoachResetStore` on the product owner's device; it erases their data. On a simulator it also erases existing test data.

## Project agents

- Use `mobile-ux-designer` during discovery and approved feature design for iOS-first journeys, interaction states, accessibility, prototypes, and usability validation.
- Use `mobile-solution-architect` when the product owner has asked for a technical approach, to record that approach and any focused architecture decisions.
- Use `ios-swiftui-dev` for implementation in this repository. The shipped stack is native Swift and SwiftUI. The agent's existence does not authorize a second stack.
- Use `mobile-code-reviewer` only when the user explicitly asks for a mobile code review. Do not launch it after ordinary implementation. When that explicit review is requested, use it instead of `code-reviewer` or `fs-reviewer` for mobile UI, lifecycle, persistence, or platform-API changes.
- Use `mobile-reliability-tester` after an executable mobile slice exists for lifecycle, migration, offline, permission, accessibility, and device/simulator evidence.
- Use `mobile-privacy-security-reviewer` as an independent read-only gate for architecture and implementation milestones involving sensitive data or platform privacy controls.
- Do not create or route work to an Android implementation agent until an Android phase starts and its stack and compatibility contract are approved.

## Git

- Do not commit unless explicitly requested.
- Keep commits and pull requests scoped to one concern and reference the relevant decision recorded in this repository.
- Preserve unrelated and untracked work.

**Protected primary branch.** Do not modify tracked files, stage, or commit on `main` or `master`. The remote `origin` is the public GitHub repository. Do not push, merge into `main`, delete specs files, or rewrite history without product-owner approval. Use the local `main` tip, then create a topic branch (prefer a dedicated git worktree) before changing tracked files. Direct commits to the primary branch are forbidden. Gitignored local state on the primary checkout is allowed.

**Local toolchain bootstrap.** After `git worktree add`, and before using project skills, `.handoff`, or subagents in that worktree, run `scripts/bootstrap-local-worktree.sh` with the worktree as `cwd`. The script links ignored runtime subtrees from the primary checkout and skips missing sources. Do not symlink entire ignored toolchain directories; the script chooses the subtrees. Agents: run `ig-worktree-gate` before tracked-file edits.

## iOS setup validation

Run these commands from the repository root. Device SDK builds use `CODE_SIGNING_ALLOWED=NO` so setup validation does not require a signing team; use a real signing configuration separately for device installation.

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
