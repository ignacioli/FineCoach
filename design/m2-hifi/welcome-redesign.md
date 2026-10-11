# 首次说明页（Coach 欢迎页）重设计：设计说明

> 状态：**草稿，待产品负责人 review**（2026-10-10）。本文按 [`components.md`](../design-system/components.md) §1.5 / §6 的格式记录，只写本页自己的内容；数值以 [`README.md`](../design-system/README.md) 为准，共享组件结构以 `components.md` 为准。
> 起因：产品负责人 2026-10-10 反馈，现有首次说明页（`ios/FineCoachApp/Features/Students/Onboarding/OnboardingView.swift`）「工程味重，像本科课程作业，不像成熟 App」：系统字体导航标题「精练教练」、「首次打开 · 无账号」小字、三段长说明、深色「开始使用」、系统蓝色「稍后添加学员」。要求长文案收成一个小字链接，页面像主流 App 的欢迎页：简洁、有情绪、友好。

## 1. 设计来源

| 项 | 位置 |
|---|---|
| Penpot 文件 | 「M1-B G5 Design」→ 页面「M2 G7 Design」，画板放在 M2 画板下方一行（y = 3720） |
| 画板 | `W-01a 首次说明 · 方案 A 插画欢迎`、`W-01b 首次说明 · 方案 B 要点清单`、`W-02 首次说明 · 数据说明面板（从链接打开）` |
| Penpot 快照 | 绘制前 `before-welcome-redesign 2026-10-10`（revn 253）→ `welcome-redesign-draft 2026-10-10 (W-01a/W-01b/W-02, pending owner review)`（revn 263）。`File.validate()` 0 个错误 |
| 导出图 | 未导出。绘制时用 MCP `export_shape`（1 倍）只做排版自查，不作为验收图；批准后由产品负责人按 2 倍预设导出到 `design/m2-hifi/screens/` |
| 行为权威 | `[specs] 001-m1-a-core-session/spec.md` M1A-FR-001、M1A-FR-002、AC-001、M1A-FR-037；`[specs] 002-m1-b-coach-operations/spec.md` M1B-FR-009、M1B-FR-030；`[specs] 003-m2-personal-training-archive/spec.md` M2-FR-025、tasks T039 |

## 2. 首次启动的页面顺序（与 M2-07 衔接）

```text
新安装 → M2-07 首次启动二选一（全身吉祥物 220×220）
          ├─ 「Coach 使用」→ W-01 首次说明（本页）
          │      ├─ 「了解数据怎样保存和分享」→ W-02 数据说明面板（关闭后回到 W-01）
          │      ├─ 「添加第一位学员」→ 新建学员（first create，同现状）
          │      └─ 「稍后再添加」→ 空学员列表（16，同现状 skip）
          └─ 「导入个人训练档案」→ M2-08（不经过本页）
从 M1 升级的 Coach 安装：两页都不显示（M2 spec D-010）
```

M2-07 已经用了全身吉祥物，所以本页不再重复同一张图：方案 A 用 `mascot-avatar`（与 28 隐私说明同一素材）放大到 120×120，方案 B 用 64×64。M2-07 不改，避免同一段流程设计两次。

## 3. 方案

两个方案共用：去掉系统导航栏与「精练教练」导航标题、去掉「首次打开 · 无账号」小字；底部 `DS-BUTTON` 主按钮 + `FCLinkButton`（取代系统蓝色按钮）；长说明全部移入 W-02。

### 方案 A：插画欢迎（推荐）

居中排版：吉祥物头像 120×120（`radius.xl` 20）→ `display` 34/700 `action.primary` 两行标题 → `body` `text.secondary` 两行副标题（承载 M1A-FR-001 的两项事实）→ `FCLinkButton` 链接 → 底部主按钮 → `FCLinkButton`。

推荐理由：最接近主流 App 欢迎页（一张图、一句话、一个按钮）；情绪最强；两项必须说明的事实仍然常驻可见（§5）。

### 方案 B：要点清单

左对齐、iOS「欢迎使用」式：吉祥物头像 64×64（`radius.lg`）→ `display` 标题 → `callout` 400 副标题 → 三行要点（24pt 线性图标 + `headline` 标题 + `caption` 说明，排法同 `DS-HUB-ROW` 不可点变体）→ `FCLinkButton` 链接 → 底部按钮。

