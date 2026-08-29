# T115 兼容性矩阵

记录日期：2026-08-29

计划通道：iPhone 竖屏、简体中文、浅色模式；iPhone SE (2nd generation) / 最新 iOS 18.x，以及较新 iPhone / iOS 26.x。

| 通道 | 设备 | OS | 本轮状态 |
| --- | --- | --- | --- |
| 工程回归 | iPhone 17 Simulator | iOS 26.5 | T112 Debug 套件已跑；不是物理验收 |
| iOS 18.x 物理 | iPhone XS Max `00008020-000C5D2C3ED3002E` | 18.7.10 | 核验后启动成功；Unit 70/70、Integration 67/67；UI 10/27（17 条 runner kill）；Student XL 通过；未做 VoiceOver |
| SE 2nd gen / iOS 18.x | 不可用 | — | 阻塞 |
| 较新 iPhone / iOS 26.x 物理 | 不可用 | — | 阻塞 |

iOS 26-only API：源码审计未发现。实现不得依赖仅限 iOS 26 的视觉 API；Penpot token 映射到稳定 SwiftUI 语义。
