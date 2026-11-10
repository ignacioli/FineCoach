# S0 恢复第 3 步：S1 组件与 AD-01 回写

工作树：`android-s1-comp`；分支：`feat/android-s1-components`；起点：`e6058e4`。单写者，不提交、不推送；宿主负责提交。开工审计 `git status --short`、`git diff --stat` 均为空（tracked/staged/untracked 均无现有变更）；worktree gate PASS。

## 组件状态与证据

以下测试方法均在 `S1ComponentTests`（未特别注明时），catalog 在独立 `S1CatalogEntries`。状态以实现/自动检查为限，未表示负责人视觉验收。

| 组件 | anatomy | 文件:行 | 测试 | 分类与范围 | 状态 |
|---|---|---|---|---|---|
| DS-AMBIENT-SCENE | components.md §4.9 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcAmbientScene.kt:82` | ambientScene + S1CatalogStateTests(today/calendar) | C，feature-local 原样迁移，新增 size 参数；四层/纯帧算法保留 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-SET-ROW | components.md §4.3 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcSetRow.kt:22` | setRow + S1CatalogStateTests(5 states) | C，既有实现正式登记；D，补组行合并语义和可访问自定义操作 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-HERO-CARD | components.md §4.4 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcHeroCard.kt:27` | heroAndHint + 既有 heroCard/multiHeroCard | C，复用既有单人/多人组件；不重写 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-HINT-BAR | components.md §4.4 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcHintBar.kt:22` | heroAndHint + 既有 hintBar | C，复用信息/继续两态；不重写 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-EQUIPMENT-ICON | components.md §4.5 / README §7.1 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcEquipmentIcon.kt:15` | equipmentIcons + S1ComponentAssetTests + 21 catalog states | C，移植批准 lookup；D，三处页面补位，无映射留空 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-PAGE-PRIMARY | components.md §4.6 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcPages.kt:19` | primaryPage + S1CatalogStateTests(coach/viewer) | C，正式抽取组合；今日/学员复用 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-PAGE-SECONDARY | components.md §4.6 / 4.7 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcPages.kt:36` | secondaryPage + PlatformShellTests | C，组合既有 shell/header；资料库接入，Insets 只消费一次 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-EMPTY-STATE | components.md §4.6 / 4.9 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcPages.kt:47` | emptyState + S1CatalogStateTests(static/ambient) | C，今日与学员空态迁移；D，底部主按钮按 space.8 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |
| DS-LAUNCH | components.md §4.6 / README C31 | `android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcPages.kt:65` | launch + S1ComponentAssetTests.launchThemeIsWhiteAndHasNoVisibleIconOrAnimation | D，纯白系统启动与加载面；配置/资源证明不等于真机运行证明 | 完成（本轮自动门禁 PASS；未作人工视觉验收） |

## 变化登记（当前 → 目标）

| 位置 | 当前 | 目标 | 理由 | 处理 |
|---|---|---|---|---|
| TodayAmbientScene.kt | feature-local、固定 220 | FcAmbientScene，调用方尺寸 220/160 | §4.9 共享 anatomy | 迁移，删除旧实现文件；算法保留 |
| FcSetRow / catalog | 已实现但名单延期，icon 校验有特判 | 正式注册，去掉特判 | 不把延期当实现证明 | 改变 |
| FcHeroCard / FcHintBar | §8.1 已登记且在 designsystem | 保留实现，增加独立测试 | 避免重写 | 刻意保留 |
| FcRows / 动作库与选择器 | 没有收藏星，leading 未填充 | action.primary 器材/收藏星 → disclosure | README §8.1 / C′2b | 增加可选 slot，普通行默认关闭 |
| SessionChrome / HistoryRecordCard | 动作标题缺器材图标 | 使用 sourceID 对应 catalog facet | P0-a2 / 35 | 改变，名称快照仍保留 |
| 动作筛选 | filter_list，筛选前后同图 | filter_alt / filter_alt FILL=1，300 | 批准 AD-01 / S1-D28 | 替换当前引用；旧未引用资产保留 |
| 状态徽标 | info（含圆） | info_i，600 | 外层已有状态圆 | 替换当前引用；旧未引用资产保留 |
| 资料库模板入口 | null | list_alt，300 | 批准 AD-01 | 替换 |
| 左滑移入 / 动作完成标签 | 缺 folder / 缺完成标签图标 | folder / check_circle FILL=1，400 | 批准 AD-01 | 增加装饰图标、完成文字，保留已有动作入口 |
| 启动 theme / S1Root | 默认系统启动主题 / 空平台壳 | 白底透明图标、0 动画 / FcLaunch | C31 | 替换；错误后原重试入口保留 |
| 一级页 | feature 各自拼装标题和分段 | FcPagePrimary：分段 → 标题 → 内容 | §4.6 的书面 anatomy | 改变；01/21 历史导出图是标题在前，本轮以指定 §4.6 为结构依据，差异显式记录 |
| §8.2 | S1 ID 延期（HERO/HINT 已移出） | 31 个正式 ID + 2 个 S2+ 延期 ID | 实际全集 33；不补造第三个 S2+ | 移出本轮 ID；CALENDAR-DAY/BODY-DIAGRAM 保留 |

