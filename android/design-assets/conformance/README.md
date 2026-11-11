# 设计图层只读导出

`P0-a2-training.layers.json` 是宿主通过 Penpot MCP 只读导出并逐项校验的画板几何；不是重新设计，也不是 Android screenshot baseline。原文件位于产品 `.handoff/design/P0-a2-training.layers.json`，第6轮逐字节复制，第7轮只校验digest并补齐说明。

| 字段 | 来源 |
|---|---|
| Penpot 文件 | M1-B G5 Design |
| 页 | Foundations |
| 画板 ID | `c15be9e7-1456-8033-8008-cb05fb3c1135` |
| 画板名 | P0-a2 训练中 · 精简（只留确认；左滑删除与移入分区；撤销在刚确认的组上）（2026-10-15） |
| 导出日期 | 2026-11-10 |
| SHA-256 | `db837de48a94fb7d12df081e181a4bfc3ca4477aeb95d6c1d016985714355a99` |
| 对应画稿 | `design/experience-p0/screens/P0-a2-training.png`，780×1688，390×844pt @2x |
| 数量 | 52 层 / 52 unique path；34 text、8 rectangle、4 group、4 path、2 ellipse |

导出与这版画板/PNG 绑定，只有宿主能更新；agent 不修正、删减导出层。导出未含 fileId/pageId，不推测它们。画板或 PNG 更新时，宿主同时重新导出并登记新 digest；不把导出当成新的视觉权威。

2026-11-10 宿主修订：S1-D34 将 path13 改为 15pt / 400 / #5c5a52、47×18；最终导出另将 path1 标题 x16 改为 x32，并新增 path47 返回字形（x16/y53、8×26、22pt/400/text.secondary）。本地 layers.json 与宿主交付文件逐字节一致。当前 PNG 已含 path13 修订，页头仍待负责人重新导出；agent 不改 PNG。

`P0-a2-training.map.json` 逐 path 覆盖全部 52 层。selector 使用真实 testTag 或 scope tag + 原文；运行时绑定随机 Room ID，不把 ID 当视觉信息。圆圈、铅笔、器材、✓、分割线、返回字形均指向真实可见节点；44dp 触控区单独由组件/entry tests 验证。仅 7/1、33/1、45/1、46/1 按 S1-D37 标记为矢量内部不可观测：须父级图标几何通过，并验证同一资产的来源记录及 drawable hash；任一前提不符仍失败，不伪造 path 矩形、不算 PASS。文字颜色来自 `TextLayoutResult`；填充色来自截图实际节点矩形内 exact RGB 众数，无近似色匹配。相同 hex 的 aliases 归一到 map 声明的语义 token，RGB 证据不能区分同值 alias。无 designOverride 或 registeredInserts。

## Anchor（宿主决策 S1-D30）

每项显式声明 `anchor=top|bottom|viewport`。Penpot约束暂不可读，以下依据当前 Android 容器结构登记，不推测 Penpot pin 设置。

- top：`expectedAndroidY=designY-52+measuredContentTop`；只将画稿首内容y=52与Android content顶部对齐，header内部居中/back/行距等偏差照常报告。
- bottom：固定底栏，不随 `active-session-content` 滚动；`gap=844-(y+h)`，`Δy=actualGap-designGap`。不加top offset，非文字仍逐项比较x/w/h；文字按下述S1-D37规则。结束按钮设计底距32pt，休息条96pt；真实底距差不能被anchor消除。报告保留rawYDelta和两端gap。
- viewport：全幅背景对实际390×844视口比较x/y/w/h，top offset为NOT_APPLICABLE；不将iOS内容起点差误计为背景UI偏移。

S1-D37：文字比较x、w和垂直中心，Δh只写报告；非文字比较x/y/w/h。参与判定的轴独立使用包含边界的 `abs(Δ)≤2dp`；任一超限失败。文字逐字、token精确，无阈值放宽。以下引用的Kotlin路径以 `android/app/src/main/java/com/ignacioli/finecoach/` 为根。