信息更完整，但更像功能介绍，情绪弱于 A。

### W-02 数据说明面板

`DS-BOTTOM-SHEET`（`fcBottomSheet`，遮罩 `overlay.scrim`）：拖动条 → 标题 `title` 22/600 → 副标题 `callout` 400 → 4 行 `DS-HUB-ROW` 不可点变体（图标 + `headline` + 多行 `caption`，无 `›`），行间分割线 → 居中 `FCLinkButton`「知道了」（同 33 筛选面板底部「完成」的做法）。两个方案都打开同一个面板。

## 4. 文案

| 位置 | 方案 A | 方案 B |
|---|---|---|
| 标题 | 专心带课 / 记录交给我（两行） | 欢迎使用精练教练 |
| 副标题 | 不用注册登录，资料只存在这台手机。/ 分享时，伤病和联系方式等永远不会带出去。 | 为私教准备的课堂记录本 |
| 要点 | — | 没网也能记 · 训练中每一组都随手记下，离线也不丢；资料只在这台手机 · 不用注册登录，不上传云端；分享内容由你挑选 · 伤病、联系方式和私人备注永远不会带出去 |
| 链接 | 了解数据怎样保存和分享 | 同左 |
| 主按钮 | 添加第一位学员（原「开始使用」，行为不变：进入新建学员） | 同左 |
| 次按钮 | 稍后再添加（原「稍后添加学员」，行为不变：完成首次说明，进入空学员列表） | 同左 |

W-02 面板（两个方案共用）：

- 标题：你的数据怎样保存
- 副标题：FineCoach 不需要账号，也没有服务器。
- 只保存在这台手机：学员资料和训练记录默认只存在本机，不会上传。卸载 App 或丢失手机时会一起丢失，可在「设置 → 备份与恢复」手动备份。
- 分享内容由你挑选：给学员发训练报告时，由你决定包含哪些内容。性别、身体数据、伤病、电话、微信和你的私人备注永远不会进入报告。（M1A-FR-037、M1B-FR-030）
- 只有你在使用：学员不需要注册登录，也不在这台手机上操作。（原文「他们不安装」在 M2 学员可导入档案后不再准确，已改写）
- 现在不会请求权限：不会弹出通知、通讯录等系统权限。只有你为课程打开提醒时，才会询问通知权限。（M1A-FR-004、M1B-FR-009）
- 关闭：知道了

## 5. spec 符合性

M1A-FR-001：「首次启动 MUST 在创建第一名 Student 前说明数据默认留在本机和分享最少披露边界；MUST NOT 要求注册或登录。」AC-001：「Coach 阅读本机/最少披露说明，跳过首次创建……」

- **只留一个链接、页面上不写这两项事实**：用户不点链接就看不到说明，「MUST 说明」变成了「可以去看说明」，不满足 M1A-FR-001 的字面要求。这种做法需要先修订 M1A-FR-001，本设计不采用。
- **方案 A / B（本设计）**：两项事实以短句常驻页面——A 的副标题两句（本机保存 + 永久不分享的字段），B 的第 2、3 条要点；不用注册登录同时写明。链接只承载完整清单和背景说明。所以页面在创建第一名学员之前已经「说明」了两项事实，满足 M1A-FR-001 与 AC-001，不需要修改 spec。
- 页面上的分享边界只举例「伤病和联系方式等」，完整的永久禁止字段在 W-02 列出。判断：M1A-FR-001 要求说明的是「边界存在」，字段的完整清单由 M1A-FR-037 约束分享报告本身，不要求写在首次说明页；现状页面同样只列了部分字段。
- M2-FR-025：选择「Coach 使用」后仍进入「M1 既有的 Coach 首次说明与主流程」——本页角色不变，只改呈现。
- M1A-FR-002：「稍后再添加」保留可见的跳过入口，行为不变。

## 6. 分类与组件（`components.md` §1.2 / §1.3）