## 资产链

- Material Symbols：固定 commit `10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7`，19 项，新增/替换的 SVG 从 upstream 获取；`convert-material-symbols.mjs` 验证输入摘要并保留 path。`material-symbols-provenance.json` 记录每项实际 upstreamPath、weight、fill、输入/输出 SHA-256；manifest / SHA256SUMS / SOURCE 同步。Apache License 2.0 与 APK NOTICE 原样保留。
- 器材：`design/m1-b-hifi/icons/*.svg` 共 21 个产品自有素材。`convert-equipment-icons.mjs` 校验形状子集，展开 group 继承，保留路径、24 viewport、2px round cap/join；只有 kettlebell 铃身填充。`equipment-manifest.txt`、`equipment-provenance.json`、`equipment-SHA256SUMS` 记录来源与输出。不套用 Material 的第三方许可。
- 图标装饰性隐藏；名称由同行动作/状态文字承担。自定义动作无 catalog facet 时不显示；固定器械臂/核心和其他类不猜测 fallback。

## 五行执行记录

分类与依据：C 类共享映射/迁移 + D 类批准设计偏差修复；目标设计不变，AD-01 沿用 Penpot「M1-B G5 Design → Android 差异 → AD-01 图标映射」负责人批准（S1-D28），不重新设计/改画板。
影响范围：本轮九组件、DS-LIST-ROW 收藏 slot、指定 feature 回填、独立 debug catalog；iOS、port/schema/repository、S2+、截图基线未改。
设计决定：复用 §4 anatomy / README token / C31 / D23–29；G2 四类计数保持 27/66/6/5。延期表实际只剩两个 S2+ ID，书面一级页顺序与历史导出图差异如上。
实施与验证：独立 S1 组件/资产/catalog 测试；entry/layout 追加到 implementation-map；一次性只读批准画稿，无生成截图/比较修复循环。L3 人工视觉验收未执行，本轮不作已视觉验收声明。
结果：PASS，指定 13 个测试类共 250 tests，0 failures/errors/skips；新增 S1 共 47 tests，G2 固定计数 27/66/6/5 保持。先前 Canvas size 遮蔽、DpRect.width import 编译失败及 4 个运行失败均已针对性修复，旧日志保留；训练模板旧 null 源码断言改为精确 list_alt 断言，未放宽验证。

## 验证与未完成项

`agent-test.sh` 最终 exit=0，完整 stdout 经 tee 保存至 `.handoff/logs/S0-step3-components-test-summary.log`；Gradle 原始输出 `.handoff/logs/agent-test-android-s1-comp-20261110-130222.log`（-q 成功时为空）。

| 测试类 | tests | failures/errors/skips |
|---|---:|---|
| S1ComponentTests | 9 | 0/0/0 |
| S1ComponentAssetTests | 3 | 0/0/0 |
| S1CatalogStateTests | 35 | 0/0/0 |
| ComponentContractTests | 27 | 0/0/0 |
| ComponentCatalogTests | 6 | 0/0/0 |
| ComponentCatalogStateTests | 66 | 0/0/0 |
| PlatformShellTests | 5 | 0/0/0 |
| TokenParityTests | 6 | 0/0/0 |
| ActiveSessionEntryLayoutTests | 20 | 0/0/0 |
| HistoryEntryLayoutTests | 9 | 0/0/0 |
| ExerciseTemplateEntryLayoutTests | 33 | 0/0/0 |
| TodayNavigationEntryLayoutTests | 13 | 0/0/0 |
| StudentEntryLayoutTests | 18 | 0/0/0 |

- 早期失败证据：`agent-test-android-s1-comp-20261110-125916.log`、`125951.log` 为编译失败；`130033.log` 为 250/4；均未删除。
- 静态收尾：`git diff --check` PASS；无 iOS、冻结 port/schema/repository、S2+ 或 baseline 改动。
- 未完成项：本轮实现与指定自动测试无未完成项；真实设备系统 splash、人工像素/视觉验收与宿主提交未执行，不以 JVM 代替。未新增截图，不改 Penpot 批准设计。未跑全套 milestone/设备测试。


## 改动文件清单

下列状态来自本轮最终 git audit；M 为 tracked modification，D 为迁移旧文件删除，?? 为新增 untracked；无 staged content。

