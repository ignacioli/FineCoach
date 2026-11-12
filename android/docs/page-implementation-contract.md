# Android 页面实现契约

这份契约适用于 Android 端新写或重写的每一个用户可见页面。每份 UI 任务说明都要引用本文。要改它，先在 `.handoff/decisions/android-port.md` 登记决策。

依据：roadmap §0/§0.1；决策 S1-D40（行盒）、S1-D42（待改稿）、S1-D44（例外比例）、S1-D45（SSIM 只作诊断）；`design/design-system/README.md` §15；`components.md` §1.4。

## 1. 文字与行盒（S1-D40 R1～R5）

- **一律用 `FcText`**（`designsystem/FcText.kt`）。单行文字的布局高度等于 token 行高（字号 × 行高倍率），自然行盒在其中居中；首基线和末基线会向外传递，`alignByBaseline` 照常可用。
- 平台 `Text(` / `BasicText(` 只能出现在 `DesignValueScanTests` 的 R5 白名单里。每条白名单都写明文件、类别、精确次数和理由；新增一处会让 G3 失败。
- **多行文字**：行与行之间的距离就是 token 行高。比对器按 token 行高归一设计稿的文字框（R2），所以不用为了贴合设计稿去手工补 padding。
- **输入框**（`EDITABLE_TEXT_FIELD`）：按中心点比对，不比上下边。
- **−/+ 等符号**（`SYMBOL_CENTER`）：用 20dp 的符号框居中，不按文字行盒处理。
- **墨迹溢出**：下伸部和大号数字的墨迹可以超出 token 行盒，最多（自然行高 − token 行高）/ 2，这与 CSS 一致。会裁剪内容的容器（`clipToBounds`、滚动视口的边缘）必须给这部分留出空间。
- **间距只用 token**（R3）：`FcSpacing.*`、`FcComponentMetrics.*`。不要用 `.offset` / `.absoluteOffset` 去微调位置；这两个也受 R5 白名单约束。
- **页面纵向组合**按 `components.md` §2.1 `DS-PAGE-FLOW`：块间 `space.4`、区段标签→内容 `space.2`、水平 `space.4`、底部 `space.6`。任务说明要列出该页用到的关系；画板与它冲突时，由调度方先改画板（S1-D49），实现不去贴合手工距离。

## 2. 设计来源

- 唯一目标是 `design/*/screens/*.png` 和 Penpot 画板，组件结构以 `components.md` 为准。iOS 代码只作功能参考，不作视觉参考（roadmap §0）。
- 任务说明必须写出：screens PNG 的路径、用到的 components anatomy 条目、用到的 `design/` 资产（图标、器械 SVG 等）。没先查过 `design/`，不能说"没有对应资产"。
- 设计稿和 token、anatomy 冲突时，先看 P1.3 预检报告（`ConformancePrecheck`），由调度方登记成决策点。不要在实现里自行取舍。

## 3. 比对器契约（`s0Conformance`）

- **文字层**按原文精确自动映射，不需要手写 selector。重复文案按阅读顺序加最近中心一一配对；配对有歧义就报 AMBIGUOUS。
- **非文字层**（图标、容器、分隔线、chip 等）遵守命名约定，二选一：
  - 画板图层命名为 `testTag:<运行时 tag>`；
  - 或者运行时 `Modifier.testTag("conformance:<完整画板图层名>")`。
  tag 必须挂在**真实可见的图形**上，不能挂在 44dp 的点击区上。
