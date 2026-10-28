# 阶段 F 系统级入口：设计改动与实施映射

> 状态：**Phase 1 完成（2026-10-27）：空扩展 target + App Group，主机门禁全绿，真机签名通过（§4.1）。**画稿 F-a、F-b、F-c 未起草。本文是 `components.md` §6 要求的里程碑实施映射，不重复 token 数值。
> 行为权威：`specs/006-stage-f-system-entry/spec.md`（`1.0-approved`）、`plan.md`、`tasks.md`、`research.md`、`data-model.md`。字段白名单只认 spec §2.2。视觉权威：`design/design-system/README.md`（§8「系统入口」、§10 C28）、`components.md`。
> 分支：本文件在设计文档分支 `topic/docs-stage-f-system-entry-590290`；代码在实现分支 `feature/stage-f-system-entry`（worktree `.worktrees/stage-f-system-entry`）。

## 1. 按设计变化分类（`components.md` §1.2）

见 spec §7.1。画稿批准后在这里补每个组件的 anatomy 指针。

## 2. 页面组合

（F-a、F-b、F-c 批准后填写。）

## 3. 画稿与文案

| 画稿 | 内容 | 状态 |
|---|---|---|
| F-a | 锁屏矩形 / 单行，主屏小 / 中号（含 StandBy 锁着打码、空态、占位） | 未起草 |
| F-b | Live Activity 锁屏 + 灵动岛紧凑 / 最小 / 展开（休息中、已超时） | 未起草 |
| F-c | 设置页说明行（spec F-FR-040） | 未起草 |

## 4. 执行记录

| 日期 | 阶段 / 任务 | 提交 | 闸门结果 | 备注 |
|---|---|---|---|---|
| 2026-10-27 | 建实现 worktree，分支 `feature/stage-f-system-entry`（基于 main `29ee636`）；T001 本文件 | — | — | — |
| 2026-10-27 | T002、T003：空壳扩展 `FineCoachWidgets`（占位小组件，只显示固定文字，不读数据）、App Group `group.com.finecoach.app`、`NSSupportsLiveActivities`；`SystemEntryConfigurationTests`。修正：`CapabilityManifestTests` 改为只放行这一个 App Group，import 扫描扩到 `FineCoachWidgets/`（负责人 2026-10-27 批准） | 未提交 | 主机 `gate.sh`：lint、Debug / Release 真机构建、build-for-testing 均 0；Unit 611（1 skip，既有）0 失败；Integration 212 0 失败；`FineCoach.app/PlugIns/FineCoachWidgets.appex` 存在。门禁构建关闭签名，签名能力看 §4.1 | Codex gpt-6.1-sol 两轮；无新 UI（占位小组件 US1 时替换） |

### 4.1 真机证据

| 项 | 来源 | 结果 |
|---|---|---|
| 签名：带 App Group 的 Debug 版能装上并运行 | research R6，tasks T004 | **通过**（2026-10-27，iPhone XS Max）：自动签名（个人团队，描述文件 7 天，至 2026-11-04）为 App 与扩展签入 `group.com.finecoach.app`；首次启动需在手机上重新信任开发者；负责人确认 App 能打开，占位小组件能加到锁屏（矩形）与主屏（小号）。构建日志 `.handoff/logs/2026-10-27-stage-f-phase1-device-build.log` |
| 小组件锁着打码（各形态、StandBy、VoiceOver） | research R1，tasks T018 | 未取得 |
| Live Activity 出现 / 更新 / 结束、划掉后倒计时、残留清理 | research R4，tasks T026 | 未取得 |
| 快捷指令锁着先要求解锁、不朗读 | research R5，tasks T030 | 未取得 |

## 5. 入口与布局清单（`components.md` §1.4）

画面 → 可见控件 → identifier → 改数据？→ 撑满宽度的组件 / 容器。本阶段所有新入口都是跳转、不改数据。

（各故事完成时填写。）
