# S1 明文 seed fixture

唯一数据文件：[s1-seed.json](../../app/src/debug/assets/seed/s1-seed.json)。仅位于 `src/debug/assets/seed/`；Release 不包含此 asset、parser 或 seed 入口。当前 **seedVersion=3**，dataset=`fictional-s1-coach-core-v3`；初始 rows：**multi 1149 / single 1138 / empty 1088**，与 v2 相同。

虚构数据风格参考 `ios/FineCoachApp/Core/Platform/ArchiveExportDebugSeed.swift`，只借用姓名与训练内容风格。所有信息为合成数据，不放真实身份、身体测量、Appointment、分享报告或导出内容；原生训练重量 `weightValue` 是组记录，不是身体数据。

## 字段说明

每条业务记录与嵌套记录都有 `scenario`，说明它覆盖 T019 的哪个场景。JSON 无注释语法，用此字段写解释。parser 拒绝未知字段，拼错字段或增加身体数据字段会失败，不会静默忽略。

| 位置 / 字段 | 含义与修改约定 |
|---|---|
| `declaration` / `source` | 保留 `fictional-data` 声明；记录 iOS 样例来源，不作为执行代码 |
| `seedVersion` / `dataset` | 正整数版本；dataset 必须为 `fictional-s1-coach-core-v版本`。内容变更时一并递增，防止旧安装误当作新数据 |
| `clockUTC` | 所有业务时间的固定 UTC 基点，ISO-8601 Instant |
| `uuidPrefix` / `generatedIDStart` | 固定 UUID 前缀、Repository/UseCase ID generator 起点；相同文件与 variant 产生可复现 ID。顺序变化可能改变后续生成 ID |
| `catalogCount` | 当前 bundled catalog 的持久行数（542，含 1 retired）；不是页面可选数量（541） |
| `expectedRows` | 三个 variant 的首次持久 inventory；含业务行及 5 个 seed metadata，不含 Room/framework 与 store generation/created_at |
| `scenarios[].key` | 安装 variant：`empty` / `single` / `multi`；各有中文 `scenario` 说明 |
| `variants` | 记录属于哪些安装 variant；业务记录目前使用 `single`、`multi`。`empty` 只加载 catalog，无学员/训练 |
| `students[]` | `id` 数字映射固定 UUID；`name`、`sex`、可选 `trainingGoal` / `injuryNotes` / `privateCoachNote` / `phone` / `wechatID`；`lifecycle` 为 active/archived。输入仍由 StudentDraft 和 Repository 校验 |
| `packages[]` | `key` 为 fixture 内引用名；`studentID` 引用学员；`name`、`totalCredits`、可空日期 `startDate`/`endDate`、初始 `state`、`confirmedReplacement`。按数组顺序调用真实创建用例，替换必须明确 true，旧包由用例结束；不直接改状态列 |
| `sessions[]` | `key`、`studentID`、`state`（inProgress/completed）、`trainingFocus`（BodyPart enum 数组）、分段、动作、组及可选 summary。按数组顺序创建；同一学员不能有两个进行中 Session |
| `sections[]` | `id`、`name`、`orderIndex`；owner 由所属 Session 或 Template 决定 |
| `exercises[]` | `id`、`sectionID`、`orderIndex`、`sourceKind`、`recordMode`、`sets`。builtIn 用 catalog `stableID` 或精确 `canonicalName` 引用；找不到、已 retired、mode 不符就失败。sessionOnly 使用显式 `canonicalName`，不自动替代内置动作 |
| `sets[]` | `id`、`orderIndex`、`state`（draft/pending/completed）、`unit`；可选十进制字符串 `weightValue`、`repetitionCount`、`durationSeconds`、`distanceValue`、`speedValue`、`resistanceValue`。先构造并校验 TrainingSet，再确认或复制为 pending；模板经 TemplatePlannedSet 转换 |
| `summary` | `publicSummary`（本地训练总结，不是分享内容）、`privateCoachNote`；只用于 completed Session |
| `ledger[]` | `kind=manualCorrection` 用 `packageKey`、`direction`、正整数 `amount`、`note`；`kind=adhocDebit` 用 `packageKey` / `sessionKey`。真实 Credit/Finish use case 生成事件键及自动流水，不在 JSON 伪造数据库行 |
| `templates[]` | `key`、`name`、`trainingFocus`、分段与动作计划组；与 Session 共用字段结构，保留真实 TemplateUseCases/Repository 校验 |
| `offsetSeconds` | 记录时间相对 `clockUTC` 的秒偏移；支持负数。学员/课包/ledger/模板操作、组创建与确认、summary 保存各自显式指定 |
| `startOffsetSeconds` / `finishOffsetSeconds` | Session 开始与完成时间。所有偏移均相对根时钟，不是相对 Session；改历史时间时同步调整其组和 summary 时间，保持领域时序有效 |

业务执行顺序为 students → packages → sessions/summary → ledger → templates。写入全部经过现有 Repository/UseCase；只有 seed metadata 使用 Room DAO。保留非 seed 库的只读 preflight 和 inventory SELECT；没有直接 SQL 写入。内置引用在首个业务写入前检查，失败由 shell instrumentation 输出 `status=failed`；不泄露缺失引用或业务内容。

## T019 场景对照

