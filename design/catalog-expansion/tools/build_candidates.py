#!/usr/bin/env python3
"""Build the C' catalog-expansion candidate review from the frozen 2026-10-17 inputs.

Reads:
  design/catalog-expansion/source/2026-10-17/    frozen copy of the external tables + reports
  design/catalog-expansion/source/cache/verified-sources.json   source verification (verify_sources.py)
  ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json    the current 146-entry catalog

Writes:
  design/catalog-expansion/catalog-review-300.md

The script is deterministic: two runs on the same inputs and cache produce a
byte-identical review. Run from anywhere with the stdlib only:

    python3 -I design/catalog-expansion/tools/build_candidates.py

Mechanical rules applied (see the task prompt, 2026-10-17):
  * equipment normalised to the 13-value CX-D1 enum (CX-D7: plate/hex/landmine -> 杠铃);
  * muscle -> body-part mapping of the prompt only; a source-table/category mismatch
    is written to the note and does not change the derived part;
  * Chinese names: CX-D3 removes 单臂/单手/单腿/单边/单侧/交替/轮换 wording, prefixes
    and separators are normalised to the existing catalog style;
  * rows already in the current catalog are matched by English name (case and
    punctuation insensitive), wger UUID and Chinese name and are not added;
  * identical (equipment, Chinese name) rows after normalisation are merged;
  * each entry records source + license (free-exercise-db Unlicense, wger CC per
    entry, finecoach-built entries use MIT under CX-D5).

Judgement calls that the mechanical rules cannot make live in the *_OVERRIDES /
*_TABLES below, keyed by "<short table name>:<line in that table>". They never
change the frozen input data; they only decide the candidate row and its note.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import subprocess
import unicodedata
from collections import OrderedDict, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "design/catalog-expansion/source/2026-10-17"
CACHE = ROOT / "design/catalog-expansion/source/cache/verified-sources.json"
PROVENANCE = ROOT / "ios/FineCoachApp/Resources/ExerciseCatalog/provenance.json"
BASELINE_COMMIT = "96b385fe730b09171244fedb69341d0bb9f8fb47"
OUTPUT = ROOT / "design/catalog-expansion/catalog-review-300.md"

AUDIT_CSV = SOURCE / "out/reports/match-audit.csv"

PART_ORDER = ["胸", "肩", "背", "大腿", "小腿", "臂", "臀", "核心"]
EQUIP_ORDER = [
    "杠铃", "哑铃", "固定器械", "史密斯机", "绳索", "哈克机", "壶铃",
    "徒手", "悍马机", "弹力带", "悬挂带", "单杠", "其他",
]
PENDING = "待决"

MUSCLE_PART = {
    "胸大肌": "胸",
    "三角肌": "肩",
    "背阔肌": "背", "斜方肌": "背", "菱形肌": "背", "竖脊肌": "背",
    "肱二头肌": "臂", "肱三头肌": "臂", "前臂肌": "臂",
    "腹肌": "核心", "腹斜肌": "核心",
    "臀大肌": "臀", "臀中肌": "臀", "髋外展肌": "臀",
    "股四头肌": "大腿", "腘绳肌": "大腿", "内收肌": "大腿",
    "小腿肌": "小腿",
    "颈部": PENDING,
}

FILE_SHORT = {
    "胸部健身器械动作分类表.md": "胸",
    "肩部健身器械动作分类表.md": "肩",
    "背部健身器械动作分类表.md": "背",
    "腿部健身器械动作分类表.md": "腿",
    "小腿部健身器械动作分类表.md": "小腿",
    "上臂健身器械动作分类表.md": "上臂",
    "小臂部健身器械动作分类表.md": "小臂",
    "臀部健身器械动作分类表.md": "臀",
    "腹部健身器械动作分类表.md": "腹",
    "核心健身动作分类表.md": "核心",
}
FILE_PART = {
    "胸部健身器械动作分类表.md": "胸",
    "肩部健身器械动作分类表.md": "肩",
    "背部健身器械动作分类表.md": "背",
    "腿部健身器械动作分类表.md": "大腿",
    "小腿部健身器械动作分类表.md": "小腿",
    "上臂健身器械动作分类表.md": "臂",
    "小臂部健身器械动作分类表.md": "臂",
    "臀部健身器械动作分类表.md": "臀",
    "腹部健身器械动作分类表.md": "核心",
    "核心健身动作分类表.md": "核心",
}

# ---------------------------------------------------------------------------
# Candidate rows: canonical Chinese names decided by the prompt rules where they
# are unambiguous. Keyed by "<short table>:<line>". A missing key means the
# generic normaliser (CX-D3 marker removal, separator clean-up) is enough.
# ---------------------------------------------------------------------------
NAME_OVERRIDES = {
    # Names that are the same movement as an existing entry, normalised to the
    # existing catalog's wording so the "already in library" rule catches them.
    "腿:3": "杠铃深蹲",
    "腿:6": "杠铃前蹲",
    "腿:7": "杠铃硬拉",
    "腿:12": "直腿硬拉",
    "腿:74": "弹力带站姿外展",
    "胸:3": "杠铃平板卧推",
    "胸:5": "杠铃下斜卧推",
    "胸:8": "杠铃上斜卧推",
    "胸:11": "哑铃平板卧推",
    "胸:12": "哑铃上斜卧推",
    "胸:14": "哑铃飞鸟",
    "胸:16": "哑铃上斜飞鸟",
    "胸:20": "哑铃平板卧推",
    "胸:29": "助力双杠臂屈伸",
    "上臂:36": "杠铃弯举",
    "上臂:42": "V把下压",
    "上臂:43": "绳索下压",
    "背:3": "宽握高位下拉",
    "背:4": "绳索直臂下拉",
    "背:7": "坐姿绳索划船",
    "背:9": "坐姿绳索划船",
    "背:16": "绳索直臂下拉",
    "背:23": "杠铃俯身划船",
    "背:59": "哑铃俯身划船",
    "肩:39": "杠铃肩上推举",
    "肩:52": "绳索前平举",
    "小腿:13": "腿举提踵",
    "腹:8": "死虫式",
    "臀:11": "杠铃早安式",
    "上臂:5": "坐姿哑铃牧师凳弯举",       # One Arm Dumbbell Preacher Curl
    "上臂:13": "坐姿哑铃臂屈伸",          # Seated Bent-Over One-Arm ...
    "上臂:17": "哑铃牧师凳弯举",          # One Arm Dumbbell Preacher Curl
    "上臂:45": "绳索三头肌臂屈伸",        # Cable One Arm Tricep Extension
    "上臂:48": "背后绳索弯举",            # Standing One-Arm Cable Curl
    "上臂:62": "器械牧师凳弯举",          # Machine Preacher Curls
    "核心:4": "平板支撑摆腿",             # Plank with Alternating Leg Lift
    "核心:9": "平板手肘支撑",             # Plank-to-Elbow Extension
    "肩:21": "哑铃上斜Y字举",             # low row, recommended adopt
    "肩:49": "悍马机开肘俯身飞鸟",        # Reverse Machine Flyes
    "肩:58": "肩胛骨后缩热身",            # low row, recommended adopt
    "肩:59": "肩胛骨上回旋热身",
    "肩:60": "肩胛骨下回旋热身",
    "肩:63": "悬挂带面拉",                # equipment pending (see Q1)
    "肩:72": "悬挂带后束飞鸟",            # equipment pending (see Q1)
    "肩:73": "弹力带耸肩",                # low row, recommended adopt
    "肩:74": "V字俯卧撑",
    "肩:75": "V字俯卧撑(负重)",
    "肩:80": "侧转肩拉伸",
    "肩:84": "派克俯卧撑(辅助)",
    "背:17": "绳索下拉",                  # One Arm Lat Pulldown
    "背:21": "绳索俯身划船",              # Shotgun Row, raw name truncated
    "背:11": "宽握高位下拉",              # Wide-Grip Lat Pulldown, raw name truncated
    "背:22": "绳索分腿站姿下拉",          # One Arm Lat Pulldown, raw name truncated
    "背:39": "支撑式悍马划船",
    "背:45": "坐姿悍马机划船",
    "背:60": "哑铃划船(手撑)",
    "胸:81": "持杆扩胸拉伸",
    "胸:82": "辅助胸廓拉伸",
    "腿:39": "站姿腿弯举",                # Standing Leg Curl, same movement as existing
    "腿:46": "腿屈伸",                    # Single-Leg Leg Extension, CX-D4 same movement
    "腿:76": "弹力带深蹲",                # Squats - With Bands
    "腿:87": "膝关节绕环热身",
    "腿:88": "前后摆腿热身",
    "腿:89": "滑雪式拉伸",                # low row, recommended adopt
    "腿:90": "坐姿腿拉伸",
    "腿:92": "箭步蹲拉伸",
    "腿:95": "站姿腿拉伸",
    "臀:19": "史密斯臀冲",                # low row, recommended adopt
    "臀:46": "泡沫轴臀部放松",            # foam-roll release, not a stretch
    "臀:66": "挂片罗马尼亚硬拉",          # raw name truncated
    "上臂:66": "弹力带站姿弯举",          # low row, recommended adopt
    # CX-D3 / catalog-style name normalisation round two.
    "上臂:55": "绳索弯举",
    "肩:8": "哑铃侧平举",
    "肩:10": "哑铃半俯身侧平举",
    "肩:11": "哑铃前平举",
    "肩:12": "哑铃后束飞鸟",
    "肩:15": "哑铃上斜俯卧后束飞鸟",
    "肩:16": "哑铃上斜仰卧臂上举",
    "肩:33": "站姿杠铃推举",
    "肩:38": "站姿杠铃推举",
    "肩:48": "悍马机半俯身侧平举",
    "肩:50": "悍马机开肘俯身划船",
    "背:5": "坐姿绳索划船",
    "背:13": "窄握高位下拉",
    "背:19": "坐姿绳索划船",
    "背:36": "分动式高位划船",
    "背:43": "悍马机高位下拉",
    "背:88": "山羊挺身",
    "胸:15": "仰卧旋转展臂",
    "腿:13": "杠铃保加利亚蹲",
    "腿:79": "弹力带螃蟹行走",
    "腹:14": "仰卧抬腿",
    "腹:21": "仰卧抬腿",
    "腹:22": "健腹轮",
    "臀:69": "壶铃摆荡",
    "核心:9": "平板肘撑转换",
    "腹:9": "徒手俄罗斯转体",  # CX-D12
    "腿:23": "哑铃罗马尼亚硬拉",  # CX-D12
}

# recordMode for rows where the generic rule would be wrong (or where the
# source equipment label hides a bodyweight movement).
MODE_OVERRIDES = {
    "背:49": "reps",      # V-Bar Pullup listed under 固定器械
    "背:54": "reps",      # Band Assisted Pull-Up listed under 固定器械
    "核心:5": "duration", # 固定熊爬 stationary bear crawl hold
    "核心:9": "reps",     # 平板交替手肘支 Plank-to-Elbow is alternating, counted
    "腿:84": "reps",      # 北欧腿弯举 bodyweight, source equipment 其他
    "腿:86": "reps",      # 跳箱 bodyweight plyometrics, source equipment 其他
    "腿:85": "reps",      # 臀桥 bodyweight, source equipment 其他 (already in library)
    "腿:79": "duration", # A1 overrides the band reps rule
    "臀:60": "duration", # Same normalized crab-walk movement, merged with 腿:79
    "腿:82": "reps",      # 悬吊带深蹲 bodyweight suspension squat
    "臀:39": "duration",  # 仰卧交叉腿 Lying Crossover is a stretch
}

# CX-D6 unilateral defaults that the name/English heuristics cannot infer.
UNILATERAL_TRUE = {
    "腿:13",   # 杠铃保加利亚蹲
    "腿:31",   # 哑铃保加利亚蹲
    "腿:57",   # 自重保加利亚蹲
    "腿:61",   # 手枪深蹲
    "腿:83",   # 保加利亚蹲(负重)
    "腿:66",   # 弹力带提腿
    "腿:70",   # 弹力带站姿踢腿
    "臀:52",   # 绳索侧踢 (standing hip abduction)
    "臀:53",   # 绳索站姿臀冲 (cable hip extension, cf. P0-14)
    "臀:65",   # 挂片后摆腿 (machine glute kickback, cf. P0-14)
    "臀:68",   # 站姿髋外展
    "腿:52",   # 史密斯机上踢 (machine glute kickback, cf. P0-14)
    "腿:81",   # 弹力带仰卧腿外展
    # One-side-at-a-time stretching / warm-up rows (CX-D6; P0-14 has no stretch
    # precedent, so this is stated explicitly in the review's notes).
    "小腿:6",  # 墙面小腿拉伸
    "小腿:7",  # 墙面比目鱼肌拉伸
    "小腿:8",  # 坐姿腓骨肌拉伸
    "小臂:11", # 手腕屈肌拉伸
    "小臂:12", # 手腕伸肌拉伸
    "肩:78",   # 肩内外旋拉伸
    "肩:81",   # 三头肌拉伸
    "肩:82",   # 手臂交叉拉伸
    "腿:88",   # 前后摆腿热身
    "腿:90",   # 坐姿腿拉伸
    "腿:92",   # 箭步蹲拉伸
    "腿:94",   # 仰卧抬腿拉伸
    "腿:95",   # 站姿腿拉伸
    "腿:97",   # 髋屈肌与股四头肌拉伸
    "臀:39",   # 仰卧交叉腿
    "臀:41",   # 侧向摆腿热身
    "臀:44",   # 坐姿梨状肌拉伸
    "臀:45",   # 仰卧四字臀肌拉伸
    "臀:46",   # 泡沫轴臀部放松
    "臀:47",   # 滚轮腿交叉拉伸
    "臀:43",   # 抱膝提拉热身（交替单腿）
    "小腿:9",  # 跪姿胫骨肌拉伸（泡沫轴单侧）
}
UNILATERAL_FALSE = set()

# Row-specific notes that are not derivable from the input columns. Merged with
# the generated notes in the review's 备注 / 待决 column.
ROW_NOTES = {
    "上臂:45": "原名疑缺「臂屈伸」",
    "上臂:66": "low 行，建议采纳（附录 A）；CX-D5 自建条目",
    "背:21": "原名疑缺「船」",
    "背:22": "原名「绳索分腿站姿单绳」不完整",
    "背:39": "原名「单手支撑式悍马」不完整",
    "背:45": "原名「单手坐悍马机」不完整",
    "肩:21": "low 行，建议采纳（附录 A）；CX-D5 自建条目",
    "肩:49": "原名「单手开肘悍马俯」不完整",
    "肩:58": "low 行，建议采纳（附录 A）；热身命名见 Q3",
    "肩:63": "器械待决：原名前缀「悬垂带」不在归一规则内（Q1）",
    "肩:72": "器械待决：原名前缀「悬垂带」不在归一规则内（Q1）",
    "肩:73": "low 行，建议采纳（附录 A）；CX-D5 自建条目",
    "上臂:55": "待决：原名「绳索训练器」不是动作名（Q5）",
    "腿:85": "已在库（徒手臀桥）",
    "腿:89": "low 行，建议采纳（附录 A）；CX-D5 自建条目",
    "臀:19": "low 行，建议采纳（附录 A）；CX-D5 自建条目",
    "臀:46": "泡沫轴放松，按 CX-D8 收入；不是拉伸；Q8：按泡沫轴放松记时长",
    "臀:66": "原名疑缺「硬拉」",
    "腿:35": "待决 Q6：同一动作在臀:3 器械写哈克机",
    "腿:82": "器械待决：原名前缀「悬吊带」不在归一规则内（Q1）",
    "臀:3": "待决 Q6：同一动作在腿:35 器械写固定器械",
    "上臂:28": "Q7：与现有「仰卧臂屈伸(碎颅者)」疑同一动作",
    "上臂:37": "Q7：与现有「仰卧臂屈伸(碎颅者)」疑同一动作",
    "上臂:29": "Q7：与现有「窄距卧推」近似",
    "上臂:35": "Q7：与现有「窄距卧推」近似",
    "肩:3": "Q7：与现有「哑铃肩上推举」近似",
    "肩:33": "Q7：与现有「杠铃肩上推举」近似",
    "背:52": "Q7：与现有「坐姿绳索划船」近似",
    "背:50": "Q7：与现有「胸撑器械划船」近似",
    "背:57": "Q7：与现有「单臂哑铃划船」（第 2 步改名为「哑铃支撑划船」）同一动作",
    "背:60": "Q7：与现有「单臂哑铃划船」（第 2 步改名为「哑铃支撑划船」）同一动作",
    "腹:42": "Q7：与现有「龙门架卷腹」近似",
    "腹:44": "Q7：与现有「龙门架卷腹」近似",
    "臀:10": "Q7：与现有「山羊挺身」近似",
    "核心:5": "Q8：按静止熊爬记时长",
    "核心:9": "Q8：按交替动作记次数",
    "腹:34": "名字是「摇摆」但源条目是 Hollow Hold 静态支撑，按时长",
    "臀:39": "Q8：源条目 Lying Crossover 是拉伸，按时长",
    "臀:31": "Q4：原名「哑铃单腿罗马尼亚硬拉」，去「单腿」后与现有「罗马尼亚硬拉」近似，默认单侧",
    "臀:40": "Q4：去掉「单腿」后与现有「徒手臀桥」近似，默认单侧",
    "腿:83": "来源器材为「其他」，按规则保留",
    "腿:86": "来源器材为「其他」，按规则保留",
    "胸:44": "Q10：来源器材写固定器械，实际为史密斯机",
    "胸:45": "Q10：来源器材写固定器械，实际为史密斯机",
    "胸:46": "Q10：来源器材写固定器械，实际为史密斯机",
    "胸:47": "Q10：来源器材写固定器械，实际为史密斯机",
}

# The 21 low-confidence rows: product-owner decision required. recommend=True
# rows are proposed for adoption as finecoach-built entries (CX-D5: MIT).
LOW_ROWS = OrderedDict([
    ("上臂:66", (True, "弹力带站姿弯举", "弹力带", "reps", False, "臂", [],
                 "弹力带站姿弯举是带新手、课前热身的常规手臂动作，现有目录弹力带器械完全空白。")),
    ("上臂:67", (False, "", "", "", False, "", [],
                 "与上臂:66 只差轮换节奏，CX-D3 又不能在名字里写交替，收进来是两条几乎一样的记录。")),
    ("上臂:70", (False, "", "", "", False, "", [],
                 "坐姿只是同一弹力带弯举换体位，教练课不会分开记录，站姿版已足够。")),
    ("上臂:80", (False, "", "", "", False, "", [],
                 "「铃铃」是明显错字、器材列又填「无」，动作无法确认；按哑铃或杠铃读都会撞现有条目。")),
    ("肩:21", (True, "哑铃上斜Y字举", "哑铃", "weightReps", False, "肩", ["背"],
               "上斜 Y 字举是肩后束/下斜方肌和圆肩改善的常用辅助动作，现有「哑铃后束飞鸟」方向不同。")),
    ("肩:58", (True, "肩胛骨后缩热身", "绳索", "duration", False, "肩", ["背"],
               "肩胛骨后缩是肩带热身和圆肩矫正常规练习；同表上/下回旋两条已按 medium 自动收录，缺后缩就断了序列。")),
    ("肩:73", (True, "弹力带耸肩", "弹力带", "reps", False, "背", [],
               "弹力带耸肩是弹力带热身和斜方肌基础训练常规动作；现有耸肩只有杠铃/哑铃/史密斯/绳索。")),
    ("背:18", (False, "", "", "", False, "", [],
               "「站旋转划」名称残缺，不是标准动作名；划船和转体已分别被「坐姿绳索划船」「站姿绳索转体」覆盖。")),
    ("背:75", (False, "", "", "", False, "", [],
               "悬挂带坐姿下拉还要额外负重，固定方式别扭，不是教练课会用的做法；悬挂带拉类已有深蹲划船/水平划船。")),
    ("背:80", (False, "", "", "", False, "", [],
               "单臂弹力带划船与已收录弹力带俯身/坐姿划船是同一动作的单侧版，去「单手」后无法区分。")),
    ("背:86", (False, "", "", "", False, "", [],
               "反手弹力带下拉只是已收录「弹力带高位下拉」的握法变式，弹力带下拉已有四条。")),
    ("腹:48", (False, "", "", "", False, "", [],
               "跪姿卷腹已被「绳索跪姿卷腹」覆盖，弹力带仰卧卷腹也已收录，不新增动作模式。")),
    ("腹:50", (False, "", "", "", False, "", [],
               "「下上转体」不是通用动作名，与「上下转体」只差字序、肌肉列相同，无法确认区别。")),
    ("腹:51", (False, "", "", "", False, "", [],
               "与腹:50 只差字序、肌肉列完全相同，是重复行。")),
    ("腹:52", (False, "", "", "", False, "", [],
               "「十字转体」名称不通用、动作路线无法确认；旋转/抗旋已由绳索转体、帕洛夫、伐木覆盖。")),
    ("腿:65", (False, "", "", "", False, "", [],
               "现有目录已有「手枪深蹲」，支撑版只是同一动作的退阶，CX-D3 又不许名字写「有支撑」，收进来就是重名。")),
    ("腿:73", (False, "", "", "", False, "", [],
               "「仰卧登山者」不是通用动作名、动作形式不清；已收录「弹力带登山者」。")),
    ("腿:80", (False, "", "", "", False, "", [],
               "弹力带鸭步是田径式热身，教练课记录频率低；同类弹力带走类已有「弹力带螃蟹行走」。")),
    ("腿:89", (True, "滑雪式拉伸", "徒手", "duration", False, "大腿", [],
               "滑雪式（宽距体前屈）是腘绳肌+内收肌的常见静态拉伸；现有「直腿弯腰」是窄距版，覆盖不了内收肌。")),
    ("臀:19", (True, "史密斯臀冲", "史密斯机", "weightReps", False, "臀", ["大腿", "小腿"],
               "史密斯机臀冲是健身房臀冲的主流器械做法，现有目录只有杠铃臀冲和徒手臀桥，史密斯版是真实需要的器械区分。")),
    ("臀:23", (False, "", "", "", False, "", [],
               "「俯卧蛙」是青蛙式臀激活的非标准叫法，史密斯机上怎么做无法确认；同类已有哑铃青蛙臀桥、摇摆青蛙式。")),
])

# Questions the product owner has to decide; each renders as one line in the
# review header. Referenced from ROW_NOTES / appendix rows.
QUESTIONS = [
    "Q1 器械待决 3 行：「悬垂带 - 面拉」「悬垂带 - 后束飞鸟」「悬吊带深蹲」的「悬垂带/悬吊带」是不是「悬挂带」笔误？若是，3 行器械改悬挂带；面拉与后束飞鸟的 recordMode 相应改为 reps（悬吊带深蹲已是 reps）。",
    "Q2 弹力带/悬挂带动作的 recordMode：本表把弹力带阻力视为负重、记 weightReps（重量栏填阻力值），悬挂带（TRX）是自重、记 reps；是否认可？",
    "Q3 热身类命名：本表统一为「动作 + 热身」并去掉「灵活性」「小幅」等描述词（如 肩胛骨后缩热身、膝关节绕环热身）；是否确认这一约定？",
    "Q4 去掉「单腿/单手/单臂」后与现有条目重名，按提示词规则第 6 条当作「已在库」，单侧变式因此不入库：单手俯卧撑→俯卧撑、杠铃单腿硬拉→杠铃硬拉、单腿哑铃硬拉→哑铃硬拉、哑铃轮换弯举→哑铃弯举；另有单腿臀桥、单腿罗马尼亚硬拉改成近似名后仍新增。是否接受，还是给单侧变式保留可区分名字（沿用 CX-D4 的「支撑/分腿」写法）？",
    "Q5 「绳索训练器」（上臂:55）不是动作名，映射到 Standing Biceps Cable Curl；是否按「绳索弯举」合并、不单独收录？",
    "Q6 哈克机深蹲：腿:35（固定器械）与臀:3（哈克机）是同一动作、器械列又互相矛盾，且都与现有「哈克深蹲」是同一动作；建议两行都按现有「哈克深蹲」处理、不再新增，是否确认？",
    "Q7 疑似重复：附录 E 列出机械规则没有判重、但实际是同一动作的候选↔现有配对（如 仰卧杠铃臂屈伸 vs 仰卧臂屈伸(碎颅者)、窄距卧推(靠近/散开) vs 窄距卧推、杠铃碎颅者 vs 仰卧臂屈伸(碎颅者)、哑铃推举 vs 哑铃肩上推举、哑铃划船/哑铃划船(手撑) vs 单臂哑铃划船），以及共用同一 wger 条目、但来源表器械/变式不同而按新条目保留的 10 行（如 悍马机侧平举 vs 器械侧平举）；请逐条确认是否按「已在库」处理。",
    "Q8 recordMode 拿不准的 4 行：「固定熊爬」按静止支撑记 duration、「平板肘撑转换」按交替动作记 reps、「仰卧交叉腿」按拉伸记 duration、「泡沫轴臀部放松」按泡沫轴放松记 duration；是否认可这 4 个判断？",
    "Q9 附录 A 的 21 条 low 行：本表建议采纳 6 条、不采纳 15 条；请逐条确认（采纳的按 CX-D5 记为 FineCoach 自建、MIT 许可）。",
    "Q10 来源表器材列不一致：胸表 44-47 行（史密斯机卧推、上斜/下斜史密斯机卧推、史密斯机 V-bar）写「固定器械」，其余表同类动作用「史密斯机」，且现有目录把同类动作归「史密斯机」；建议统一为「史密斯机」，是否确认？",
]


def nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text).strip()


def norm_english(text: str) -> str:
    """Case- and punctuation-insensitive English name key."""
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def split_muscles(text: str) -> list[str]:
    text = nfc(text)
    if text in ("", "-"):
        return []
    return [piece.strip() for piece in re.split("[、,，]", text) if piece.strip()]


def strip_separators(name: str) -> str:
    name = re.sub(r"\s*[-—－]\s*", "", name)
    name = re.sub(r"\s+", "", name)
    name = re.sub(r"V-?Bar", "V把", name, flags=re.I)
    name = re.sub(r"T-?[Bb]ar", "T杠", name)
    return name


def base_name(raw: str) -> str:
    """CX-D3 normalisation: prefixes -> suffix, separators, unilateral wording."""
    raw = raw.replace("悬垂带", "悬挂带").replace("悬吊带", "悬挂带")
    name = nfc(raw).replace("（", "(").replace("）", ")")
    match = re.match(r"^(拉伸|热身)\s*[-—－]?\s*(.+)$", name)
    if match:
        tag, rest = match.group(1), match.group(2).strip()
        suffix = re.match(r"^(.*?)(\([^()]*\))$", rest)
        name = (suffix.group(1) + tag + suffix.group(2)) if suffix else (rest + tag)
    name = strip_separators(name)
    for word in ["双臂", "双侧", "单臂", "单手", "单腿", "单边", "单侧", "交替", "轮换"]:
        name = name.replace(word, "")
    name = re.sub(r"^(弹力带|悬挂带|悬垂带|悬吊带)\1", r"\1", name)
    name = re.sub(r"\(\s*\)", "", name)
    return name


def normalise_equipment(raw_equipment: str, raw_name: str) -> tuple[str, str]:
    """Return (equipment enum value or 待决, note)."""
    if raw_equipment == "无":
        return "徒手", ""
    if raw_equipment in ("杠铃片", "六角杆", "地雷杆"):
        return "杠铃", "器械归一：%s→杠铃（CX-D7）" % raw_equipment
    if raw_equipment == "悬挂带 & 弹力带":
        if "弹力带" in raw_name:
            return "弹力带", "器械按名称拆分：悬挂带 & 弹力带→弹力带"
        if any(prefix in raw_name for prefix in ("悬挂带", "悬垂带", "悬吊带", "TRX")):
            return "悬挂带", "器械按名称拆分：悬挂带 & 弹力带→悬挂带"
        return PENDING, "器械待决：名称不含弹力带/悬挂带/TRX"
    return raw_equipment, ""


def derive_parts(row: dict) -> tuple[str, list[str], list[str]]:
    """Return (primary part, secondary parts, unmapped muscle tokens)."""
    primary_muscles = split_muscles(row["primary_muscles"])
    secondary_muscles = split_muscles(row["secondary_muscles"])
    unmapped = [m for m in primary_muscles + secondary_muscles if m not in MUSCLE_PART]
    primary_parts = [MUSCLE_PART.get(m, PENDING) for m in primary_muscles]
    secondary_parts = [MUSCLE_PART.get(m, PENDING) for m in secondary_muscles]
    primary = primary_parts[0] if primary_parts else PENDING
    secondary = {p for p in primary_parts[1:] + secondary_parts if p not in (PENDING, primary)}
    ordered = [p for p in PART_ORDER if p in secondary]
    return primary, ordered, unmapped


def derive_mode(row: dict, equipment: str, category: str) -> str:
    key = row["_key"]
    if key in MODE_OVERRIDES:
        return MODE_OVERRIDES[key]
    raw = row["raw_name"]
    if raw.startswith(("拉伸", "热身")):
        return "duration"
    if any(word in raw for word in (
        "平板支撑", "静态侧卧支撑", "反向支撑", "空心", "L坐", "L 坐",
        "靠墙静蹲", "平板手肘撑", "农夫走", "提走",
    )):
        return "duration"
    loaded = "负重" in raw
    if not loaded and equipment in ("徒手", "单杠", "悬挂带", "弹力带"):
        return "reps"
    return "weightReps"


def derive_unilateral(row: dict) -> bool:
    key = row["_key"]
    if key in UNILATERAL_TRUE:
        return True
    if key in UNILATERAL_FALSE:
        return False
    raw = row["raw_name"]
    if re.search(r"单(臂|手|腿|边|侧|绳|推)", raw):
        return True
    english = row["english"]
    if re.search(r"One[- ]?Arm|One[- ]?Leg|Single[- ]?Arm|Single[- ]?Leg", english, re.I):
        return True
    if any(word in raw for word in (
        "后踢", "驴踢", "上凳", "上台阶", "侧躺腿外展", "蚌式", "蛤壳", "帕洛夫", "伐木", "提走",
    )):
        return True
    return False


BODYWEIGHT_EQUIPMENT = {"徒手", "单杠", "悬挂带", "其他"}


def existing_equipment(current: dict) -> str:
    """CX-D1: the catalog still stores the old 龙门架 value for cable work."""
    return "绳索" if current["equipmentClass"] == "龙门架" else current["equipmentClass"]


def equipment_compatible(equipment: str, current: dict) -> bool:
    current_equipment = existing_equipment(current)
    return equipment == current_equipment


def _display(text: str) -> str:
    """Keep a literal pipe out of Markdown table cells (display only)."""
    return text.replace("|", "｜")


def load_rows() -> list[dict]:
    with AUDIT_CSV.open(encoding="utf-8-sig") as handle:
        raw_rows = list(csv.DictReader(handle))
    rows = []
    for index, row in enumerate(raw_rows):
        short = FILE_SHORT[row["文件"]]
        rows.append({
            "_idx": index,
            "_key": "%s:%s" % (short, row["行号"]),
            "file": row["文件"],
            "file_short": short,
            "line": row["行号"],
            "raw_equipment": row["器材"],
            "raw_name": _display(row["动作名称"]),
            "primary_muscles": row["主要肌肉群"],
            "secondary_muscles": row["次要肌肉群"],
            "english": _display(row["动作英文名"]),
            "library": row["库内ID"],
            "library_english": row["库内原始英文名"],
            "confidence": row["置信度"],
            "input_note": _display(row["备注"]),
        })
    return rows


def load_baseline_manifest() -> dict:
    raw = subprocess.check_output([
        "git", "show", BASELINE_COMMIT + ":" + PROVENANCE.relative_to(ROOT).as_posix()
    ], cwd=ROOT)
    manifest = json.loads(raw)
    if len(manifest["exercises"]) != 146:
        raise ValueError("the pinned pre-expansion baseline must contain 146 exercises")
    return manifest


def load_existing() -> list[dict]:
    # The expanded output must never become its own deduplication input.
    manifest = load_baseline_manifest()
    records = {record["recordID"]: record for record in manifest["provenance"]["records"]}
    return manifest["exercises"], records


def build_entries(rows: list[dict], existing_by_english: dict, existing_by_name: dict,
                  existing_by_uuid: dict) -> dict:
    verified = json.loads(CACHE.read_text(encoding="utf-8"))
    fedb = verified["freeExerciseDB"]["exercises"]
    wger = verified["wger"]["entries"]

    entries = []
    low_rows = []
    for row in rows:
        key = row["_key"]
        raw_name = row["raw_name"]
        name = NAME_OVERRIDES.get(key) or base_name(raw_name)
        equipment, equipment_note = normalise_equipment(row["raw_equipment"], raw_name)
        if key in {"胸:44", "胸:45", "胸:46", "胸:47"}:
            equipment = "史密斯机"
            equipment_note = "Q10：史密斯机动作归史密斯机"
        primary, secondary, unmapped = derive_parts(row)

        # Source + license resolution (CX-D5, CX-D7 license rules).
        library = row["library"]
        source = ""
        source_kind = ""
        license_short = ""
        license_text = ""
        author = ""
        category = ""
        if library.startswith("fedb:"):
            library_id = library[5:]
            data = fedb.get(library_id)
            if data:
                source = "free-exercise-db:%s" % library_id
                source_kind = "free-exercise-db"
                license_short = "Unlicense"
                license_text = "Unlicense (public domain). https://unlicense.org/"
                author = "free-exercise-db"
                category = data.get("category", "")
            else:
                source = "finecoach-built"
                source_kind = "finecoach-built"
                license_short = "MIT"
                license_text = "MIT (FineCoach repository LICENSE)"
                author = "FineCoach"
        elif library.startswith("wger:"):
            wger_id = library[5:]
            data = wger.get(wger_id)
            if data:
                source = "wger.de:%s" % data["uuid"]
                source_kind = "wger"
                license_short = data["licenseShortName"]
                license_text = "%s. %s" % (data["licenseFullName"], data["licenseURL"])
                author = data["licenseAuthor"] or "wger.de"
            else:
                source = "finecoach-built"
                source_kind = "finecoach-built"
                license_short = "MIT"
                license_text = "MIT (FineCoach repository LICENSE)"
                author = "FineCoach"
        else:
            source = "finecoach-built"
            source_kind = "finecoach-built"
            license_short = "MIT"
            license_text = "MIT (FineCoach repository LICENSE)"
            author = "FineCoach"

        mode = derive_mode(row, equipment, category)
        unilateral = derive_unilateral(row)

        # Low-confidence rows are handled by the explicit recommendation table.
        if key in LOW_ROWS:
            recommend, low_name, low_equipment, low_mode, low_unilateral, low_primary, low_secondary, reason = LOW_ROWS[key]
            if not recommend:
                low_rows.append({
                    "key": key, "file_short": row["file_short"], "line": row["line"],
                    "raw_equipment": row["raw_equipment"], "raw_name": raw_name,
                    "primary_muscles": row["primary_muscles"], "secondary_muscles": row["secondary_muscles"],
                    "recommend": False, "name": "", "equipment": "", "mode": "",
                    "unilateral": False, "primary": "", "secondary": [], "reason": reason,
                    "input_note": row["input_note"],
                })
                continue
            low_rows.append({
                "key": key, "file_short": row["file_short"], "line": row["line"],
                "raw_equipment": row["raw_equipment"], "raw_name": raw_name,
                "primary_muscles": row["primary_muscles"], "secondary_muscles": row["secondary_muscles"],
                "recommend": True, "name": low_name, "equipment": low_equipment, "mode": low_mode,
                "unilateral": low_unilateral, "primary": low_primary, "secondary": low_secondary,
                "reason": reason, "input_note": row["input_note"],
            })
            name = low_name
            equipment = low_equipment
            mode = low_mode
            unilateral = low_unilateral
            primary = low_primary
            secondary = list(low_secondary)
            source = "finecoach-built"
            source_kind = "finecoach-built"
            license_short = "MIT"
            license_text = "MIT (FineCoach repository LICENSE)"
            author = "FineCoach"
            library = ""

        entry = {
            "_idx": row["_idx"],
            "key": key,
            "file_short": row["file_short"],
            "line": row["line"],
            "raw_name": raw_name,
            "raw_equipment": row["raw_equipment"],
            "name": name,
            "equipment": equipment,
            "equipment_note": equipment_note,
            "primary": primary,
            "secondary": secondary,
            "unmapped_muscles": unmapped,
            "mode": mode,
            "unilateral": unilateral,
            "confidence": row["confidence"],
            "source": source,
            "source_kind": source_kind,
            "license_short": license_short,
            "license_text": license_text,
            "author": author,
            "library": library,
            "english": row["english"],
            "category": category,
            "input_note": row["input_note"],
            "notes": [],
            "merged": [],
            "pending": [],
        }

        # Match against the current catalog.
        #   1. Chinese name: always "already in library" (prompt rule 1).
        #   2. wger UUID / English name: only when the equipment class is the same
        #      or both are bodyweight classes.  The external table's approximate
        #      mappings (band/TRX/brand machine -> generic library entry) must not
        #      swallow a real equipment variant as a duplicate.
        match = None
        match_basis = ""
        current_name = existing_by_name.get(name)
        if current_name is not None and equipment_compatible(equipment, current_name):
            match, match_basis = current_name, "中文名相同且器械相同"
        if match is None and library.startswith("wger:"):
            data = wger.get(library[5:])
            if data:
                current = existing_by_uuid.get(data["uuid"])
                if current is not None and equipment_compatible(equipment, current):
                    match, match_basis = current, "wger UUID 相同"
        if match is None and row["english"]:
            current = existing_by_english.get(norm_english(row["english"]))
            if current is not None and equipment_compatible(equipment, current):
                match, match_basis = current, "英文名相同"

        # Explicit owner decisions take precedence over equipment matching.
        target = EXPLICIT_EXISTING.get(key)
        if target is not None:
            match, match_basis = existing_by_name[target], "产品负责人 Q4/Q5/Q6/Q7/CX-D12 明确合并"
        elif key in SEMANTIC_EXISTING:
            current = existing_by_name[SEMANTIC_EXISTING[key]]
            if equipment_compatible(equipment, current):
                match, match_basis = current, "Q7 同器械同动作"

        if match is not None:
            entry["existing"] = match
            entry["match_basis"] = match_basis
            entry["notes"].append("已在库（%s）" % match_basis)
            if key in MATCH_EXTRA_NOTES:
                entry["notes"].append(MATCH_EXTRA_NOTES[key])
            entries.append(entry)
            continue

        # Same wger entry as an existing catalog exercise, but the source table's
        # equipment class differs (brand machine / other): keep it as a new
        # equipment variant and surface the shared source instead of swallowing it.
        if library.startswith("wger:"):
            data = wger.get(library[5:])
            if data:
                current = existing_by_uuid.get(data["uuid"])
                if current is not None:
                    entry["source_collision"] = (current["canonicalName"], current["id"], data["uuid"])
                    entry["notes"].append(
                        "近似映射：与现有「%s」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）"
                        % current["canonicalName"]
                    )

        # Notes: equipment mapping, source-table/category mismatch, rename hints.
        if equipment_note:
            entry["notes"].append(equipment_note)
        if primary != FILE_PART[row["file"]]:
            entry["notes"].append("分类表为「%s」，按肌肉推为「%s」" % (FILE_PART[row["file"]], primary))
        if unmapped:
            entry["notes"].append("肌肉词表外：%s" % "、".join(unmapped))
        if name != base_name(raw_name):
            entry["notes"].append("名称规范化")
        if source_kind == "finecoach-built" and library:
            entry["notes"].append("来源核对失败，按 CX-D5 自建条目")
            entry["pending"].append("来源核对失败（%s）" % library)
        if key in ROW_NOTES:
            note = ROW_NOTES[key]
            if note.startswith("待决") or "待决" in note:
                entry["pending"].append(note)
            else:
                entry["notes"].append(note)
        entries.append(entry)

    return {"entries": entries, "low": low_rows, "fedb": fedb, "wger": wger,
            "audit_rows": len(rows)}


def merge_entries(entries: list[dict]) -> list[dict]:
    """Merge candidate rows with the same (equipment, canonical Chinese name)."""
    groups = defaultdict(list)
    for entry in entries:
        if "existing" in entry:
            continue
        if entry["equipment"] == PENDING:
            groups[("__pending__", entry["name"], entry["key"])].append(entry)
        else:
            groups[(entry["equipment"], entry["name"])].append(entry)

    merged = []
    for group in groups.values():
        representative = group[0]
        if len(group) == 1:
            representative["merged"] = []
            merged.append(representative)
            continue
        representative = dict(group[0])
        representative["merged"] = group[1:]
        representative["notes"] = list(group[0]["notes"])
        secondary = set()
        for member in group:
            secondary.update(member["secondary"])
        representative["secondary"] = [p for p in PART_ORDER if p in secondary]
        if len({member["mode"] for member in group}) > 1:
            representative["pending"].append("合并行记录方式不一致：%s" % "、".join(
                "%s=%s" % (member["key"], member["mode"]) for member in group))
        if len({member["unilateral"] for member in group}) > 1:
            representative["unilateral"] = False
            representative["notes"].append("合并单侧与双侧两行，默认双侧（单侧由教练切换）")
        sources = {member["source"] for member in group}
        if len(sources) > 1:
            representative["notes"].append("合并行来源不同：%s" % "、".join(sorted(sources)))
        if len({member["primary"] for member in group}) > 1:
            representative["notes"].append("合并行主部位不同：%s" % "、".join(
                "%s=%s" % (member["key"], member["primary"]) for member in group))
        merged.append(representative)
    return merged


def tag_approximate_mappings(merged: list[dict]) -> None:
    """Different Chinese names that share one library entry: note 近似映射."""
    by_library = defaultdict(list)
    for entry in merged:
        if entry["library"]:
            by_library[entry["library"]].append(entry)
    for library, group in by_library.items():
        names = sorted({entry["name"] for entry in group})
        if len(names) < 2:
            continue
        for entry in group:
            others = [name for name in names if name != entry["name"]]
            if len(others) > 3:
                entry["notes"].append(
                    "近似映射：另 %d 个中文名（%s 等）共用库内条目 %s"
                    % (len(others), "、".join(others[:3]), library)
                )
            else:
                entry["notes"].append(
                    "近似映射：与「%s」共用库内条目 %s" % ("、".join(others), library)
                )


# Rows whose unilateral wording was removed and whose normalised name then hits
# an existing bilateral entry (prompt rule 6 / Q4).
COLLAPSED_UNILATERAL = {"上臂:4", "上臂:54", "胸:77", "背:9", "臀:18", "臀:26"}

# Borderline "already in library" rows where the library entry is more generic
# than the source row; surfaced in appendix B instead of silently swallowed.
MATCH_EXTRA_NOTES = {
    "背:71": "近似映射：来源表映射到通用引体向上条目，弹跳变式不单列",
    "背:72": "近似映射：来源表映射到通用引体向上条目，变式不单列",
    "胸:39": "近似映射：来源表映射到通用蝴蝶机夹胸条目，上斜悍马变式不单列",
}

SEMANTIC_DUPLICATES = [
    ("上臂:28", "仰卧臂屈伸(碎颅者)", "同一动作（Lying Triceps Press / Extensions）"),
    ("上臂:37", "仰卧臂屈伸(碎颅者)", "同一动作（EZ-Bar Skullcrusher / Lying Triceps Extensions）"),
    ("上臂:29", "窄距卧推", "同一动作的肘位变式（Close-Grip Barbell Bench Press）"),
    ("上臂:35", "窄距卧推", "同一动作的肘位变式（Close-Grip Barbell Bench Press）"),
    ("肩:3", "哑铃肩上推举", "同一动作（Dumbbell Shoulder Press / Shoulder Press, Dumbbells）"),
    ("肩:33", "杠铃肩上推举", "同一动作（Standing Military Press / Shoulder Press, Barbell）"),
    ("背:50", "胸撑器械划船", "同一动作（Leverage Iso Row / Leverage Machine Iso Row）"),
    ("背:52", "坐姿绳索划船", "同一动作（Seated Cable Rows）但来源表器材写固定器械"),
    ("背:57", "单臂哑铃划船", "同一动作（One-Arm Dumbbell Row；第 2 步现有条目改名为「哑铃支撑划船」）"),
    ("背:60", "单臂哑铃划船", "同一动作的手撑变式（One-Arm Dumbbell Row；第 2 步现有条目改名为「哑铃支撑划船」）"),
    ("腹:42", "龙门架卷腹", "同一动作（Cable Crunch / Crunches With Cable），来源表器材写固定器械"),
    ("腹:44", "龙门架卷腹", "同一动作（Cable Crunch / Crunches With Cable）"),
    ("臀:10", "山羊挺身", "同一动作（Hyperextensions）"),
    ("腿:35", "哈克深蹲", "同一动作（Hack Squat），器械列与臀:3 互相矛盾（Q6）"),
    ("臀:3", "哈克深蹲", "同一动作（Hack Squat），器械列与腿:35 互相矛盾（Q6）"),
    ("臀:31", "罗马尼亚硬拉", "单腿罗马尼亚硬拉，去「单腿」后与现有近似（Q4）"),
    ("臀:40", "徒手臀桥", "单腿臀桥，去「单腿」后与现有「徒手臀桥」近似（Q4）"),
]



# Product-owner decisions approved 2026-10-18. These are data rules, not output edits.
EXPLICIT_EXISTING = {
    "胸:47": "史密斯窄距卧推", "背:65": "引体向上",  # CX-D12
    "背:68": "反手引体向上", "背:69": "山羊挺身",
    "腹:22": "健腹轮", "腿:84": "北欧腿弯举",
    "臀:31": "罗马尼亚硬拉", "臀:40": "徒手臀桥",  # Q4
    "上臂:55": "绳索弯举",  # Q5
    "腿:35": "哈克深蹲", "臀:3": "哈克深蹲",  # Q6
    "腿:83": "哑铃保加利亚分腿蹲", "腹:10": "俄罗斯转体",  # Q7
    "臀:66": "罗马尼亚硬拉", "臀:28": "罗马尼亚硬拉", "臀:29": "罗马尼亚硬拉",
}
SEMANTIC_EXISTING = {key: name for key, name, _ in SEMANTIC_DUPLICATES}
for _key in ("肩:63", "肩:72", "腿:82"):
    ROW_NOTES[_key] = "Q1 已批准：悬垂带/悬吊带统一悬挂带，次数动作 reps"
for _key in ("腿:35", "臀:3"):
    ROW_NOTES[_key] = "Q6 已批准：并入现有哈克深蹲"
ROW_NOTES["上臂:55"] = "Q5 已批准：并入现有绳索弯举"
for _key in ("臀:31", "臀:40"):
    ROW_NOTES[_key] = "Q4 已批准：单侧变式并入现有条目"
QUESTIONS = [
    "Q1–Q10、A1–A3 及 CX-D12 的 8 行裁决已于 2026-10-18 获产品负责人批准。",
    "Q1 悬挂带统一；Q2 弹力带/悬挂带次数动作 reps；Q3 动作 + 热身；A1 螃蟹行走 duration。",
    "Q4/Q5/Q6 和 Q7 四个明确例外并入指定现有条目；Q7 其余按同器械同动作判重（附录 E/F）。",
    "Q8 保持四项记录方式；Q9 采纳 6 条 low 自建 MIT、不采纳 15 条；Q10 胸表四条改史密斯机；A2 保持 11 行默认否；A3 删除旧上限。",
]
# Original appendix E's 27 pairs and the audit report's 18 rows remain individually traceable.
ORIGINAL_E_COLLISIONS = ["肩:47", "背:44", "腹:10", "腿:52", "腿:67", "腿:69", "腿:83", "臀:20", "臀:65", "臀:67"]
AUDIT_18 = ["胸:47", "肩:47", "肩:64", "肩:63", "背:44", "臀:28", "臀:66", "腿:67", "腿:69", "腿:83", "上臂:69", "上臂:74", "腿:52", "臀:20", "臀:65", "臀:67", "腹:10", "腹:49"]


def semantic_duplicates(entries: list[dict], existing: list[dict]) -> list[dict]:
    by_key = {entry["key"]: entry for entry in entries}
    by_uuid = {entry["id"]: entry for entry in existing}
    by_name = {entry["canonicalName"]: entry for entry in existing}
    verified = json.loads(CACHE.read_text(encoding="utf-8"))
    original = [(key, None, "原附录 E：共用 wger UUID") for key in ORIGINAL_E_COLLISIONS]
    original += [(key, name, reason) for key, name, reason in SEMANTIC_DUPLICATES]
    audit = [(key, None, "核对报告第 4 项：英文名/UUID 命中") for key in AUDIT_18]
    pairs = []
    for appendix, group in (("E", original), ("F", audit)):
        for key, name, reason in group:
            entry = by_key[key]
            current = entry.get("existing") or by_name.get(name)
            if current is None:
                library = entry["library"]
                if library.startswith("wger:"):
                    current = by_uuid.get(verified["wger"]["entries"][library[5:]]["uuid"])
                if current is None:
                    current = next(item for item in existing if norm_english(item["sourceEnglishName"]) == norm_english(entry["english"]))
            is_existing = "existing" in entry
            pairs.append({"appendix": appendix, "candidate": entry["name"], "candidate_key": key,
                "existing": current["canonicalName"], "existing_id": current["id"],
                "reason": reason + "；器械 %s → %s" % (entry["equipment"], existing_equipment(current)),
                "decision": ("已在库：" + entry["match_basis"]) if is_existing else "新增：器械不同，按 Q7 保留"})
    return pairs


def render(data: dict, merged: list[dict], already: list[dict], calibrations: list[dict],
           duplicates: list[dict]) -> str:
    entries = merged
    adopted_low = [low for low in data["low"] if low["recommend"]]
    rejected_low = [low for low in data["low"] if not low["recommend"]]

    def sort_key(entry: dict):
        part_rank = PART_ORDER.index(entry["primary"]) if entry["primary"] in PART_ORDER else len(PART_ORDER)
        equip = entry["equipment"]
        equip_rank = EQUIP_ORDER.index(equip) if equip in EQUIP_ORDER else len(EQUIP_ORDER)
        return (part_rank, equip_rank, entry["_idx"])

    ordered = sorted(entries, key=sort_key)

    part_counts = OrderedDict((part, 0) for part in PART_ORDER)
    equip_counts = OrderedDict((equip, 0) for equip in EQUIP_ORDER)
    equip_counts[PENDING] = 0
    for entry in ordered:
        if entry["primary"] in part_counts:
            part_counts[entry["primary"]] += 1
        equip_counts[entry["equipment"]] = equip_counts.get(entry["equipment"], 0) + 1

    high_medium_added = sum(1 for entry in ordered if entry["confidence"] != "low")
    total = 146 + len(ordered)
    audit_rows = data["audit_rows"]
    merged_away = sum(len(entry["merged"]) for entry in entries)
    already_entries = len({entry["existing"]["id"] for entry in already})

    lines = []
    lines.append("# C′ 动作库扩充已审清单")
    lines.append("")
    lines.append("状态：**已审，2026-10-18 产品负责人批准**。依据 Q1–Q10、A1–A3 及 CX-D12；原 146 条以固定 baseline `96b385f` 为准，新增与合并总数见以下实际生成统计。")
    lines.append("")
    lines.append("生成方式：`.venv/bin/python -I design/catalog-expansion/tools/build_candidates.py`（项目本地 uv venv，保留原要求的 `-I` 隔离；仅标准库）。")
    lines.append("输入：`design/catalog-expansion/source/2026-10-17/`（外部表的冻结副本，"
                 "match-audit.csv SHA-256 `%s`）；来源核对：`tools/verify_sources.py` "
                 "（缓存 + `source/cache/verified-sources.json`，下载日期 2026-10-18）。"
                 % _sha256(AUDIT_CSV))
    lines.append("")
    lines.append("## 批准入库统计")
    lines.append("")
    lines.append("- 输入 `match-audit.csv`：%d 行（high 332 / medium 216 / low 21）。" % audit_rows)
    lines.append("- **新增条数**：high/medium 合并去重后 **%d** 条；low 建议采纳 **%d** 条（附录 A，"
                 "已计入主名单并标 low）。主名单合计 **%d** 条。" %
                 (high_medium_added, len(adopted_low), len(ordered)))
    lines.append("- **合并总条数**：146 + %d = **%d** 条（其中不含 low 的条数 %d）。" %
                 (len(ordered), total, 146 + high_medium_added))
    lines.append("- **已在库**：%d 行，对应现有 %d 条条目（附录 B）；**合并掉** %d 行（附录 D）。" %
                 (len(already), already_entries, merged_away))
    lines.append("- 校准差异：%d 处（附录 C）。逐组复核：%d 行（原附录 E 27 组 + 核对报告 18 行，附录 E/F）。" %
                 (len(calibrations), len(duplicates)))
    lines.append("")
    lines.append("### 主部位条数（主名单，含 low 建议采纳）")
    lines.append("")
    lines.append("| 部位 | 条数 |")
    lines.append("|---|---|")
    for part, count in part_counts.items():
        lines.append("| %s | %d |" % (part, count))
    lines.append("")
    lines.append("### 器械条数（主名单，含 low 建议采纳）")
    lines.append("")
    lines.append("| 器械 | 条数 |")
    lines.append("|---|---|")
    for equip, count in equip_counts.items():
        if count:
            lines.append("| %s | %d |" % (equip, count))
    lines.append("")
    lines.append("## 已批准决定")
    lines.append("")
    for question in QUESTIONS:
        lines.append("- %s" % question)
    lines.append("")
    lines.append("## 完整名单")
    lines.append("")
    lines.append("排序：主部位（%s）→ 器械（%s）。" % ("、".join(PART_ORDER), "、".join(EQUIP_ORDER)))
    lines.append("")
    lines.append("「已在库」判定：Q7 器械相同且动作相同才合并，器械不同新增；不再把徒手、单杠、悬挂带、其他当同一器械。Q4/Q5/Q6 和 Q7 四行明确决定优先。现有中文名/id 一律来自 146 条 baseline，JSON 写入后也不会改变清单。")
    lines.append("")
    lines.append("| # | 主部位 | 次要部位 | 器械 | 中文名 | 原名 | English | 记录方式 | 单侧默认 | 来源 | 许可 | 置信度 | 备注 / 待决 |")
    lines.append("|---:|---|---|---|---|---|---|---|---|---|---|---|---|")
    for number, entry in enumerate(ordered, start=1):
        note_parts = list(entry["notes"])
        if entry["merged"]:
            note_parts.append("合并 %d 行：%s" % (
                len(entry["merged"]) + 1,
                "、".join("%s:%s（%s）" % (member["file_short"], member["line"], member["raw_name"])
                         for member in [entry] + entry["merged"]),
            ))
        if entry["confidence"] == "low" and not any(
            "建议采纳（附录 A）" in part for part in note_parts
        ):
            note_parts.append("low 行，建议采纳（附录 A）")
        note_parts.extend(entry["pending"])
        note = "；".join(dict.fromkeys(note_parts))
        lines.append("| %d | %s | %s | %s | %s | %s | %s | `%s` | %s | %s | %s | %s | %s |" % (
            number,
            entry["primary"],
            "、".join(entry["secondary"]),
            entry["equipment"],
            entry["name"],
            entry["raw_name"] if entry["raw_name"] != entry["name"] else "",
            entry["english"] or "",
            entry["mode"],
            "是" if entry["unilateral"] else "",
            entry["source"],
            _license_cell(entry),
            entry["confidence"],
            note,
        ))
    lines.append("")
    lines.append("说明：中文名由来源表动作名按 CX-D3 规范化；原名只在改名时显示。"
                 "空白的「单侧默认」表示默认双侧；「是」表示默认单侧。"
                 "拉伸/热身类里一次只练一侧的（如 坐姿梨状肌拉伸、单腿拉伸）默认单侧，"
                 "两侧同时做的默认双侧。"
                 "来源 `finecoach-built` 的条目按 CX-D5 为 FineCoach 自建，作者 `FineCoach`，许可 `MIT`。")
    lines.append("")

    lines.append("## CX-D12：8 行批准裁决与原始证据")
    lines.append("")
    lines.append("| 文件:行 | 批准结果 | 证据 |")
    lines.append("|---|---|---|")
    for key, decision, evidence in [
        ("胸:47", "并入史密斯窄距卧推", "fedb:Smith_Machine_Close-Grip_Bench_Press，同器械同英文名"),
        ("背:65", "并入引体向上，现有器械改为单杠，id/名不动", "fedb:Pullups；CSV 单杠，缓存 body only"),
        ("背:68", "并入反手引体向上，现有器械改为单杠，id/名不动", "fedb:Chin-Up；CSV 单杠，缓存 body only"),
        ("背:69", "并入山羊挺身", "fedb:Hyperextensions_Back_Extensions；器械差异没有证据"),
        ("腹:9", "新增徒手俄罗斯转体，现有俄罗斯转体保持哑铃", "fedb:Russian_Twist；CSV 无→徒手"),
        ("腹:22", "并入健腹轮", "fedb:Ab_Roller；器械差异没有证据"),
        ("腿:23", "新增哑铃罗马尼亚硬拉，现有罗马尼亚硬拉保持杠铃", "wger:1652；Dumbbell Romanian Deadlift"),
        ("腿:84", "并入北欧腿弯举", "wger:910；UUID 与旧目录相同"),
    ]:
        lines.append("| %s | %s | %s |" % (key, decision, evidence))
    lines.append("")
    lines.append("证据来自冻结 CSV、verified-sources.json 与固定 baseline `96b385f`。CX-D12 通则：内置条目之间不允许中文重名；生成器遇到重名即失败，不自动加器械前缀。")
    lines.append("")

    # Appendix A: low rows.
    lines.append("## 附录 A：low 行（21 行）采纳建议")
    lines.append("")
    lines.append("| 结论 | 文件:行 | 原器械 | 原动作名 | 建议规范名 | 器械 | 记录方式 | 单侧默认 | 主部位 | 次要部位 | 理由 |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for low in data["low"]:
        lines.append("| %s | %s:%s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            "建议采纳" if low["recommend"] else "不采纳",
            low["file_short"],
            low["line"],
            low["raw_equipment"],
            low["raw_name"],
            low["name"] or "—",
            low["equipment"] or "—",
            ("`%s`" % low["mode"]) if low["mode"] else "—",
            ("是" if low["unilateral"] else "否") if low["recommend"] else "—",
            low["primary"] or "—",
            "、".join(low["secondary"]) or "—",
            low["reason"],
        ))
    lines.append("")
    lines.append("采纳的 6 条已由产品负责人批准，按 CX-D5 为 FineCoach 自建（作者 `FineCoach`、许可 `MIT`）；`sourceEnglishName` 使用 `FineCoach original: <canonicalName>` 自建标记，不假造外部英文来源。")
    lines.append("")
    lines.append("来源表数据质量问题（不改输入，仅记录）：`上臂:80` 的「铃铃二头弯举」是错字；"
                 "`背:18` 的「绳索站旋转划」名称残缺；`腹:50/51/52` 三条弹力带转体名称互相矛盾、肌肉列不一致。")
    lines.append("")

    # Appendix B: already in library.
    lines.append("## 附录 B：已在库（不新增，以现有条目为准）")
    lines.append("")
    lines.append("| 文件:行 | 原器械 | 原名 | 规范名 | 现有中文名 | 现有 id | 匹配依据 | 备注 |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for entry in sorted(already, key=lambda item: item["_idx"]):
        current = entry["existing"]
        basis = ""
        for note in entry["notes"]:
            if note.startswith("已在库（"):
                basis = note
                break
        extra = [note for note in entry["notes"] if not note.startswith("已在库（")]
        merged_note = ""
        if entry["key"] in COLLAPSED_UNILATERAL:
            merged_note = "去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4）"
        lines.append("| %s:%s | %s | %s | %s | %s | `%s` | %s | %s |" % (
            entry["file_short"], entry["line"], entry["raw_equipment"], entry["raw_name"],
            entry["name"], current["canonicalName"], current["id"],
            basis.replace("已在库（", "").rstrip("）"),
            "；".join(extra + ([merged_note] if merged_note else [])),
        ))
    lines.append("")

    # Appendix C: calibration differences.
    lines.append("## 附录 C：校准差异（已在库行：按规则推出的部位/器械与现有条目不一致）")
    lines.append("")
    if calibrations:
        lines.append("| 文件:行 | 现有中文名 | 项目 | 本表推出 | 现有条目 | 处理 |")
        lines.append("|---|---|---|---|---|---|")
        for item in calibrations:
            lines.append("| %s:%s | %s | %s | %s | %s | 只记录，不改现有条目 |" % (
                item["file_short"], item["line"], item["existing_name"], item["field"],
                item["derived"], item["current"],
            ))
    else:
        lines.append("无。")
    lines.append("")

    # Appendix D: merge records.
    lines.append("## 附录 D：合并记录（规范化后器械与中文名都相同的行）")
    lines.append("")
    merged_entries = [entry for entry in ordered if entry["merged"]]
    if merged_entries:
        lines.append("| 合并后中文名 | 器械 | 成员（文件:行，原名） | 备注 |")
        lines.append("|---|---|---|---|")
        for entry in merged_entries:
            members = "；".join("%s:%s（%s）" % (member["file_short"], member["line"], member["raw_name"])
                               for member in [entry] + entry["merged"])
            lines.append("| %s | %s | %s | %s |" % (
                entry["name"], entry["equipment"], members,
                "；".join(note for note in entry["notes"] if "合并" in note or "来源" in note),
            ))
    else:
        lines.append("无。")
    lines.append("")

    for appendix, title in (("E", "原附录 E 27 组逐组判定"), ("F", "机械核对报告第 4 项 18 行逐行判定")):
        lines.append("## 附录 %s：%s（Q7 已批准规则）" % (appendix, title))
        lines.append("")
        lines.append("| 候选 | 候选来源 | 对照 | 依据 | 最终判定 |")
        lines.append("|---|---|---|---|---|")
        for item in duplicates:
            if item["appendix"] != appendix:
                continue
            lines.append("| %s | %s | 现有「%s」（`%s`） | %s | %s |" % (
                item["candidate"], item["candidate_key"], item["existing"], item["existing_id"], item["reason"], item["decision"]))
        lines.append("")

    return "\n".join(lines) + "\n"


def _license_cell(entry: dict) -> str:
    if entry["license_short"] in ("MIT", "Unlicense", "CC0"):
        return entry["license_short"]
    author = entry["author"] if entry["author"] and entry["author"] != "wger.de" else "wger.de"
    return "%s (© %s)" % (entry["license_short"], author)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_builtin_names(existing: list[dict], merged: list[dict]) -> None:
    """CX-D12: fail on duplicate Chinese names; never invent equipment prefixes."""
    names = defaultdict(list)
    renames = {"单臂哑铃划船": "哑铃支撑划船", "哑铃单手提走": "哑铃提箱走"}
    for current in existing:
        name = renames.get(current["canonicalName"], current["canonicalName"])
        names[name].append("baseline:" + current["id"])
    for entry in merged:
        names[entry["name"]].append(entry["key"])
        if entry["pending"]:
            raise ValueError("unresolved candidate: %s %s" % (entry["key"], entry["pending"]))
    collisions = {name: keys for name, keys in names.items() if len(keys) > 1}
    if collisions:
        raise ValueError("CX-D12 duplicate built-in Chinese names: %s" % collisions)


def main() -> None:
    rows = load_rows()
    existing, _records = load_existing()
    existing_by_english = {}
    existing_by_name = {}
    existing_by_uuid = {}
    for current in existing:
        existing_by_english.setdefault(norm_english(current["sourceEnglishName"]), current)
        existing_by_name.setdefault(current["canonicalName"], current)
        existing_by_uuid.setdefault(current["id"], current)


    built = build_entries(rows, existing_by_english, existing_by_name, existing_by_uuid)
    entries = built["entries"]

    already = [entry for entry in entries if "existing" in entry]
    candidates = [entry for entry in entries if "existing" not in entry]

    merged = merge_entries(candidates)
    tag_approximate_mappings(merged)
    validate_builtin_names(existing, merged)

    calibrations = []
    for entry in already:
        current = entry["existing"]
        current_equipment = "绳索" if current["equipmentClass"] == "龙门架" else current["equipmentClass"]
        if entry["equipment"] != current_equipment:
            calibrations.append({
                "file_short": entry["file_short"], "line": entry["line"],
                "existing_name": current["canonicalName"], "field": "器械",
                "derived": entry["equipment"], "current": current["equipmentClass"],
            })
        if entry["primary"] != current["primaryMuscleGroup"]:
            calibrations.append({
                "file_short": entry["file_short"], "line": entry["line"],
                "existing_name": current["canonicalName"], "field": "主部位",
                "derived": entry["primary"], "current": current["primaryMuscleGroup"],
            })
        if set(entry["secondary"]) != set(current["secondaryMuscleGroups"]):
            calibrations.append({
                "file_short": entry["file_short"], "line": entry["line"],
                "existing_name": current["canonicalName"], "field": "次要部位",
                "derived": "、".join(entry["secondary"]) or "（空）",
                "current": "、".join(current["secondaryMuscleGroups"]) or "（空）",
            })

    duplicates = semantic_duplicates(entries, existing)
    text = render(built, merged, already, calibrations, duplicates)
    OUTPUT.write_text(text, encoding="utf-8")

    # Console summary (also the determinism check surface).
    print("rows=%d entries=%d merged_away=%d already=%d(entries=%d) adopted_low=%d rejected_low=%d" % (
        len(rows), len(merged), sum(len(entry["merged"]) for entry in merged), len(already),
        len({entry["existing"]["id"] for entry in already}),
        sum(1 for low in built["low"] if low["recommend"]),
        sum(1 for low in built["low"] if not low["recommend"]),
    ))
    print("calibrations=%d near_duplicates=%d questions=%d" % (
        len(calibrations), len(duplicates), 0))
    print("output=%s sha256=%s" % (OUTPUT.relative_to(ROOT), _sha256(OUTPUT)))


if __name__ == "__main__":
    main()
