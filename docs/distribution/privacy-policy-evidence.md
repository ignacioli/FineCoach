# 隐私政策事实依据

已发布正文：`docs/privacy/index.md`（GitHub Pages：<https://ignacioli.github.io/FineCoach/privacy/>）。修改正文时逐句对照下列代码事实。

每一句都对应一条代码事实：

- 无网络请求、无第三方 SDK、无遥测：testflight-readiness.md §1
- 本机存储，排除在设备备份外，并启用文件保护：Core/Platform/ProtectedFileStore.swift:8-25，StoreGeneration.swift:111
- 通知只在本地触发，只在开启提醒时请求权限：NotificationAdapter.swift:104，Localizable「onboarding.sheet.permission.detail」
- 备份和档案用用户密码加密（AES-GCM + PBKDF2）：BackupCrypto.swift:44-104，ArchiveFileCodec.swift:201-205
- 档案永不导出的字段：Localizable「archive.export.exclusion.fullList」
- 训练报告永不包含的字段：Localizable「onboarding.sheet.private.detail」
- 文件只通过系统分享面板或「存储到文件」交出：SystemShareAdapter.swift:43-104
- 外链只用系统浏览器打开：SettingsView.swift:44，ArchiveAboutView.swift:60
- 隐私清单：FineCoachApp/PrivacyInfo.xcprivacy

