# T113 离线核心路径

记录日期：2026-08-29

## 架构

`FineCoach.entitlements` 为空。App 源码无 `URLSession` / `Network` / 可达性探测。Student、Session、Exercise 搜索、历史、Share Report、备份 round-trip 均走本地 Core Data / 本地文件。系统 Files 与分享由 Coach 主动发起，不构成核心路径对网络的依赖。

## Simulator 功能覆盖（诊断）

iPhone 17 / iOS 26.5。T112 UI 套件已执行这些核心路径（Debug）：

- Student：`StudentLifecycleUITests`
- Session：`CoreTrainingUITests`
- Exercise 搜索：`ExerciseLibraryUITests.testSearchFavoriteHideUnhidePlaceholderSquat`
- 历史 / Share Report：`HistoryShareUITests`
- 备份导出/恢复 UI：`BackupRestoreUITests`

备份容器 round-trip：`BackupRoundTripTests`（集成）。

这些运行未打开飞行模式；对无网络客户端的 App，失败模式与飞行模式等价，但**不能**写成已完成物理设备飞行模式验收。

## 未完成

未在 iPhone XS Max 上打开飞行模式后人工走完 Student → Session → Exercise 搜索 → 历史 → Share Report → 备份 round-trip。USB 连接设备仍可用于安装，但本轮未切换飞行模式。