| 组件 | 范围 | 类别 | 说明 |
|---|---|---|---|
| `DS-BUTTON`（`FCButton`、`FCLinkButton`） | 复用 | C | 修复现状的系统蓝色按钮（现状属 D 类偏离：未用 `FCLinkButton`） |
| `DS-BOTTOM-SHEET` | 复用 | C | W-02 |
| `DS-HUB-ROW` 不可点变体 | 复用（轻微扩展） | B | W-02 与方案 B 的要点行；副标题需要**多行换行不截断**，§4.7 未明确写，实现时补一句 |
| `W-WELCOME` 欢迎页组合 | 新增（feature 专有） | B | 吉祥物头像 → 标题 → 副标题 → 链接 → 底部按钮组；只有本页使用 |
| 吉祥物新用法 | — | B（新视觉决定） | README §9 写「吉祥物只用于空态插图」，28 / M2-07 已有例外；本页把 `mascot-avatar` 放大到 120（A）或 64（B）。A 使用保留 token `radius.xl` 20 的首个用例 |

整页属 **B 类**：改写已上线页面的信息层级和视觉；该页从未有过 G5 高保真画稿。没有新 token、没有新的共享组件。触发 L3 条件 1，需要产品负责人在 Penpot review。

## 7. 批准后的代码改动（本轮不做）

1. 重写 `OnboardingView` 的 body：隐藏导航栏；按选定方案用 `.fcFont` / `FCSemanticColors` / `FCPrimitives` 拼装；`Image("mascot-avatar")`（xcassets 已有）；`FCButton`「添加第一位学员」→ `path.append(.editor(.firstCreate))`；`FCLinkButton`「稍后再添加」→ `viewModel.skip()`；`FCLinkButton` 链接 → `.fcBottomSheet` 打开 W-02。ViewModel 与导航逻辑不变。
2. W-02 行用 `FCHubRow` 不可点变体（M2 Phase 0 组件；若尚未合入，按 `components.md` §4.7 的规格等它合入后再接）。
3. `Localizable.xcstrings`：替换 `onboarding.kicker / lead / local / share / operator / start / skip` 的文案，新增链接与面板文案键；删除不再使用的键。
4. `FCAccessibilityID`：保留 `onboardingTitle / Start / Skip`；`onboardingLead` 指向副标题；新增链接与面板的 identifier；`onboardingLocalRule / ShareRule` 移到面板对应行。仓库中没有 UI 测试依赖这些 identifier（2026-10-10 `grep`）。
5. 本页同步登记到 `design/m2-hifi/implementation-map.md`（或本文转正），导出 2 倍图；README §9 吉祥物用途补一行。
6. 验证：`xcodebuild build` + `FineCoachTests`（`DesignValueScanTests` 覆盖 feature 源码不出现原始值）+ `FineCoachIntegrationTests`；入口与布局清单（每个控件一行）。没有人工看过之前不称「已视觉验证」。

## 8. 待产品负责人决定

1. 选方案 A 还是 B（推荐 A）。
2. 是否接受「两项事实以短句常驻页面 + 详情收进链接」的做法。如果希望页面上**只剩**链接、副标题也不写事实，需要先修订 M1A-FR-001 的「MUST 在创建第一名 Student 前说明……」。
3. 从 W-01 能否返回 M2-07 重新选择（此时还没有任何 Coach 数据）。画板没有画返回按钮；这属于 T039 的导航行为，需确认后由 T039 实现。

## 9. 执行记录（`components.md` §1.5）

```text
分类与依据：B 类（改写已上线的 M1-A 首次说明页的层级与视觉；该页无 G5 画稿）。批准来源：README v1.0、components.md v1.0、M2-07 画板（G7 已批准）。
影响范围：OnboardingView（批准后）；复用 DS-BUTTON、DS-BOTTOM-SHEET、DS-HUB-ROW；新增 feature 专有 W-WELCOME；M2-07 不改。
设计决定：新决定——方案 A/B、吉祥物头像新用法、文案、链接加面板的说明方式；全部待 review。
实施与验证：设计阶段，无代码。绘制中用 1 倍导出做排版自查（修正了面板中两处单字换行、拖动条位置），不是视觉验收。
结果：Penpot 画板 3 块，快照见 §1；File.validate() 0 错误。待产品负责人 review；没有代码改动；没有人工视觉验收。
```
