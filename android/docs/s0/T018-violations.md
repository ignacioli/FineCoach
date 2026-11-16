# T018 完整违规清单（修复轮扩展规则后）

基线：`2cfa9e4587226f34fe5da1d1fcba65ffad38c7aa`，工作树初始干净。
前轮旧规则扫描 108 文件 / 0 违规；本修复轮规则扩展后仍扫描 108 文件，检出 3 个真实违规（均为 debug 组合的 MaterialTheme 直接取值）。当前修改前状态已审计，保留前轮所有未提交内容。修复轮按要求停止替换并报告；收尾轮负责人明确批准后，依据 FineCoachTheme.kt 映射将 3 处等值替换，不加豁免。最终扫描 108 文件 / 0 违规。

| 核心页分组 | 扫描目录 | 文件数 | 原始违规 | 等值替换 | 遗留 |
|---|---|---:|---:|---:|---:|
| 训练中 | features/session | 12 | 0 | 0 | 0 |
| 动作库/选择动作 | features/exercises；选择动作也位于 session | 3（session 不重复计） | 0 | 0 | 0 |
| 今日 | features/today | 1 | 0 | 0 | 0 |
| 学员列表/学员详情 | features/students | 7 | 0 | 0 | 0 |
| 历史详情 | features/history | 5 | 0 | 0 | 0 |
| 其他 | features/packages 7、features/resources 1、features/templates 3、navigation 3、shell/other 59、debug 7 | 80 | 3 | 3 | 0 |
| 总计 | main（排除 designsystem 定义）；debug（含全部组合） | 108 | 3 | 3 | 0 |

## 替换前逐项违规与最终处置（行号为替换前位置）

| 文件:行（相对 app/src） | 类别 | 原始值 | 处置 |
|---|---|---|---|
| debug/java/com/ignacioli/finecoach/S0DebugApplication.kt:48 | materialTheme | MaterialTheme.colorScheme.background | 已等值替换 FcColors.surfacePage（Theme background 映射） |
| debug/java/com/ignacioli/finecoach/S0DebugApplication.kt:78 | materialTheme | MaterialTheme.typography.bodyLarge | 已等值替换 FcTypography.body（Theme bodyLarge 映射） |
| debug/java/com/ignacioli/finecoach/S0DebugApplication.kt:78 | materialTheme | MaterialTheme.colorScheme.onBackground | 已等值替换 FcColors.textPrimary（Theme onBackground 映射） |

最终目录计数：debug 7 文件 / 0 违规；其他目录违规均 0；108 文件、3 处等值替换、0 遗留。真实文件数来自测试遍历，不排除 debug、不建立 allowlist。s0G3 PASS：38 tests，0 failures/errors/skips。
