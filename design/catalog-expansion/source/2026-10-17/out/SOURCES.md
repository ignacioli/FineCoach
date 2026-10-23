# 数据来源、方法与许可说明

本目录的 10 个 markdown 文件在原「器材 / 动作名称」两列基础上，补齐了 4 列：主要肌肉群、次要肌肉群、动作英文名、开放许可库。
共 569 行有效数据（源文件 577 行，删除 8 行同文件内完全重复的行）。

## 使用的开源数据源

### 1. free-exercise-db（主库，432 行引用）
- 仓库：https://github.com/yuhonas/free-exercise-db
- 数据文件：`dist/exercises.json`，876 条动作
- 下载时间：2026-10-17；SHA-256：`5bb747e3fc658f095a60dcbf6d53c96627acdcc6ffb6fffde86f7e26995d40bf`
- 许可：**Unlicense（公共领域）**，可自由使用、修改、分发，无需署名
- 字段：name / equipment / primaryMuscles / secondaryMuscles / category / force / level / instructions / images

### 2. wger（二级库，116 行引用 / 92 个条目）
- 仓库：https://github.com/wger-project/wger ｜ 数据接口：`https://wger.de/api/v2/exerciseinfo/`
- 拉取时间：2026-10-17；共 932 条动作
- 许可：逐条不同 —— 其中 CC-BY-SA 4.0 **79** 条、CC-BY-SA 3.0 **9** 条、CC0 **4** 条
- **署名要求**：CC-BY-SA 条目需保留原作者署名并以相同许可共享衍生内容。逐条作者、许可与原文链接见
  `reports/wger-attribution.csv`（列为 wger_id / name / license / license_url / author / exercise_url）。
- 中文说明：wger 目前**没有中文条目**（语言列表中无 zh），因此中文名→英文名由本项目按动作模式+器材人工对照完成，wger 只提供英文名与肌肉数据。

## 肌肉中文词表（粗粒度，与库的 15 个 muscle key 对齐）
胸大肌、三角肌、背阔肌、斜方肌、菱形肌、竖脊肌、肱二头肌、肱三头肌、前臂肌、腹肌、腹斜肌、臀大肌、臀中肌、腘绳肌、股四头肌、小腿肌、颈部、内收肌、髋外展肌

- 库映射：abdominals→腹肌｜biceps→肱二头肌｜calves→小腿肌｜chest→胸大肌｜forearms→前臂肌｜glutes→臀大肌｜hamstrings→腘绳肌｜lats→背阔肌｜lower back→竖脊肌｜middle back→菱形肌｜neck→颈部｜quadriceps→股四头肌｜shoulders→三角肌｜traps→斜方肌｜triceps→肱三头肌
- 库未覆盖时按解剖常识补充：腹斜肌（转体/侧弯类）、臀中肌（髋外展类）

## 匹配方法
1. 中文名拆为「器材 + 动作模式 + 变式」三段，翻译为英文后与库条目做名称/器材匹配；变式按 Incline/Decline/Wide-Grip/Close-Grip/Reverse/One-Arm/Seated/Standing/Hanging 等逐项落位。
2. 品牌/编号器械（悍马机、哈克机、器械 -V2/V3/V4、蝴蝶机 -V2 等）映射到最接近的**通用**库条目，置信度 medium，`match-audit.csv` 的「备注」列写明理由。
3. 库中确无合理对应（弹力带/悬挂带专有条目缺失、特殊器械、纯拉伸等）时：动作英文名与开放许可库列填 `-`，肌肉群仍按解剖常识填写 —— 共 21 行。
4. 同一动作在不同文件中保持英文名与肌肉群一致（按「器材+动作名」建立全局映射表）。
5. 英文名仅做排版规范化（3 条全小写 wger 名称首字母大写、2 条 en dash 改连字符）；`match-audit.csv` 保留「库内原始英文名」与条目 ID，可逐字溯源。

## 置信度
| 等级 | 行数 | 含义 |
|---|---|---|
| high | 332 | 名称/动作模式/器材与库条目明确一致 |
| medium | 216 | 品牌器械→通用条目、变式近似、弹力带/悬挂带映射到同动作条目 |
| low | 21 | 库中无对应条目（英文名与库列留空） |

## 目录结构
```
exercise-catalog-fixed/      补齐后的 10 个 markdown 文件
reports/
  match-audit.csv            逐行审计表（569 行，含置信度与备注）
  wger-attribution.csv       wger 条目的署名/许可清单（92 条）
README-变更报告.md            变更明细（去重、器材归一、已填值改写、未匹配清单、覆盖方法）
SOURCES.md                   本文件
```
