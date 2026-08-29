# T119 隐私 canary

记录日期：2026-08-29

虚构 canary 字段（不得出现在报告/日志/文件名）：性别、伤病、联系方式、私有备注、身体数据标识。`ShareReportPolicyTests` 使用「林青」、`女`、`13800001111`、`合成伤病注意事项`、私有教练/动作备注，并禁止 DTO 属性名含 `sex` / `injury` / `phone` / `bodyMass` 等。

`ShareReportRendererTests` 扫描 PNG/文件名。`HistoryShareUITests.testShareReportStartsFromSafeDefaultsPreviewAndForbidsSensitiveFields` 覆盖预览。`FoundationIntegrationTests.testLoggerCanaryOnlyExposesFixedNonBusinessValues` 覆盖日志枚举面。

App 无通知扩展、无远程日志。T112 上述用例通过。

物理设备 Integration：`FoundationIntegrationTests.testLoggerCanaryOnlyExposesFixedNonBusinessValues` 与 `ShareReportRendererTests` 在 `/tmp/FineCoach-Device-Int.xcresult` 通过。`HistoryShareUITests.testShareReportStartsFromSafeDefaultsPreviewAndForbidsSensitiveFields` 在真机 UI 跑次中为 `Test crashed with signal kill`。

## 未完成

未用含身体数据的完整 canary 扫描通知、截图与系统分享附件的物理设备产物。泄漏数不能在缺少任务切换器截图的情况下记为已证明的 0。见 `app-switcher-privacy.md`。
