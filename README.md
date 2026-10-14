<p align="center">
  <img src="design/design-system/assets/app-icon-light.png" width="120" alt="FineCoach">
</p>

<h1 align="center">FineCoach</h1>
<p align="center">精练教练</p>

<p align="center">A local class recorder for a personal trainer.<br>The records stay on this iPhone.</p>

<p align="center"><a href="README.zh.md">中文</a></p>

FineCoach is a native iPhone app for one-to-one gym sessions. The same app has two views. The coach view schedules classes, logs sets, reviews progress, and hands over a training card or an encrypted archive. The student view opens that archive read-only. There is no account, no server, and no telemetry. Logging, history, scheduling, and report generation all work in airplane mode.

---

## Between sets, one rest is enough

During a session the coach logs weight, reps, and duration as they were actually performed, including left and right sides when needed, plus a dedicated cardio entry. Numbers copied from the previous set, or from the last time this exercise was done, stay pending until the coach edits or confirms them. An empty session cannot be stored as a completed record.

Only one session can be in progress. An exercise can come from the built-in library, from the coach's own list, or be marked for this session only. A this-session exercise stays inside that class and does not slip into the library.

<p align="center">
  <img src="design/m1-b-hifi/screens/30-training-v2.png" width="280" alt="Training record">
</p>

## Confirmed sets survive a closed app

Every meaningful edit is written automatically. After backgrounding, a force-quit, or a restart, confirmed sets and unfinished drafts both come back. Drafts still do not count. If a save fails, the screen keeps the error and a retry. It does not say "Saved", and the session cannot be marked complete.

## A class on the calendar is not a class that happened

Today gathers the session in progress, overdue classes still waiting, the next class, and the rest of the day's schedule. A month calendar opens any date. A class can be a single appointment or a weekly series that ends on a date or after a set number of repeats. Editing one occurrence can change only that day, or that day and everything after it.

A class that passes its time and is still untouched stays overdue until the coach starts it, reschedules it, cancels it, or marks the student absent. Reminders go only to the coach. The lock screen shows a generic training reminder and a time, never the student's name.

## Credits have a ledger. Money does not enter the app

A student has at most one active course package. The package stores remaining credits and an end date. A completed class linked to an appointment is charged at most once. A cancellation is not charged. An absence is the coach's decision. A walk-in session asks at the end. An expired package or an empty balance does not block logging, and the balance does not go negative on its own.

Every charge, return, and manual correction leaves a trace. Reopening a completed, already-charged session returns that charge. Finishing or editing again does not charge twice, and does not return twice.

## Progress uses one ruler

History can be filtered by date, training focus, and exercise. Only records for the same student with a compatible focus are compared together. Exercise trends use a compatible scale for weight, reps, duration, and volume. On an assisted machine, a lower counterweight is progress, and it is not ranked on the same list as added load. A personal best follows a rule that can be stated: heaviest weight, most reps at the same weight, or longest duration. There is no estimated one-rep max, and no single score standing in for judgment.

Body data can be left entirely empty. Height, weight, body fat, and common girths are built in, and the coach can add their own measures. One entry per measure per day. Switching kilograms and pounds changes the display and leaves stored numbers alone.

## What the student receives, the coach sees first

A share card is a read-only image the coach generates from one completed session. The final preview comes first. Each card starts from the smallest disclosure. Options opened last time do not carry over.

Sex, body data, injuries, private notes, phone numbers, and WeChat IDs never enter the card. There is no switch that unlocks them. The filename does not carry the student's identity. Delivery uses the system share sheet. Cancel and failure are not recorded as "sent". A picture that has already left through the system cannot be edited by this app, and the app does not pretend it can be recalled.

<p align="center">
  <img src="design/m1-b-hifi/screens/29-share-preview.png" width="280" alt="Share card preview">
</p>

## A coach view, and a student's read-only view

The first launch asks, "How do you want to use FineCoach?" The two entries are mutually exclusive. The screen says they cannot be switched directly afterwards.

**Coach use** opens the coach view: "Manage students, record training." Scheduling, set logging, history, course packages, share cards, and archive export live here.

**Import a personal training archive** opens the student view: "Read the archive your coach gave you." This view only opens the encrypted snapshot the coach handed over.

Once that choice is in use, the installation stays on the current view. The app has no control that jumps between the two. Import is blocked while coach records are already on the phone, so the two sets of data stay apart. The student view cannot log a coach's classes.

<p align="center">
  <img src="design/m2-hifi/screens/M2-07-first-launch-choice.png" width="280" alt="First launch: Coach use, or import a personal training archive">
</p>

A coach exports an archive from the coach view, for one student: a complete snapshot of one moment, not a live sync. Before export, each part can be kept or removed, and the actual text is visible. Injuries, private notes, course packages, appointments, and contact details are never in the archive. The password is at least 8 characters. The app does not store it, upload it, or recover it. The filename does not include the student's name.

The student view browses offline: training records, included body data, trends, and exercise information. Search and filters work. Display units on that phone can change. Editing, adding a session, and generating a share card do not. An update is accepted only when it is a newer complete snapshot from the same source and the same student. It replaces the whole archive. It does not merge row by row. If the new file cannot replace the old one, the old archive stays intact.

<p align="center">
  <img src="design/m2-hifi/screens/M2-11-viewer-home.png" width="280" alt="Personal training archive">
</p>

## Backup starts when the coach starts it

A full backup is exported by the coach, with a password the app does not remember. Restore checks the password, integrity, and compatibility before it replaces the current data. A wrong password, a damaged file, or an incompatible version leaves the phone's data as it was.

## The exercise library names its source

The built-in library has 146 exercises from [wger](https://wger.de), used under CC-BY-SA and attributed in the archive's exercise information. Each exercise has a Chinese name, muscle groups, and equipment. The coach can favorite, hide, or copy one into their own list. This version includes no exercise photos, GIFs, or video.

---

## The edge of this version

- Simplified Chinese, iPhone portrait, light interface.
- iOS 18 and later. The implementation is native Swift and SwiftUI, with Core Data on the device.
- One coach, one phone, one student at a time. A small studio means each coach's own phone. The coach view and the student's read-only view are one choice per installation, and they cannot be switched directly afterwards.
- Android, iPad, Apple Watch, dark mode, group classes, payments, cloud sync, and in-app booking or chat are outside this version.

## Build

Open `ios/FineCoach.xcodeproj` in Xcode and select the `FineCoach` scheme. The project uses Apple frameworks only.

A simulator result and a physical-device result are two different facts. The acceptance record and the known gaps are in `ios/VALIDATION.md`.

## License

[MIT](LICENSE). Copyright (c) 2026 Ignacio Li.

The built-in exercise data keeps the license named above. The repository's MIT license does not replace it.
