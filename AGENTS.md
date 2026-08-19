# FineCoach Repository Instructions

## Project

FineCoach (精练教练) is intended to become a local-first mobile App for recording gym classes and serving Coaches and Students.

The precise user roles and product surfaces are not yet approved. Do not infer whether Students directly use the App, receive exported records, use a separate client, or have accounts. Resolve those questions in the product specification before designing behavior or architecture around them.

## Current Artifacts and Authority

- `specs/ideas.md` contains initial product ideas. It is not an approved specification or PRD and is not a source of binding requirements.
- Treat requirement-style language, scope boundaries, acceptance scenarios, and technical questions in `specs/ideas.md` as discovery input that still requires confirmation.
- `specs/CONTEXT.md` is the current working domain glossary. Use its terms consistently during discovery, but do not treat a term definition as proof that related product behavior has been approved.
- There is currently no approved product specification or PRD in the repository. Do not silently promote `specs/ideas.md` into one.
- When an approved specification is added, identify it explicitly here and define how it relates to the ideas document and glossary.

## Current Phase

The repository is in product discovery and requirements definition. Delivery sequencing is approved: build and validate the iOS App first, then add Android later. No application framework, supported OS/version matrix, role model, database, synchronization model, backup format, exercise-asset source, report renderer, notification implementation, or distribution method has been approved.

Before implementation:

1. Resolve the target users, Coach/Student responsibilities, product surfaces, and primary workflows.
2. Produce and approve a product specification or PRD with explicit goals, scope, exclusions, functional requirements, non-functional requirements, and acceptance scenarios.
3. Produce a technical plan based on that approved document, with evidence for material architecture and dependency choices.
4. Trace implementation tasks and validation back to approved requirements.

Do not create application scaffolding or add dependencies merely to make progress before the product specification and technical plan are approved.

## Working Direction, Not Approved Scope

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
- Use `mobile-reliability-tester` after an executable mobile slice exists for lifecycle, migration, offline, permission, accessibility, and device/simulator evidence.
- Use `mobile-privacy-security-reviewer` as an independent read-only gate for architecture and implementation milestones involving sensitive data or platform privacy controls.
- Do not create or route work to an Android implementation agent until the Android phase starts and its stack and compatibility contract are approved.

## Git

- Do not commit unless explicitly requested.
- Keep commits and pull requests scoped to one concern and reference the relevant approved requirement or decision.
- Preserve unrelated and untracked work.
