# T122 加密出口合规（非 TestFlight 门）

记录日期：2026-08-29

**本文件不声称豁免。** 实现方不得把 `ITSAppUsesNonExemptEncryption` 写成 `NO`。

## 产品决定（2026-08-29）

Account Holder 打开 App Store Connect 时提示：

> Your Apple Account isn't enabled for App Store Connect.

当前 Apple ID **未订阅** Apple Developer Program。产品负责人决定：先完成 App 功能；Apple Developer Program、TestFlight、App Store Connect、App Store 上架全部推迟。

M1-A 安装通道为 **Personal Team 本机签名**，七天证书有效期可接受。T122 **不是**验收门。

## 产品事实（上架时再由 Account Holder 判定）

- 无账号、无服务器、无 HTTPS 业务通道；无第三方加密库。
- 备份容器 `FineCoachBackup v1` 使用 PBKDF2-HMAC-SHA256（600,000 次）与 AES-256-GCM。
- 生成的 Info.plist 当前没有 `ITSAppUsesNonExemptEncryption` 或 `ITSEncryptionExportComplianceCode`。
