# T121 隐私清单（非 TestFlight 门）

记录日期：2026-08-29

## 产品决定

M1-A **不以** Apple Developer Program、TestFlight、App Store Connect 隐私问卷或签名 Archive 隐私报告为验收门。上架推迟。本文件不构成上传授权。

## 本地已覆盖（T005 / T114）

- `ios/FineCoachApp/FineCoach.entitlements` 为空字典。
- `ios/FineCoachApp/PrivacyInfo.xcprivacy`：
  - `NSPrivacyTracking` = false
  - collected data types 与 tracking domains 为空
  - `NSPrivacyAccessedAPITypes`：`NSPrivacyAccessedAPICategoryDiskSpace` / `E174.1`

`E174.1` 对应备份/恢复写入前的空间检查，不向用户展示磁盘数字，也不把容量送出设备。

## 推迟

Xcode Archive 隐私报告、App Store Connect 问卷：随 App Store / TestFlight 一并推迟。
