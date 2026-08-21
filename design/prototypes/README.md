# FineCoach 低保真原型

这是 FineCoach（精练教练）discovery 阶段的可点击低保真线框集合，供产品负责人走查。它不是批准 PRD，也不代表已选定实现栈。

来源输入：`specs/ideas.md`（discovery input）、`specs/CONTEXT.md`（领域术语）。生成在 Open Design 项目中完成，再复制到本目录。

## 约定

- 目标：iPhone 竖屏（约 393×852），浅色模式，简体中文。
- 形态：结构化灰盒线框，带旁注。不是高保真品牌视觉。
- 数据：仅虚构姓名与记录。不含真实学员资料。
- 资源：自包含 HTML。无外链、CDN、远程字体或远程图片。
- 系统界面：分享面板、文件选择器、通知授权只画调用边界，不伪造系统内部 UI。
- 阶段隔离：M1-A 稿不混入 M1-B / M2 能力；英文领域词（Appointment、Session、Student 等）不出现在界面文案。

每个模块页头标明：`stage`、`module`、`version`、`coverage`、`data`、`network`、`review`。

## 目录

```text
design/prototypes/
├── README.md
├── manifest.json
├── shared/
│   ├── glossary.md    界面用词
│   ├── privacy.md     分享与敏感字段边界
│   └── states.md      跨模块状态
├── m1-a/              第一里程碑前半
├── m1-b/              第一里程碑后半
└── m2/                个人训练档案
```

模块清单与走查状态见 `manifest.json`。

## 走查顺序（建议）

1. M1-A `01` → `02` → `03` → `04` → `05` → `06` → `07`：学员根页面到课堂闭环、分享、备份。
2. M1-B：今日/排课、课包、模板与分区、身体数据与趋势。
3. M2：档案导出与只读查看模式。

模块之间的「出口」只画目的地标签，不把其他模块的完整内部页嵌进来。