- **矢量内部 path** 自动继承父图标的 selector，前提是父图标几何通过、来源 hash 一致。
- **几何（S1-D55/D56）**：尺寸 w/h、相邻间距、最小包含父层内边距与对齐的每个 Δ 先取最近 0.25dp，再比较 ±2dp；报告保留 raw Δ 与 rounded Δ。绝对坐标使用未经取整的 ±8dp 粗界限；界内绝对坐标只诊断；保留行盒归一、anchor 与 origin offset。
- **取整**：最近 0.25dp 的 ties 使用 half away from zero，+2.125→+2.25、−2.125→−2.25，两者均失败。
- **nearest neighbour**：仅按设计几何选取下方或右方、不互相包含且 cross axis 严格重叠的候选；选择主轴边缘间距最小者，同距按 path 排序。每个方向最多一对，实际偏移不改变配对。
- **smallest container**：设计框完整包含子框且面积严格大于子框的最小面积可观测层；x/y inset 为子框相对该父框的左/上距离。相同面积按导出顺序稳定选择。
- **alignment group**：按设计的 left/right/centerX 分别建图，边缘距离 ≤0.5dp 连边，以 transitive closure 的 connected component 为组；实际边缘最大值减最小值按 ±2dp 判断。0/0.4/0.8dp 属同组。
- **已知限制**：无完整包含父框就没有 INSET；cross axis 不重叠就不形成 GAP；unpaired gaps fall back to the absolute ±8 bound。粗界限不能证明这些未配对关系的 ±2dp 一致性（S1-D61）。
- **ICON_PIXELS（S1-D59）**：所有 icon 或承载矢量内部 path 的最近父 group，在父几何通过后独立做形状门禁；AD-01 mapping table 中的平台图标（含组件名中的 Android symbol alias）除外。内部 path 仍为 UNOBSERVABLE，不计 PASS，也不能代替此门禁。
  - 从批准 PNG（2×）的原始父框及 Android 的实测父框各取 crop，父框中心重合，按父框尺寸用 nearest-neighbour 采样到相同的设计 2× 像素网格。仅消除父框位置差，不做 ink centroid 搜索、旋转或墨迹包围盒拟合；框尺寸仍受 SIZE 门禁。
  - 每个 crop 边界的 RGB 众数为 local background（同票按 RGB 数值排序）；与其最大通道差 >32 的像素为 ink。两 mask 的 intersection / union 为 ink IoU，空 union 得 0；越界 crop 失败。颜色仍由独立 exact RGB 检查负责。
  - **阈值 IoU ≥0.70**，统一用于所有屏，无 per-screen 分支。数据依据：当前 D2b canonical icons 为 0.975062～1.000000，P0-a2 barbell 为 1.000000；32 灰阶阈值下，1.4× 中心放大负例为 0.227687～0.477394。0.70 位于两组间，双方均留 >0.20 margin；barbell→dumbbell 替换负例为 0.328244，由自动测试覆盖。阈值固定，不随本次结果自适应。
  - 每个父图标在 JSON 与 Markdown 报告中单列 ICON_PIXELS、IoU、threshold 和 PASS/FAIL；失败使该元素计入 failed，父几何不通过时报告 BLOCKED_PARENT_GEOMETRY。
- **颜色**必须属于 README 的 token，并且在截图中能找到精确 RGB。半透明颜色按真实背景合成后再比；找不到背景就判失败。
- **弹窗、底部面板**必须拍到真实面板像素；拍不到就是 INVALID_CAPTURE，不算通过。
- **动态 ID** 用 fixture bindings（`$name`）引用，不要写死 UUID。

## 4. 完成标志（每个核心屏）

1. 设计图层全部映射，没有 MISSING；尺寸、相邻间距、包含内边距与对齐的 Δ 取最近 0.25dp 后比较 ±2dp，绝对坐标 ±8dp 粗界限、颜色精确（S1-D55/D56），适用图标 ICON_PIXELS（S1-D59）全部通过，failed 0。
2. 手写例外（manual selector、anchor、geometryRule、pendingBoardFix）≤10%（S1-D44）。超出的部分要么是设计稿待改项，要么就是 UI 没按 §3 的约定挂 tag，后者要修。
3. 功能测试、G3、G4、全量宿主门禁全绿；Compose UI 测试覆盖入口与布局（改动数据的控件可见、可点，不能只靠长按；该占满宽度的控件宽度等于父容器）。
4. 三联图和 SSIM 热力图已生成。SSIM **不是门禁**（S1-D45），只用来帮人在走查时定位问题。
5. 执行记录里有入口与布局映射表（`components.md` §1.4）。
6. 负责人走查并批准后，才录入 G5 像素基线（只有负责人能录）。

## 5. 禁止事项

- 截图→判断→修改→再截图的收敛循环（任何工具都不行）。一次性、按清单做的截图审查可以。
- 为了让比对通过，去改容差、改锚点或扩大白名单；遇到这种情况登记决策点。
- 改 iOS 产品代码、改截图基线、在 fixture 里用真实个人数据。
- 单个子任务跑了 20 分钟还没收敛：停下来检查方向，不要原地重试。
