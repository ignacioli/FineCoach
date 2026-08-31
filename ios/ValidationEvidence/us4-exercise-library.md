# US4 动作库与稳定身份证据

记录日期：2026-08-28

范围：T066–T077（使用稳定身份的动作库）。未启动 T078。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- 名称先 trim + NFC；活动 Built-in、活动 Custom 与当前 Session 新建动作共用统一 claim，冲突返回 `DomainError.conflict` 且不静默改名。
- Built-in 核心定义不可直接修改；本地 alias/收藏/隐藏只影响呈现，不改稳定 ID。Custom 保存后 ID 稳定，归档释放 claim，恢复时重新占用。
- Session-only 无 `ExerciseCatalogMO` 行，只存在于所属 Session 快照；结束/放弃后释放 `currentSession` claim。
- 课中快速创建必须明确选择「仅本次」或「保存到动作库」。前者保持 `activeSession.saveExercise`，US2/US3 UI 标识不变。
- 可分发构建：来源 manifest 缺字段、禁止再分发、或 `isFictionalPlaceholder == true` 均不得通过 distributable gate。T120 已用 wger 文字库（146 条，`provenance.json`）替换虚构占位 catalog；Release 不得回退到占位深蹲/引体/支撑。

## Simulator 回归

设备：iPhone 17，iOS 26.5。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests | `/tmp/FineCoachDD-US4-Unit/Logs/Test/Test-FineCoachTests-2026.08.28_08-31-16--0700.xcresult` | 38/38 通过（含身份 6 + 来源 5；US1–US3 回归仍绿） |
| FineCoachIntegrationTests | `/tmp/FineCoachDD-US4-Int/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_08-32-20--0700.xcresult` | 31/31 通过（含动作库持久化 4；US2 ActiveSession 6 + US3 投影 6 回归） |
| FineCoachUITests（US1–US3 回归） | `/tmp/FineCoachDD-US4-UI/Logs/Test/Test-FineCoachUITests-2026.08.28_08-32-56--0700.xcresult` | US1 4 + US2 CoreTraining 4 + smoke 1 + US3 matrix 3 通过；当时 4 个动作库用例因 accessibility 容器折叠失败 |
| FineCoachUITests（动作库） | `/tmp/FineCoachDD-US4-UI4/Logs/Test/Test-FineCoachUITests-2026.08.28_08-55-57--0700.xcresult` | 4/4 通过 |

动作库覆盖：

- 身份：NFC/trim、跨 scope 统一冲突、归档与 Session 结束释放 claim、Custom 改名保持稳定 ID、Built-in 拒绝 `updatingCustom`、相同 owner 再占用幂等。
- 来源：缺字段失败；禁止再分发使 distributable 失败、developmentPlaceholder 可通过；占位 catalog 不得当作可分发内容；损坏 JSON 抛 `incompatibleInput`。
- 持久化：Built-in/Custom/偏好重启后仍在；Session-only 不写 catalog；归档后名称可复用；默认搜索省略隐藏项。
- UI：搜索杠铃深蹲、收藏/隐藏/显示已隐藏；Custom 归档后可再用同名；课中「仅本次」杠铃深蹲仍可用，「保存到动作库」课中自定义A 进入库，与杠铃深蹲冲突时明确提示且不改名；仅本次动作不出现在动作库搜索。
## 浏览补丁（FR-013A，2026-08-30）

默认按主部位分段平铺动作名（M1-A 100–150 条全部展开）；部位与器械芯片筛选；Custom 单独成组。Simulator：FineCoachTests 身份+来源通过；FineCoachIntegrationTests 动作库持久化通过；FineCoachUITests `ExerciseLibraryUITests` 5/5 通过（含 `testBrowseByMuscleEquipmentAndCustomSection`）。未做实体机复跑。

`swift-format lint --strict` 已在本轮 US4 相关源码上执行通过。

## 实体设备

