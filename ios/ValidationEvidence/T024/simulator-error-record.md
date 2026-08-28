# T024 Simulator 错误记录

记录日期：2026-08-28

## 1. 文件保护审计失败

- 截图：[simulator-protection-audit-failure-converted.png](./simulator-protection-audit-failure-converted.png)
- 结果包：`/tmp/FineCoach-T024-Sim-ProtectionFix-BeforeBoundary-20260827.xcresult`
- 测试：`FoundationIntegrationTests/testProtectedDirectoryAndAtomicFileReadBackPolicy()`
- 现象：Simulator 回读为 `NSFileProtectionNone`，而策略要求 `NSFileProtectionCompleteUnlessOpen`；备份排除仍为 `true`。
- 处理：Simulator 仅保留备份排除的强校验，并把保护级别回读作为诊断附件；实体设备构建仍执行精确保护级别匹配。
- 修复后针对性结果：`/tmp/FineCoach-T024-Sim-ProtectionFix-FinalTargeted-20260827.xcresult`，1/1 通过。

## 2. 不兼容模型未阻止加载

- 截图：[simulator-incompatible-model-failure-converted.png](./simulator-incompatible-model-failure-converted.png)
- 结果包：`/tmp/FineCoach-T024-Sim-Foundation-Final-20260827.xcresult`
- 测试：`FoundationIntegrationTests/testIncompatibleModelDoesNotEraseExistingStore()`
- 现象：旧实现未抛出错误，重开后已有记录消失。
- 处理：在 `NSPersistentContainer` 加载前读取 SQLite metadata，并使用当前模型做兼容性预检；不兼容时 fail closed，不加载、不覆盖原 store。
- 修复后针对性结果：`/tmp/FineCoach-T024-Sim-IncompatibleModel-Fix-20260827.xcresult`，1/1 通过。

## 当前验证边界

以上两个失败均已修复并纳入完整回归。最终结果与真机证据见
[final-validation.md](./final-validation.md)。