| path | anchor | 判定依据（源码位置） |
|---|---|---|
| 0 | viewport | designsystem/FcPlatformShell.kt / FcPlatformShell：全幅背景，platform-shell。 |
| 1 | top | features/session/SessionChrome.kt / SessionHeader；ActiveSessionScreen 的滚动内容内；训练中。 |
| 2 | top | features/session/SessionChrome.kt / SessionHeader；ActiveSessionScreen 的滚动内容内；session-student。 |
| 3 | top | features/session/SessionChrome.kt / SessionHeader；ActiveSessionScreen 的滚动内容内；session-clock。 |
| 4 | top | features/session/SessionChrome.kt / SessionExerciseHeader：真实标题/上次参考 Text；滚动内容内。 |
| 5 | bottom | features/session/ActiveSessionScreen.kt：滚动区外 session-finish，外层 Box 的 bottom space.8 留白；文字来自 FcButton。 |
| 6 | bottom | features/session/ActiveSessionScreen.kt：滚动区外 session-finish，外层 Box 的 bottom space.8 留白；文字来自 FcButton。 |
| 7 | top | features/session/SessionChrome.kt / SessionExerciseHeader → FcEquipmentIconForExercise：session-icon-$squatID，真实24dp Icon。父 Icon 几何参与比较，内部 path 按 S1-D37 有条件单列为不可观测。 |
| 7/1 | top | features/session/SessionChrome.kt / SessionExerciseHeader → FcEquipmentIconForExercise：session-icon-$squatID，真实24dp Icon。父 Icon 几何参与比较，内部 path 按 S1-D37 有条件单列为不可观测。 |
| 8 | top | features/session/SessionChrome.kt / SessionExerciseHeader：真实标题/上次参考 Text；滚动内容内。 |
| 9 | top | designsystem/FcSetRow.kt / FcSetRow：$set1-circle；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 10 | top | designsystem/FcSetRow.kt / FcSetRow：$set1-check；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 11 | top | designsystem/FcSetRow.kt / FcSetRow：第 1 组；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 12 | top | designsystem/FcSetRow.kt / FcSetRow：$set1-values；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 13 | top | designsystem/FcSetRow.kt / FcSetRow：已完成；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 45 | top | designsystem/FcSetRow.kt / FcSetRow：$set1-edit-icon；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 45/1 | top | designsystem/FcSetRow.kt / FcSetRow：$set1-edit-icon；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 内部 path 按 S1-D37 有条件单列为不可观测，父 Icon 几何仍需通过。 |
| 14 | top | designsystem/FcSetRow.kt / FcSetRow：$set2-circle；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 15 | top | designsystem/FcSetRow.kt / FcSetRow：$set2-check；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 16 | top | designsystem/FcSetRow.kt / FcSetRow：第 2 组；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 17 | top | designsystem/FcSetRow.kt / FcSetRow：$set2-values；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 18 | top | designsystem/FcSetRow.kt / FcSetRow：撤销；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 46 | top | designsystem/FcSetRow.kt / FcSetRow：$set2-edit-icon；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 |
| 46/1 | top | designsystem/FcSetRow.kt / FcSetRow：$set2-edit-icon；圆圈22、编辑Icon20、✓是真实视觉节点，confirm/edit/undo 的44dp触控区保留。 内部 path 按 S1-D37 有条件单列为不可观测，父 Icon 几何仍需通过。 |
| 19 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：重量 kg；可见 glyph/input 与44dp触控区分别观测。 |
| 20 | top | designsystem/FcControls.kt / FcStepperField：minus/plus 的真实共同 Row，input 祖先链校验不变。 |
| 21 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-weight-minus-glyph；可见 glyph/input 与44dp触控区分别观测。 |
| 22 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-weight-input；可见 glyph/input 与44dp触控区分别观测。 |
| 23 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-weight-plus-glyph；可见 glyph/input 与44dp触控区分别观测。 |
| 24 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：次数；可见 glyph/input 与44dp触控区分别观测。 |
| 25 | top | designsystem/FcControls.kt / FcStepperField：minus/plus 的真实共同 Row，input 祖先链校验不变。 |
| 26 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-reps-minus-glyph；可见 glyph/input 与44dp触控区分别观测。 |
| 27 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-reps-input；可见 glyph/input 与44dp触控区分别观测。 |
| 28 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-reps-plus-glyph；可见 glyph/input 与44dp触控区分别观测。 |
| 29 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-weight-hint；可见 glyph/input 与44dp触控区分别观测。 |
| 30 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：set-save；可见 glyph/input 与44dp触控区分别观测。 |
| 31 | top | features/session/SetEditor.kt → FcLabelValueRow / FcStepperField / FcButton：确认；可见 glyph/input 与44dp触控区分别观测。 |
| 32 | top | features/session/ActiveSessionScreen.kt：session-divider-$squatID，真实 FcListRowDivider，1dp、满宽。 |
| 33 | top | features/session/SessionChrome.kt / SessionExerciseHeader → FcEquipmentIconForExercise：session-icon-$benchID，真实24dp Icon。父 Icon 几何参与比较，内部 path 按 S1-D37 有条件单列为不可观测。 |
| 33/1 | top | features/session/SessionChrome.kt / SessionExerciseHeader → FcEquipmentIconForExercise：session-icon-$benchID，真实24dp Icon。父 Icon 几何参与比较，内部 path 按 S1-D37 有条件单列为不可观测。 |
| 34 | top | features/session/SessionChrome.kt / SessionExerciseHeader：真实标题/上次参考 Text；滚动内容内。 |
| 35 | top | features/session/SessionChrome.kt / SessionExerciseHeader：真实标题/上次参考 Text；滚动内容内。 |
| 36 | top | features/session/ActiveSessionScreen.kt：session-divider-$benchID，真实 FcListRowDivider，1dp、满宽。 |
| 37 | top | features/session/ActiveSessionScreen.kt：滚动区内添加动作/新建分区真实 FcLinkButton Text。 |
| 38 | top | features/session/ActiveSessionScreen.kt：滚动区内添加动作/新建分区真实 FcLinkButton Text。 |
| 39 | bottom | features/session/RestTimerView.kt / RestTimerView：滚动区外真实休息条及其子元素，容器 bottom space.3 间隔后接结束按钮。 |
| 40 | bottom | features/session/RestTimerView.kt / RestTimerView：滚动区外真实休息条及其子元素，容器 bottom space.3 间隔后接结束按钮。 |
| 41 | bottom | features/session/RestTimerView.kt / RestTimerView：滚动区外真实休息条及其子元素，容器 bottom space.3 间隔后接结束按钮。 |
| 42 | bottom | features/session/RestTimerView.kt / RestTimerView：滚动区外真实休息条及其子元素，容器 bottom space.3 间隔后接结束按钮。 |
| 43 | bottom | features/session/RestTimerView.kt / RestTimerView：滚动区外真实休息条及其子元素，容器 bottom space.3 间隔后接结束按钮。 |
| 44 | bottom | features/session/RestTimerView.kt / RestTimerView：滚动区外真实休息条及其子元素，容器 bottom space.3 间隔后接结束按钮。 |

| 47 | top | features/session/SessionChrome.kt → FcPageHeader：active-session-back-glyph 真实返回 Text；16dp slot，44dp active-session-back 点击 overlay 不参与布局。 |

## Capsule测试侧selector

path20/25通过 `commonLayoutParentOfTags` 指向真实minus/plus的最近共同 `LayoutInfo.parentInfo`，要求 `containsTag` 对应input的祖先链也包含该节点。读取真实Row的coordinates.boundsInRoot与positionInRoot/size；不按目标262×48反选容器、不用子节点union伪造边界。Row本身无semantics（FcControls.kt:277），所以它作为test-only layout observation写入nodes.json，并明确geometrySource，未给产品增加tag。定位/附着失败则missing，不能回退到近似矩形。