- 设备：iPhone XS Max（iPhone11,6），iOS 18.7.10，id `00008020-000C5D2C3ED3002E`。屏幕解锁、保持常亮。前两次 UI 因 `Timed out while enabling automation mode` 未能启动；解锁并允许自动化后第三次跑通。
- FineCoachTests：38/38 通过（`/tmp/FineCoachDD-Device-Unit/Logs/Test/Test-FineCoachTests-2026.08.28_09-06-14--0700.xcresult`）。命令行覆盖 `DEVELOPMENT_TEAM=9Z7427RG9X`，未改 pbxproj。
- FineCoachIntegrationTests：31/31 通过（`/tmp/FineCoachDD-Device-Int/Logs/Test/Test-FineCoachIntegrationTests-2026.08.28_09-06-37--0700.xcresult`）。
- FineCoachUITests：18/18 通过（`/tmp/FineCoachDD-Device-UI3/Logs/Test/Test-FineCoachUITests-2026.08.28_09-17-23--0700.xcresult`），含 US1 4 + US2 CoreTraining 4 + US3 recovery 5 + US4 library 4 + smoke 1。
- 这不是 Data Protection 专项证据。当时真实 100–150 条 Built-in 内容仍受来源/许可评审阻塞。

## T120 内置文字库（2026-08-30）

产品 catalog review 通过后，用 wger 文字库 146 条替换虚构占位 catalog。稳定 ID 为 wger UUID；`provenance.json` 含来源/作者/许可/版本、记录模式、中文名。课中输入已有内置名时从匹配列表选取该条，而不是再建仅本次同名动作。GIF/视频未打包。

## 浏览补丁（FR-013A，2026-08-30）

默认按主部位分段平铺动作名（M1-A 100–150 条全部展开）；部位与器械芯片筛选；Custom 单独成组。部位/器械按稳定 ID 从包内 catalog 叠加，不写入 `ExerciseCatalogMO`。

### Simulator

- FineCoachTests：`ExerciseIdentityTests` + `ExerciseProvenanceTests` 通过（`/tmp/FineCoachDD-LibBrowse-Unit`）。
- FineCoachIntegrationTests：`ExercisePersistenceTests` 通过（`/tmp/FineCoachDD-LibBrowse-Int`）。
- FineCoachUITests：`ExerciseLibraryUITests` 5/5 通过（`/tmp/FineCoachDD-LibBrowse-UI`，含 `testBrowseByMuscleEquipmentAndCustomSection`）。

### 实体设备

设备：iPhone XS Max / iOS 18.7.10，id `00008020-000C5D2C3ED3002E`。屏幕需亮着；首次 UI 因 `Timed out while enabling automation mode` 失败，唤醒 Settings 后复跑通过。

| 套件 | 结果包 | 结果 |
| --- | --- | --- |
| FineCoachTests（身份+来源） | `/tmp/FineCoach-LibBrowse-Device-Unit.xcresult` | 通过 |
| FineCoachIntegrationTests（`ExercisePersistenceTests`） | `/tmp/FineCoach-LibBrowse-Device-Int.xcresult` | 通过 |
| FineCoachUITests（`ExerciseLibraryUITests` 5） | `/tmp/FineCoach-LibBrowse-Device-UI2.xcresult` | 5/5 通过 |

命令（从仓库根）：

```sh
xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachTests \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=9Z7427RG9X CODE_SIGN_STYLE=Automatic \
  -only-testing:FineCoachTests/ExerciseIdentityTests \
  -only-testing:FineCoachTests/ExerciseProvenanceTests \
  -derivedDataPath /tmp/FineCoachDD-LibBrowse-Device-Unit \
  -resultBundlePath /tmp/FineCoach-LibBrowse-Device-Unit.xcresult

xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachIntegrationTests \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates \
  -only-testing:FineCoachIntegrationTests/ExercisePersistenceTests \
  -derivedDataPath /tmp/FineCoachDD-LibBrowse-Device-Int \
  -resultBundlePath /tmp/FineCoach-LibBrowse-Device-Int.xcresult

xcodebuild test -project ios/FineCoach.xcodeproj -scheme FineCoachUITests \
  -destination 'platform=iOS,id=00008020-000C5D2C3ED3002E' \
  -allowProvisioningUpdates \
  -only-testing:FineCoachUITests/ExerciseLibraryUITests \
  -derivedDataPath /tmp/FineCoachDD-LibBrowse-Device-UI2 \
  -resultBundlePath /tmp/FineCoach-LibBrowse-Device-UI2.xcresult
```

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未启动 T078 或任何 User Story 5 任务。