```text
 M android/app/src/debug/java/com/ignacioli/finecoach/S0ComponentCatalog.kt
 M android/app/src/main/java/com/ignacioli/finecoach/S1App.kt
 M android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcControls.kt
 M android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcRows.kt
 M android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcSetRow.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/exercises/ExerciseScreens.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/history/HistoryRecordCard.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/resources/ResourceHubScreen.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/session/SessionChrome.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/session/SessionSwipeRow.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/students/StudentListScreen.kt
 D android/app/src/main/java/com/ignacioli/finecoach/features/today/TodayAmbientScene.kt
 M android/app/src/main/java/com/ignacioli/finecoach/features/today/TodayScreen.kt
 M android/app/src/main/res/values/themes.xml
 M android/app/src/test/java/com/ignacioli/finecoach/ComponentCatalogTests.kt
 M android/app/src/test/java/com/ignacioli/finecoach/TodayNavigationEntryLayoutTests.kt
 M android/design-assets/README.md
 M android/design-assets/convert-material-symbols.mjs
 M android/design-assets/material-symbols-SHA256SUMS
 M android/design-assets/material-symbols-SOURCE.txt
 M android/design-assets/material-symbols-manifest.txt
 M android/design-assets/material-symbols-provenance.json
 M android/docs/s1/implementation-map.md
 M design/design-system/components.md
?? android/app/src/debug/java/com/ignacioli/finecoach/S1ComponentCatalog.kt
?? android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcAmbientScene.kt
?? android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcEquipmentIcon.kt
?? android/app/src/main/java/com/ignacioli/finecoach/designsystem/FcPages.kt
?? android/app/src/main/res/drawable/ic_equipment_barbell.xml
?? android/app/src/main/res/drawable/ic_equipment_bike.xml
?? android/app/src/main/res/drawable/ic_equipment_bodyweight.xml
?? android/app/src/main/res/drawable/ic_equipment_cable_crossover.xml
?? android/app/src/main/res/drawable/ic_equipment_cable_machine.xml
?? android/app/src/main/res/drawable/ic_equipment_dumbbell.xml
?? android/app/src/main/res/drawable/ic_equipment_hack_squat.xml
?? android/app/src/main/res/drawable/ic_equipment_hip_adduction.xml
?? android/app/src/main/res/drawable/ic_equipment_jump_rope.xml
?? android/app/src/main/res/drawable/ic_equipment_kettlebell.xml
?? android/app/src/main/res/drawable/ic_equipment_leg_extension.xml
?? android/app/src/main/res/drawable/ic_equipment_pec_deck.xml
?? android/app/src/main/res/drawable/ic_equipment_plate_loaded.xml
?? android/app/src/main/res/drawable/ic_equipment_pull_up_bar.xml
?? android/app/src/main/res/drawable/ic_equipment_resistance_band.xml
?? android/app/src/main/res/drawable/ic_equipment_rowing_machine.xml
?? android/app/src/main/res/drawable/ic_equipment_shoulder_press.xml
?? android/app/src/main/res/drawable/ic_equipment_smith_machine.xml
?? android/app/src/main/res/drawable/ic_equipment_suspension_trainer.xml
?? android/app/src/main/res/drawable/ic_equipment_tbar_row.xml
?? android/app/src/main/res/drawable/ic_equipment_treadmill.xml
?? android/app/src/main/res/drawable/ic_ms_check_circle_filled.xml
?? android/app/src/main/res/drawable/ic_ms_filter_alt.xml
?? android/app/src/main/res/drawable/ic_ms_filter_alt_filled.xml
?? android/app/src/main/res/drawable/ic_ms_folder.xml
?? android/app/src/main/res/drawable/ic_ms_info_i.xml
?? android/app/src/main/res/drawable/ic_ms_list_alt.xml
?? android/app/src/main/res/drawable/ic_ms_star_filled.xml
?? android/app/src/main/res/drawable/launch_blank.xml
?? android/app/src/test/java/com/ignacioli/finecoach/S1CatalogStateTests.kt
?? android/app/src/test/java/com/ignacioli/finecoach/S1ComponentAssetTests.kt
?? android/app/src/test/java/com/ignacioli/finecoach/S1ComponentTests.kt
?? android/design-assets/convert-equipment-icons.mjs
?? android/design-assets/equipment-SHA256SUMS
?? android/design-assets/equipment-manifest.txt
?? android/design-assets/equipment-provenance.json
?? android/design-assets/material-symbols-svg/check_circle_filled.svg
?? android/design-assets/material-symbols-svg/filter_alt.svg
?? android/design-assets/material-symbols-svg/filter_alt_filled.svg
?? android/design-assets/material-symbols-svg/folder.svg
?? android/design-assets/material-symbols-svg/info_i.svg
?? android/design-assets/material-symbols-svg/list_alt.svg
?? android/design-assets/material-symbols-svg/star_filled.svg
?? android/docs/s1/S0-step3-components.md
```

## 第 3 步复审修复（2026-11-10）

