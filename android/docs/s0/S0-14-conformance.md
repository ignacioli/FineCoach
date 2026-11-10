# S0-14 训练页设计一致性：最终执行记录

状态：**VALID_FIXTURE / 设计一致性 FAIL（预期非零）**。本轮已完成比较器anchor修正、capsule测试侧定位与报告收尾；余下真实偏差交step 6，不在本轮修产品UI。

分类与依据：C类验证工具/记录补齐；沿用P0-a2批准画稿，坐标模型按宿主S1-D30登记，不新增视觉设计。
影响范围：test-only训练fixture、比较器、map与说明；复用现有ActiveSessionScreen及DS组件；产品UI、基线、schema/repository/iOS均未改。
设计决定：51层保留，逐项top/bottom/viewport，x/y/w/h各自±2dp（含边界），文字/token精确。画板导出未改；Penpot约束暂不可读，以Android容器结构登记anchor依据。
实施与验证：组件合同27、可见性分类4、比较器单测10共41通过；实际门禁进行两次独立Room/composition渲染、真实按钮点击与PNG hash比较。无新增产品入口；entry/layout仍使用既有动作头、set-weight-plus和set-weight-input。
结果：fixture有效且stable=true；51项通过1、失败50=UI_DEVIATION40+MISSING10+INVISIBLE_OR_CLIPPED0。门禁退出1，未把失败改成通过；负责人视觉验收PENDING。

## Fixture根因与宿主修复（保留）

宿主探针已证实：原先点击动作头后只等64ms时，编辑器尚未预填（值为空、加号top=800px，随后稳定为678px）；另外mainClock暂停时，滚动容器内的真实触摸手势无法完成。semantics OnClick虽可生效，不能替代真实用户路径；命中测试没有发现其他可点击节点覆盖加号。

本轮保留宿主流程：逐帧waitUntil直到EditableText为120，再推进500ms；仅在真实set-weight-plus点击与waitForIdle期间临时autoAdvance=true，随后恢复false。精确断言122.5后才截图；没有SetText/IME注入，没有产品代码绕过。

两次渲染各重新建立Room fixture并挂载真实ActiveSessionScreen，保留虚构王小明、大腿/臀、32:00、两动作上次参考、两完成组及撤销、122.5/8录入和1:45休息状态。上次参考由test-only previous/previousCounts装配，不宣称真实历史查询证明。固定API36/NATIVE、390×844dp、density2/fontScale1、zh-CN及随包Noto Sans SC。

## S1-D30 Anchor与selector

- top（42项）：滚动内容，expectedY=designY−52+measuredContentTop；本轮contentTop=0。header内部位置、额外统计/保存区域、行距与文字布局差仍保留。
- bottom（8项：5/6、39–44）：滚动Column之外的结束按钮与休息条。Δy=actualBottomGap−designBottomGap，gap=844−(y+h)，不应用顶部偏移；x/w/h仍独立比较。结束按钮实际gap0对设计32，Δgap=−32；休息条实际gap52对设计96，Δgap=−44。
- viewport（1项：0）：全幅背景按0/0/390/844视口比较，top origin为NOT_APPLICABLE；最终四轴均0，颜色匹配，PASS。

每个map条目的判定依据及具体Kotlin位置见 `android/design-assets/conformance/README.md` 的51行表。报告JSON保留rawYDelta、actual/designBottomGap、逐轴withinTolerance；MD列出anchor与±2dp。绝对差≤2才算该轴通过，不因单轴0/亚像素就忽略其他超差轴。

path20/25不用产品tag：由真实minus/plus的LayoutInfo.parentInfo找到最近共同父容器，并确认input祖先链包含它；读取该Row真实coordinates，而非子节点union或按目标尺寸反选。本轮两个Row实际x112、w262、h48，重量y337、次数y397；相对top映射均Δy131，x/w/h均0，填充token匹配，继续如实FAIL。

## 测试与产物

产品根命令：

```sh
.handoff/bin/agent-test.sh ComponentContractTests ConformanceVisibilityTests ConformanceComparisonTests
.handoff/bin/agent-test.sh --task s0Conformance
```

均通过共享host锁运行，输出tee到 `.handoff/logs/s0-step4-anchor-unit-summary.log` / `.handoff/logs/s0-step4-anchor-conformance.log`；原始Gradle日志另保留并tee到 `s0-step4-anchor-unit-full.log`。

| 执行 | tests | failures | skips | exit |
|---|---:|---:|---:|---:|
| ComponentContractTests | 27 | 0 | 0 | 0（单测聚合） |
| ConformanceVisibilityTests | 4 | 0 | 0 | 0（单测聚合） |
| ConformanceComparisonTests | 10 | 0 | 0 | 0（单测聚合） |
| s0Conformance / TrainingConformanceTests | 1 | 1 | 0 | 1（实际设计偏差断言） |

比较器新增单测覆盖：top offset、viewport不继承offset、bottom底距及真实漂移、独立高度检查、四轴±2包含边界/单轴超差、亚像素、未知anchor失败、parent selector的input证据与歧义。G2原计数27/66/6/5未改；本轮仅定向跑合同27，不宣称完整G2或788宿主门禁通过。