| 场景 | JSON 记录 / 可读样例 | variant |
|---|---|---|
| 同名、active、无课包 | 学员 1/2 同名周十节；1 无包 | single / multi |
| archived、恢复入口 | 学员 7 孙已归档 | single / multi |
| 长名字换行 | 学员 6 长名字张浩然样例 | single / multi |
| 可用、到期、耗尽、ended、替换历史 | packages 的 available / expired / exhausted / ended / replacement-old / replacement-new；exhaustion 手工扣减 | single / multi |
| 单/多进行中且互不覆盖 | sessions 的 active-first / active-second | single / multi（second 仅 multi） |
| completed / pending / draft、四种 mode | 每节 Session 的四个 exercises 与 sets | single / multi |
| completed 历史、总结与 ledger | history + summary + history-debit | single / multi |
| 分段模板、四 mode 计划组 | full-body；基础力量与核心 | single / multi |
| 空学员与空训练 | 无业务记录，仍同步 builtIn catalog | empty |

当前动作是 builtIn 杠铃平板卧推、俯卧撑、平板支撑；catalog 无 cardio mode，因此跑步机明确标为 sessionOnly。

## 改文件与重装

1. 直接修改 JSON 中的内容，保留全部 T019 场景与 `fictional-data` 声明。新增数组记录时附上 `scenario`，保证 ID、key 和引用不冲突。
2. 增加 `seedVersion`，同步 `dataset` 后缀。业务行数变化时修改同文件 `expectedRows`；值不符会拒绝 complete。仅改文案/组值/时间通常不改变行数。
3. 用共享宿主锁运行 `agent-test.sh S1DebugSeedTests S1SeedIsolationTests`。当前共享脚本含 `-q`，本轮按既有要求在执行流过滤，不修改共享脚本；日志与数量必须非空。另可运行 `./gradlew --offline :app:s0SeedIsolation` 检查实际 Release APK。
4. **宿主**在确认目标是专用虚构设备后自行卸载旧版本 seed，再安装。agent 不卸载、不清库；已有普通库、旧版本、不同 variant 或 incomplete marker 都会被拒绝。相同版本重装只校验既有 inventory，保留走查修改，不覆盖数据。

从 `android/`，按 README 配置 JDK21/SDK/cache 后：

```sh
./gradlew --offline :app:s0InstallSeededDebug -Pandroid.device="<SERIAL>" -Ps1.seedScenario=multi
```

只有一个指定且已授权的设备可连接；改为 `single` / `empty` 需要另一份全新数据目录。当前 multi 成功输出 `SEED version=3 rows=1149 status=ok`。安装失败不代表数据已回滚到空库，交宿主处理，不自动 reset。

## 计数与隔离同步位置

- **数据 authority**：JSON 的 `expectedRows` / `seedVersion` / `dataset`；loader、JVM inventory 断言和 `s0InstallSeededDebug` 均读取它，后续改数据不必改 Kotlin 文案或 Gradle 版本/行数常量。
- **测试方法数量**：新增/删除测试方法时更新 `app/build.gradle.kts` 的 `s1SeedChecks.expected`（目前 S1DebugSeedTests **12**、S1SeedIsolationTests **4**），及 README 的预期；修改 fixture 内容本身不应改变 suite 数量。
- **说明与交付**：行数/版本变化时更新 README T019、walkthrough 当前安装预期和本文件；历史 T019/T020 结果保留版本标记，不冒充当前证据。
- **Release guard**：新增 parser/seed 类或文件名时补 `s0SeedIsolation.forbidden`。当前保留 v1/v2，新增 v3、S1SeedFixture、`seed/s1-seed.json`；原有 seed 路径与二进制内容扫描不放宽。

## 本轮验证

实际结果（2026-11-09）：

| 检查 | 实测 | 日志（根为 /Users/liyongqiang/gitrepo/ignacioli/FineCoach/.handoff/logs/） |
|---|---|---|
| S1DebugSeedTests | 12 tests，0 failures/errors/skips；含三个 variant 持久验证、新增解析/场景覆盖、无身体字段、内置引用缺失失败 | agent-test-android-s1-walk1-20261109-065009.log |
| S1SeedIsolationTests | 4 tests，0 failures/errors/skips | 同上 |
| FictionalDataPolicyTests | 16 tests，0 failures/errors/skips | 同上 |
| RoomSkeletonTests | 5 tests，0 failures/errors/skips；metadata DAO update 不改变 schema | agent-test-android-s1-walk1-20261109-064735.log |
| s0SeedIsolation | PASS；再次执行 seed 12 + isolation 4，全部 0 failures/errors/skips；实际 Release APK entry/dex/resources 全部扫描通过 | agent-test-android-s1-walk1-20261109-065354.log |

上述日志均非空。最终 coverage 断言要求保留 T019 场景，不固定学员总数或要求每条新增历史都带四种 mode，便于继续编辑 fixture。Release gate 在此调整后复跑 16/0。Release APK SHA-256：

```text
701730cba87da6dd2e1a92fcee542f177ba757c1943d4ad19f75748c83270809
```

定向测试与 Release gate 均保留原共享 runner 的 host.lock。定向测试沿用上一轮仅过滤 -q 的执行流；Release 检查在临时 runner 副本中把任务替换为 :app:s0SeedIsolation、XML 路径替换为 s1SeedChecks，未修改共享脚本。XML 快照在日志根 s1-seed-fixture-20261109/jvm/ 与 release/。

失败记录保留：064652 日志为新增 Gradle Map<*, *> 取值编译错误，0 tests；064735 总计 37 tests / 1 failure，seed、isolation、Room 全通过，唯一失败是上一轮 ResourceHubScreen.kt 位于 resources 目录，被既有 fixture 扫描规则识别但缺 fictional-data 声明。本轮补充“仅通用界面文案、无个人/seed 数据”的声明，未放宽扫描规则；复跑 32/0。fixture 数据本身无失败，未删除/skip 用例。

git diff --check 通过。API36 安装、真机、人工体验与独立复核仍 PENDING；JVM 和 Release 隔离不能替代这些结果。仍不 stage/commit，不修改 iOS 产品代码。
