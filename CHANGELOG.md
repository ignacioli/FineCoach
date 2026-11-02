# Changelog

Notable changes to FineCoach are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow [Semantic Versioning](https://semver.org/). The version is the app's `MARKETING_VERSION`.

## [Unreleased]

## [0.2.0] - 2026-11-02

This version focuses on the training page, progress feedback, and system entry points. Builds before 2026-10-23 carried no version number.

### Added

- Training page:
  - Weight and reps use a stepper: tap − / + or type the number directly.
  - Each exercise shows the same student's last session, and those numbers can be carried into a pending set.
  - Confirming a set starts a 120-second rest bar that can be adjusted by 15 seconds or skipped.
  - A notification fires when the rest ends.
  - Confirming a set gives light haptic feedback.
- Several students can train at the same time, with at most one session in progress per student. Today shows a "Continue" entry for each.
- Swipe to delete a set, with a 4-second undo. Sections can be deleted. Restoring a backup asks for confirmation first.
- New-record label on a set row during training, with a one-time number float. It respects Reduce Motion.
- "Session gains" on the session summary and detail: previous versus current performance, new records, class-count milestones (10, 25, 50, 100, then every 50), and an attendance streak (at least two classes a week, shown at 4, 8, 12, 26, and 52 weeks, then every 26).
- Session gains can be added to a share card. The option is off by default for each card.
- "Needs attention" on Today, in a full list, and on student detail: stalled progress, a course package running low or nearing expiry, and students who have not trained for 14 days and have no future appointment. Each item can be snoozed.
- Estimated one-rep max (1RM) trend for selected barbell exercises.
- Home screen and lock screen widgets for today's classes. Lock screen widgets omit student names.
- Live Activity for the session in progress, showing the exercise, set count, and rest countdown, without the student's name, weight, or reps.
- App Shortcuts: "Today", "Start training", and "Continue training". They require unlocking and only open pages.
- Exercise library expanded from 146 to 542 exercises from three sources: free-exercise-db, wger, and FineCoach originals. Per-entry sources and licenses are in `provenance.json`.
- The exercise library has 21 equipment icons and a "Recently trained" group.
- Exercise search by Chinese, full pinyin, pinyin initials, or alias.
- Empty-state scene with light animation on Today and Calendar. It pauses for Reduce Motion, Low Power Mode, and the background.
- About page in Settings with the version number and a link to the source code.

### Changed

- Training page simplified to a single confirm action per set.
- Interface copy rewritten in a plainer tone. Empty states now say what will appear.
- Rest countdown is kept per session and shows overtime.
- Training duration is shown in hours and minutes.
- Page headers are unified, with an inline back button.
- After sharing, the app returns to Today.
- System entries (widgets, Live Activity, Shortcuts) only open a session that already exists. They never create one.
- White launch screen.
- README rewritten around the main features, with design images.

### Fixed

- The rest bar no longer covers the Confirm button when the keyboard is up.
- Rest-end notifications now route to the right session, work after a cold start, and no longer cause a main-thread crash.

## 0.1.0 - 2026-10-11

Label added retroactively for the M1 and M2 milestones. These builds carried no version number.

### Added

- M1-A core session loop (accepted 2026-08-30):
  - students and student detail;
  - built-in, custom, and this-session-only exercises;
  - set logging for weight, reps, and duration;
  - automatic saving and recovery;
  - session summary, history, and editing;
  - share card with a preview and minimal disclosure;
  - encrypted backup and restore;
  - fully offline.
- M1-B coach operations (accepted 2026-10-03):
  - Today and a month calendar;
  - single and weekly recurring appointments, with overdue handling;
  - coach-only reminders without student names;
  - course packages with a credit ledger;
  - reusable training templates and session sections;
  - cardio entries;
  - body data;
  - training history filters, exercise trends, comparisons, and personal bests;
  - design system v1.0 and a Settings page.
- M2 personal training archive (accepted 2026-10-11):
  - the coach exports an encrypted, field-whitelisted snapshot for one student;
  - a separate read-only student view imports and browses it offline, with search and filters;
  - first-launch choice between the coach view and the student view.

[Unreleased]: https://github.com/ignacioli/FineCoach/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ignacioli/FineCoach/releases/tag/v0.2.0
