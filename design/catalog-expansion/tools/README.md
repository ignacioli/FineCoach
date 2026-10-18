# C′ 动作库扩充：候选清单脚本

第 1 步只产出候选清单和这两支脚本；不改 `provenance.json`、schema、Swift 代码或 001 spec 正文。

## 重跑

从 worktree 根目录运行，只需要 `python3` 标准库：

```sh
# 1. 来源核对（网络 + 缓存）。首次或要重新下载来源时用 --refresh；
#    之后离线重跑只读 design/catalog-expansion/source/cache/。
python3 -I design/catalog-expansion/tools/verify_sources.py --refresh
python3 -I design/catalog-expansion/tools/verify_sources.py

# 2. 生成候选清单（读 match-audit.csv + verified-sources.json + 现有 provenance.json）
python3 -I design/catalog-expansion/tools/build_candidates.py
```

输出：

| 文件 | 说明 |
|---|---|
| `design/catalog-expansion/catalog-review-300.md` | 候选清单（待产品负责人审核） |
| `design/catalog-expansion/source/cache/verified-sources.json` | 来源核对的确定性结果（free-exercise-db + wger） |
| `design/catalog-expansion/source/cache/free-exercise-db/exercises.json` | fedb 原始下载缓存（固定 SHA-256） |
| `design/catalog-expansion/source/cache/wger/exerciseinfo-<id>.json` | 92 个 wger 条目的原始下载缓存 |

## 确定性

- `verify_sources.py`：普通运行不联网，只用缓存 + 缓存清单里的下载日期/ SHA-256 重算；
  `--refresh` 会重写缓存。两次普通运行的 `verified-sources.json` 必须逐字节相同。
  缓存缺失、损坏或 SHA 不符时非零退出并提示 `--refresh`。
- `build_candidates.py`：两次运行输出逐字节相同。判断表（改名、记录方式、单侧默认、
  `low` 行建议、疑似重复、待决问题）都写在脚本里，脚本不改冻结的输入数据。

## 输入与数据说明

- 输入是 `~/Downloads/FineCoach/exercise-catalog/` 在 2026-10-17 的原样副本，放在
  `design/catalog-expansion/source/2026-10-17/`，`_backup/` 未复制；`match-audit.csv`
  是主表（569 行）。
- `match-audit.csv` 的「文件」列把腹部表写成 `腹部健身器械动作分类表.md`，交付的文件名是
  `腹部健身动作分类表.md`；脚本只用审计表的行，不改输入。
- wger 署名表与 API 有 8 处写法差异（`wger-attribution.csv` 的 author 写 `-`，API 是空串，
  id 984/985/988/999/1188/1830/1935/2631），不是内容冲突，记录在
  `verified-sources.json` 的 `checks.wgerAttributionMismatches`。
- free-exercise-db 版本按 `source/2026-10-17/out/SOURCES.md` 的 SHA-256 校验
  （`5bb747e3…95d40bf`，876 条）。