本节为当前结果；前面的 250-test 运行、72-file 清单与「旧未引用资产保留」是首轮快照，后者由本次删除决定取代。

| 评审项 | 实际处置 | 证据 |
|---|---|---|
| P2-5 | 在现有 `iconRequestsHaveExplicitStyleWeightMappingAndNoIconDependency` 内建立 `组件 ID → 图标名 → 固定使用方文件` 对照；对 manifest 的每个 owner 逐一断言，不再扫描 main 目录。Painter 注入的图标固定校验明确的 catalog / feature 注入文件；edit 固定在 FcSetRow。未知 ID / 图标关系直接失败。 | ComponentCatalogTests，6 个方法保持；新增资产目录精确 19 SVG / 19 vector 校验 |
| P2-3 | components.md 两处现行图标数量改为 19（历史 2026-11-06 的 13 项执行记录保留）。folder 登记 feature:session-swipe-row；check_circle_filled 登记 feature:session-exercise-header，并在 map 注册 feature anatomy。确认旧图标无 Kotlin/XML 引用后删除 filter_list/info 的 SVG/vector。当前 SOURCE、manifest、provenance、SHA256SUMS、README 一致，许可/路径摘要不变。 | ComponentCatalogTests / S1ComponentAssetTests；转换器离线复现成功 |
| P2-1 | 获取装饰性星与 disclosure 的 bounds，断言 `star.right <= disclosure.left`；保留 24dp、无点击、无障碍隐藏与整行点击断言。 | S1ComponentTests.favoritePrecedesDisclosureWithoutChangingRowAction |
| P2-2 | 新增 S1ComponentReviewTests：默认场景 220；从合并 semantics 读取组标题/值/状态，以及确认、编辑、撤销 custom action 的名称和执行结果；组数值用 BasicText / TextAutoSize，单行且缩放下限 0.8；用实际字形 bounds 对照 0.8 字号参照，验证缩放底限；静态/ambient 两态量取按钮底边距等于 space.8。35 个 catalog 状态全部验证可见和关键尺寸。 | S1ComponentReviewTests 4；S1ComponentTests 9；S1CatalogStateTests 35 |
| P2-4 | 今日 loading/error/retry/empty/hero 链接重定位；历史器材补精确 `HistoryRecordCard.kt:80`。整份 map 的 1,255 个链接验证文件存在、行号范围，以及目标行包含对应 tag / 控件 / 方法；336 source + 919 test，失配 0。旧训练菜单的 9 项失效声明移至移除登记；局部 helper request/options 不再假充独立测试链接，所属具名测试仍保留。 | `.handoff/logs/S0-step3-review-map-validation.log`；逐链接 anchor 台账与只读 validator 在 `.handoff/` |

缩放机制依据当前缓存 foundation 1.12.1 的公开 API 与 [TextAutoSize 官方文档](https://developer.android.com/reference/kotlin/androidx/compose/foundation/text/TextAutoSize)。`maxLines=1`、`softWrap=false`，使用 Ellipsis 在达到 0.8 后仍放不下时保持单行。当前版本的 semantics GetTextLayoutResult 会用请求 style 回填 layoutInput（本地 TextAnnotatedStringNode 字节码已核实），因此测试保留真实单行布局读取，并对照实际字形宽度，而非把 layoutInput 的请求字号当作最终字号。

五行执行记录：

- 分类与依据：D 类 anatomy 漂移修复（§4.3 数值单行 / 最小缩放），C 类资产使用方及 entry/layout 文档校正；不改变批准设计。
- 影响范围：FcSetRow、FcRows 的装饰定位 tag、S1 独立测试/catalog 检查、Material 台账与废弃资源、implementation-map。保留开工时所有既有改动；无 staged content，不提交。
- 设计决定：复用既有 0.8 / space.8 / 220 与 AD-01；feature-owned ID 不进入共享 roster，S2+、iOS、冻结 port/schema/repository、baseline 未改。
- 实施与验证：指定受影响集合 14 类 **254 tests，0 failures/errors/skips**；G2 保持 **27 / 66 / 6 / 5**。`git diff --check` PASS。未做截图循环、真机或人工视觉验收。
- 结果：P2-1～P2-5 全部完成。完整 stdout / Gradle 输出经 tee 保存至 `.handoff/logs/S0-step3-review-complete-output.log`；最终原日志 `agent-test-android-s1-comp-20261110-133123.log`。无本轮未完成项。

保留失败证据：首轮 `agent-test-android-s1-comp-20261110-132629.log` 为 206/2（其中一项是未改动的 ActiveSession @After Compose NPE），随后该类 20/0；`132800` 运行暴露字号读取错误，改为上述实际 bounds 证明后 `133010` 为 4/0，最终完整集合 254/0。未修改收尾代码、删断言或跳过测试。
