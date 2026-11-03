<!--
草稿，未提交到 App Store Connect。用于 TestFlight Beta App Review 和后续正式审核的「Notes」栏。
按钮文案取自 ios/FineCoachApp/Resources/Localizable.xcstrings（zh-Hans 是唯一语言）。入口依据：
- 首次启动二选一：Features/Students/Onboarding/FirstLaunchChoiceView.swift:20-46，App/AppRoot.swift:130-150
- 引导页：Localizable「onboarding.start / onboarding.skip / onboarding.sheet.*」
- 今日 / 学员切换：App/RootNavigation.swift:509-510
- 学员详情「开始训练」「导出个人训练档案」：Localizable「student.detail.startTraining」，StudentDetailView.swift:364
- 训练中「添加动作」「确认」「结束训练」：Localizable「session.action.addExercise / session.action.confirmSet / session.finish.title」
- 设置入口（今日、学员标题行上的齿轮）：SettingsView.swift:3-6
第 3 步的点击顺序是按文案和入口代码整理的，提交前需要在一台干净的设备上走一遍确认（人工走查，非截图循环）。
学员视图的演示档案方案取决于决策 D7（testflight-readiness.md）。
-->

# App Review Notes (draft)

**No account and no sign-in.** FineCoach (精练教练) is a training logbook for personal trainers. All data stays on the device. There is no server, no network request, no third-party SDK and no analytics. The UI is Simplified Chinese only; the Chinese labels to tap are given below in 「」 with an English gloss.

## 1. First launch: choose a mode

The first screen asks 「打算怎样使用精练教练？」 ("How will you use FineCoach?") and offers two **mutually exclusive** modes:

- 「Coach 使用」 (Use as coach): the full app. **Please choose this one to review the app.**
- 「导入个人训练档案」 (Import a personal training archive): a read-only viewer for a student. It requires a password-protected `.fcarchive` file exported by a coach (see §4).

As the screen says, the two modes cannot be switched directly later. Choosing 「Coach 使用」 does not lock the mode yet: it is fixed only when the first student is added or the onboarding is skipped.

## 2. Coach onboarding

1. Tap 「Coach 使用」.
2. On 「欢迎使用精练教练」 (Welcome), tap 「添加第一位学员」 (Add first student). You can also tap 「稍后再添加」 (Add later).
3. Enter any name in 「姓名」 (Name), e.g. "Test", and tap 「保存学员」 (Save student). All other fields are optional.

## 3. Main flow: record a training session

1. At the top, switch between 「今日」 (Today) and 「学员」 (Students). Open 「学员」 and tap the student.
2. On the student page, tap 「开始训练」 (Start training).
3. Tap 「添加动作」 (Add exercise) and pick any exercise from the built-in library.
4. Enter a weight and reps for a set, then tap 「确认」 (Confirm).
5. Tap 「结束训练」 (Finish training) to save the session as completed.
6. Back on the student page, you can view history, trends and body data, and tap 「导出个人训练档案」 (Export personal training archive) to create an encrypted file for the student.

Other areas: calendar and appointments, course packages, templates, and 「设置」 (Settings, gear icon on the Today and Students title rows), which contains 「备份与恢复」 (Backup & Restore) and 「关于」 (About).

## 4. Student viewer mode (optional)

Viewer mode only opens an archive exported in §3 step 6, so it needs a second install or a second device.
〔D7 待定：if a fictional demo archive is provided, put the attachment or link and its password here. The archive must contain only fictional data.〕

## 5. Permissions

- The app asks for **notification** permission only when a course reminder is turned on. Notifications are scheduled locally on the device.
- It requests no other permission: no camera, photos, contacts, location, health or tracking.

## 6. Data and privacy

- Student profiles may include body measurements and injury notes entered by the coach. These stay in the app's local storage on the device. They are excluded from device backups, and HealthKit is not used.
- Data leaves the device only when the user explicitly shares a password-encrypted backup or archive file, or a training report image, through the iOS share sheet or Files.
- Privacy policy: 〔URL，待 D4〕
- Source code: https://github.com/ignacioli/FineCoach
