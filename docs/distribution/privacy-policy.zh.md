<!--
草稿，未发布。发布位置待负责人决定（docs/distribution/testflight-readiness.md D4）。
每一句都对应一条代码事实，依据写在本注释里，发布时删掉注释：
- 无网络请求、无第三方 SDK、无遥测：testflight-readiness.md §1
- 本机存储，排除在设备备份外，并启用文件保护：Core/Platform/ProtectedFileStore.swift:8-25，StoreGeneration.swift:111
- 通知只在本地触发，只在开启提醒时请求权限：NotificationAdapter.swift:104，Localizable「onboarding.sheet.permission.detail」
- 备份和档案用用户密码加密（AES-GCM + PBKDF2）：BackupCrypto.swift:44-104，ArchiveFileCodec.swift:201-205
- 档案永不导出的字段：Localizable「archive.export.exclusion.fullList」
- 训练报告永不包含的字段：Localizable「onboarding.sheet.private.detail」
- 文件只通过系统分享面板或「存储到文件」交出：SystemShareAdapter.swift:43-104
- 外链只用系统浏览器打开：SettingsView.swift:44，ArchiveAboutView.swift:60
- 隐私清单：FineCoachApp/PrivacyInfo.xcprivacy
联系方式、生效日期由负责人填写。
-->

# 精练教练（FineCoach）隐私政策

生效日期：〔待填写〕

精练教练是一款私教课堂记录 App。本政策说明 App 怎样处理你的数据。

## 一句话总结

精练教练没有账号，也没有服务器，不做数据统计。你录入的所有内容只保存在你自己的 iPhone 上。开发者收不到、也看不到你的任何数据。

## 我们收集什么

什么都不收集。

- App 不需要注册或登录。
- App 不会通过网络向开发者或任何第三方发送数据，代码里没有网络请求。
- App 不包含任何第三方 SDK，没有广告、统计、崩溃上报或追踪。
- App 不使用 HealthKit，也不读取通讯录、照片、位置等系统数据。

## 你录入的数据存在哪里

你在 App 里录入的学员资料、训练记录、身体数据、伤病备注、课程安排、课包和备注，都只保存在这台 iPhone 上 App 自己的存储空间里：

- 这些文件启用了 iOS 文件保护，设备锁定后受系统加密保护。
- 这些文件不会进入 iCloud 或电脑上的设备备份。
- 卸载 App 后，这些数据会被一起删除。丢失手机时数据也会丢失，除非你事先手动做了备份（见下文）。

## 数据什么时候会离开这台手机

只有你主动操作时，数据才会离开这台手机，并且都通过 iOS 系统的分享面板或「存储到文件」完成。精练教练不托管文件，也不生成公开链接。

1. **备份**（「设置 → 备份与恢复」）：生成 `.fcbackup` 文件，用你设置的密码加密。文件存到哪里由你决定。
2. **个人训练档案**（学员详情 → 「导出个人训练档案」）：生成 `.fcarchive` 文件，用你设置的密码加密，供学员在自己的设备上只读查看。伤病与注意事项、教练备注、动作私有备注、课包、课程安排、课时调整、电话和微信、动作图片、训练模板永远不会导出。
3. **训练报告**：生成一张图片，包含哪些内容由你挑选。性别、身体数据、伤病、电话、微信和你的私人备注永远不会出现在报告里。

文件交出后，由你选择的 App 或服务（比如微信、文件 App）按它们自己的政策处理。文件被接收后，你和精练教练都无法撤回。

## 通知

只有你为课程开启提醒时，App 才会请求通知权限。通知由 iPhone 本地生成，不经过任何服务器。

## 外部链接

「源代码」和许可证链接会用系统浏览器打开对应网页。打开之后，网页的数据处理由该网站负责。

## 学员视图

如果你在首次启动时选择「导入个人训练档案」，App 只保存你导入的那一份档案，供你在本机只读查看。导入的档案同样只存在本机，不会上传。

## 政策变更

如果今后 App 的数据处理方式发生变化（比如增加联网功能），会先更新本政策，再发布对应版本。

## 联系方式

〔待填写，例如 GitHub Issues：https://github.com/ignacioli/FineCoach/issues〕
