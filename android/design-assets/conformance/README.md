# 设计图层只读导出

`P0-a2-training.layers.json` 是宿主通过 Penpot MCP 只读导出并逐项校验的画板几何；不是重新设计，也不是 Android screenshot baseline。原文件位于产品 `.handoff/design/P0-a2-training.layers.json`，本轮逐字节复制。

| 字段 | 来源 |
|---|---|
| Penpot 文件 | M1-B G5 Design |
| 页 | Foundations |
| 画板 ID | `c15be9e7-1456-8033-8008-cb05fb3c1135` |
| 画板名 | P0-a2 训练中 · 精简（只留确认；左滑删除与移入分区；撤销在刚确认的组上）（2026-10-15） |
| 导出日期 | 2026-11-10 |
| SHA-256 | `07deec48c1da62249e058ddee1453ee2ced575e3ff710948e41cc91b46da6658` |
| 对应画稿 | `design/experience-p0/screens/P0-a2-training.png`，780×1688，390×844pt @2x |
| 数量 | 51 层 / 51 unique path；33 text、8 rectangle、4 group、4 path、2 ellipse |

导出与这版画板/PNG 绑定，只有宿主能更新；agent 不修正、删减导出层。导出未含 fileId/pageId，不推测它们。画板或 PNG 更新时，宿主同时重新导出并登记新 digest；不把导出当成新的视觉权威。

`P0-a2-training.map.json` 逐 path 覆盖全部 51 层。selector 使用真实 testTag 或 scope tag + 原文；运行时绑定随机 Room ID，不把 ID 当视觉信息。没有独立 semantics 的 SVG path / 分割线保留并报 missing；不从 map 删除。非文字触控容器的 bounds 不等于内部可见图形，相关 selector 明示此限制，因此尺寸差仍会失败。文字颜色来自 `TextLayoutResult`；填充色来自截图实际节点矩形内 exact RGB 众数，无近似色匹配。README 相同 hex 的 aliases 归一到 map 声明的语义 token，RGB 证据不能区分同值 alias。

## Anchor（宿主决策 S1-D30）

每项显式声明 `anchor=top|bottom|viewport`。Penpot约束暂不可读，以下依据当前 Android 容器结构登记，不推测 Penpot pin 设置。

- top：`expectedAndroidY=designY-52+measuredContentTop`；只将画稿首内容y=52与Android content顶部对齐，header内部居中/back/行距等偏差照常报告。
- bottom：固定底栏，不随 `active-session-content` 滚动；`gap=844-(y+h)`，`Δy=actualGap-designGap`。不加top offset，仍逐项比较x/w/h。结束按钮设计底距32pt，休息条96pt；真实底距差不能被anchor消除。报告保留rawYDelta和两端gap。
- viewport：全幅背景对实际390×844视口比较x/y/w/h，top offset为NOT_APPLICABLE；不将iOS内容起点差误计为背景UI偏移。

所有轴独立使用包含边界的 `abs(Δ)≤2dp`；任一超限失败。文字逐字、token精确，无阈值放宽。以下引用的Kotlin路径以 `android/app/src/main/java/com/ignacioli/finecoach/` 为根。

| path | anchor | 判定依据（源码位置） |
|---|---|---|
| 0 | viewport | designsystem/FcPlatformShell.kt:14：platform-shell fillMaxSize背景，覆盖视口。 |
| 1 | top | features/session/ActiveSessionScreen.kt:75–77：滚动内容内SessionHeader；features/session/SessionChrome.kt:24。 |
| 2 | top | features/session/ActiveSessionScreen.kt:75–77：滚动内容内SessionHeader；features/session/SessionChrome.kt:28。 |
| 3 | top | features/session/ActiveSessionScreen.kt:75–77：滚动内容内SessionHeader；features/session/SessionChrome.kt:36。 |
| 4 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 5 | bottom | features/session/ActiveSessionScreen.kt:153–156：滚动Column结束后，同级session-finish按钮及其文字固定在底部。 |
| 6 | bottom | features/session/ActiveSessionScreen.kt:153–156：滚动Column结束后，同级session-finish按钮及其文字固定在底部。 |
| 7 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 7/1 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 8 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 9 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 10 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 11 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 12 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 13 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 45 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 45/1 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 14 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 15 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 16 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 17 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 18 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 46 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 46/1 | top | features/session/ActiveSessionScreen.kt:102–118：滚动动作内FcSetRow；designsystem/FcSetRow.kt:28–58定义圆圈、组标题、数值、状态/撤销、编辑；无独立path仍保留top/missing。 |
| 19 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 20 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 21 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 22 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 23 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 24 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 25 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 26 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 27 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 28 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 29 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 30 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 31 | top | features/session/ActiveSessionScreen.kt:121–126：滚动动作内SetEditor；features/session/SetEditor.kt:56–71、89–104；designsystem/FcControls.kt:277–285：录入胶囊/减号/数值/加号。 |
| 32 | top | features/session/ActiveSessionScreen.kt:130：滚动动作块尾FcListRowDivider，无独立semantics节点仍保留top/missing。 |
| 33 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 33/1 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 34 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 35 | top | features/session/ActiveSessionScreen.kt:93–100、146：滚动内容内动作行；features/session/SessionChrome.kt:45–58定义标题、图标、上次参考；无独立图标path节点仍保留top/missing。 |
| 36 | top | features/session/ActiveSessionScreen.kt:129：滚动动作块尾FcListRowDivider，无独立semantics节点仍保留top/missing。 |
| 37 | top | features/session/ActiveSessionScreen.kt:149：添加动作/分区在滚动Column内。 |
| 38 | top | features/session/ActiveSessionScreen.kt:150：添加动作/分区在滚动Column内。 |
| 39 | bottom | features/session/ActiveSessionScreen.kt:153–155：滚动Column外RestTimerView；features/session/RestTimerView.kt:38，固定休息条及其子元素。 |
| 40 | bottom | features/session/ActiveSessionScreen.kt:153–155：滚动Column外RestTimerView；features/session/RestTimerView.kt:43，固定休息条及其子元素。 |
| 41 | bottom | features/session/ActiveSessionScreen.kt:153–155：滚动Column外RestTimerView；features/session/RestTimerView.kt:44，固定休息条及其子元素。 |
| 42 | bottom | features/session/ActiveSessionScreen.kt:153–155：滚动Column外RestTimerView；features/session/RestTimerView.kt:46，固定休息条及其子元素。 |
| 43 | bottom | features/session/ActiveSessionScreen.kt:153–155：滚动Column外RestTimerView；features/session/RestTimerView.kt:47，固定休息条及其子元素。 |
| 44 | bottom | features/session/ActiveSessionScreen.kt:153–155：滚动Column外RestTimerView；features/session/RestTimerView.kt:48，固定休息条及其子元素。 |

## Capsule测试侧selector

path20/25通过 `commonLayoutParentOfTags` 指向真实minus/plus的最近共同 `LayoutInfo.parentInfo`，要求 `containsTag` 对应input的祖先链也包含该节点。读取真实Row的coordinates.boundsInRoot与positionInRoot/size；不按目标262×48反选容器、不用子节点union伪造边界。Row本身无semantics（FcControls.kt:277），所以它作为test-only layout observation写入nodes.json，并明确geometrySource，未给产品增加tag。定位/附着失败则missing，不能回退到近似矩形。
