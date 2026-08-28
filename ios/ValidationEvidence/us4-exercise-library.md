# US4 动作库与稳定身份证据

记录日期：2026-08-28

范围：T066–T077（使用稳定身份的动作库）。未启动 T078。

工具链：Xcode 26.6（Build 17F113），Apple Swift 6.3.3。

## 代码门槛

- 名称先 trim + NFC；活动 Built-in、活动 Custom 与当前 Session 新建动作共用统一 claim，冲突返回 `DomainError.conflict` 且不静默改名。
- Built-in 核心定义不可直接修改；本地 alias/收藏/隐藏只影响呈现，不改稳定 ID。Custom 保存后 ID 稳定，归档释放 claim，恢复时重新占用。
- Session-only 无 `ExerciseCatalogMO` 行，只存在于所属 Session 快照；结束/放弃后释放 `currentSession` claim。
- 课中快速创建必须明确选择「仅本次」或「保存到动作库」。前者保持 `activeSession.saveExercise`，US2/US3 UI 标识不变。
- 可分发构建：来源 manifest 缺字段、禁止再分发、或 `isFictionalPlaceholder == true` 均不得通过 distributable gate。开发/测试仅使用虚构确定性 catalog（占位深蹲 / 占位引体 / 占位支撑），不加入未核验真实内容。

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
- UI：搜索占位深蹲、收藏/隐藏/显示已隐藏；Custom 归档后可再用同名；课中「仅本次」杠铃深蹲仍可用，「保存到动作库」课中自定义A 进入库，与占位深蹲冲突时明确提示且不改名；仅本次动作不出现在动作库搜索。

`swift-format lint --strict` 已在本轮 US4 相关源码上执行通过。

## 实体设备

未在本轮对 US4 做实体设备回归。真实 100–150 条 Built-in 内容仍受来源/许可/专业评审阻塞。

## 未验证

- 未做人工 VoiceOver 朗读走查。
- 未把 4 个动作库 UI 修复后再跑一遍完整 FineCoachUITests 套件（US1–US3 回归证据来自修复前的全量，当时仅动作库 4 条失败）。
- 未启动 T078 或任何 User Story 5 任务。