原始日志：`.handoff/logs/agent-test-android-s1-conf-20261110-141429.log`、`agent-test-android-s1-conf-20261110-141529.log`。XML分别在 `android/app/build/test-results/testDebugUnitTest/` 与 `s0Conformance/`。s0Conformance唯一失败是最终 `expected0 but was50`，不是fixture或稳定性失败；finalizer也按失败传播，不能整体PASS。

截图两次均780×1688；SHA-256均为 `c190e2890406e8b3c89c0f247baba457aaaff4229801cbd83ad414edc9f28a64`，stable=true。raw像素差异比例 37.2325%，未按anchor重排PNG。门禁运行重建三联图，但本轮禁止看图，未打开任何PNG或差异图；摘要仅据文字结果，非人工视觉验收。

产物（均build输出、不入库、不是基线）：

- `android/app/build/outputs/conformance/P0-a2-training.report.json`、`.report.md`
- 同目录 `P0-a2-training.triptych.png`、`.android.png`、`.run1.png`、`.run2.png`、`.nodes.json`、`.stability.json`

## 最终分类与最大偏差

总数51；通过1；失败50；UI_DEVIATION 40；MISSING 10；INVISIBLE_OR_CLIPPED 0。不可见分类本轮为0；其测试覆盖滚动区外/部分裁剪/零布局，不能把isDisplayed解释为无遮挡，occlusion仍UNVERIFIED。

下表按各映射元素max(abs(Δx),abs(Δy),abs(Δw),abs(Δh))降序，排除missing/不可见；单位dp（bottom行的Δy为底距差）。

| path | 元素 | anchor | Δx | Δy | Δw | Δh |
|---|---|---|---:|---:|---:|---:|
| 2 | Text | top | 0 | 8 | 167.5 | 0.5 |
| 27 | DS-STEPPER-FIELD · value (可点击输入) | top | -80 | 124 | 159 | 15 |
| 34 | Text | top | 0 | 130 | 141.5 | 5 |
| 29 | DS-STEPPER-FIELD · hint | top | 0 | 135 | -2 | 2.5 |
| 19 | DS-LABEL · 重量 | top | 0 | 132 | 45 | 4 |
| 24 | DS-LABEL · 次数 | top | 0 | 132 | 64 | 4 |
| 35 | P0 · 上次参考 (DS-LAST-REF) | top | 0.5 | 131.5 | -1.5 | 2.5 |
| 20 | DS-STEPPER-FIELD · capsule (重量) | top | 0 | 131 | 0 | 0 |
| 25 | DS-STEPPER-FIELD · capsule (次数) | top | 0 | 131 | 0 | 0 |
| 30 | DS-BUTTON · primary (确认) | top | 0 | 129.5 | 0 | 0 |

## 按组件归类的偏差主题（step 6输入）

- SessionHeader（1–3）：标题x偏44；学员行Δy8、Δw167.5；计时x偏28.5、Δy8，token为text.primary，画稿是action.primary。header额外完成组数/保存状态仍在Android-only文本列表，不把它们当作已批准设计变更。
- 动作头/上次参考（4/8、34/35）：深蹲上次参考x偏−93；后续卧推标题Δy130、上次参考Δy131.5；标题Text的weight占位宽度不同于画稿文字框，报告比较的是实际layout bounds，不宣称字形墨迹宽度变大。
- DS-SET-ROW（9、11–18、45/46）：组行y和横向分配有偏差，状态文字path13为text.secondary对画稿action.primary；圆圈/编辑map当前指向44dp触控容器，内部图形不是独立观测节点，因此44对22/20的尺寸、圆圈代理区域众数白色**不等于真实圆圈或铅笔形状/填色错误证明**。这些记录不计通过，step 6应先区分观测容器与视觉轮廓，不能为了green改产品形状。
- DS-STEPPER与提示（19–29）：capsule x/w/h均匹配但top偏131；输入TextField的占位框宽高不同于画稿文本框；minus/plus是painter，缺文字semantics使21/23/26/28逐字比较失败，但不能据此声称肉眼无图标。hint Δy135、Δh2.5超容差。
- DS-BUTTON确认（30/31）：按钮x/w/h一致、top偏129.5；文字Δy128.5、Δh4.5，继续FAIL。
- 添加入口（37/38）：top偏126.5，字号框高度偏4；不是不可见，也不需要滚动证明可见性。
- DS-REST-TIMER/结束训练（5/6、39–44）：去除top offset伪影后，固定栏真实bottom gap差仍32–49；休息条/按钮尺寸主体匹配，内部文字高度及控件横向位置仍不同。
- missing（7、7/1、10、45/1、15、46/1、32、33、33/1、36）：无独立可定位semantics的器材group/SVG path、勾号及分割线。此类是缺失观测节点，不据此断言屏幕没有对应图形；图层未删减，仍fail-closed。

## 边界与遗留

本轮范围已收尾：fixture解锁保留、锚点/selector已验证、报告有效且稳定；**设计一致性门禁仍FAIL**。真实偏差交step 6；剩余missing及容器代理观测限制需在该步骤明确处理，不通过删map或改容差绕过。T020负责人走查/录基线与S0-13 host集成未执行。未跑G0、完整宿主门禁、设备走查或release产物隔离检查。未提交、未推送、未改截图基线。
