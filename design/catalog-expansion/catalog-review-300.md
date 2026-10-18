# C′ 动作库扩充候选（待审）

状态：**待审**（第 1 步：候选清单。未改 `provenance.json`、schema、Swift 代码或 001 spec 正文。）

生成方式：`python3 -I design/catalog-expansion/tools/build_candidates.py`。
输入：`design/catalog-expansion/source/2026-10-17/`（外部表的冻结副本，match-audit.csv SHA-256 `c342002a998b1d82a12e78d19856db9b0f63239d22b54536b4b098c7908c3ea5`）；来源核对：`tools/verify_sources.py` （缓存 + `source/cache/verified-sources.json`，下载日期 2026-10-18）。

## 统计

- 输入 `match-audit.csv`：569 行（high 332 / medium 216 / low 21）。
- **新增条数**：high/medium 合并去重后 **405** 条；low 建议采纳 **6** 条（附录 A，已计入主名单并标 low）。主名单合计 **411** 条。
- **合并后总条数**：146 + 411 = **557** 条（若 low 建议不被采纳，则 551 条）。
- **已在库**：132 行，对应现有 92 条条目（附录 B）；**合并掉** 11 行（附录 D）。
- 校准差异：66 处（附录 C）。疑似重复待确认：27 组（附录 E）。

### 主部位条数（主名单，含 low 建议采纳）

| 部位 | 条数 |
|---|---|
| 胸 | 58 |
| 肩 | 49 |
| 背 | 73 |
| 大腿 | 70 |
| 小腿 | 11 |
| 臂 | 64 |
| 臀 | 44 |
| 核心 | 42 |

### 器械条数（主名单，含 low 建议采纳）

| 器械 | 条数 |
|---|---|
| 杠铃 | 56 |
| 哑铃 | 66 |
| 固定器械 | 43 |
| 史密斯机 | 13 |
| 绳索 | 40 |
| 哈克机 | 1 |
| 壶铃 | 3 |
| 徒手 | 97 |
| 悍马机 | 25 |
| 弹力带 | 53 |
| 悬挂带 | 4 |
| 单杠 | 5 |
| 其他 | 2 |
| 待决 | 3 |

## 待负责人决定的问题

- Q1 器械待决 3 行：「悬垂带 - 面拉」「悬垂带 - 后束飞鸟」「悬吊带深蹲」的「悬垂带/悬吊带」是不是「悬挂带」笔误？若是，3 行器械改悬挂带；面拉与后束飞鸟的 recordMode 相应改为 reps（悬吊带深蹲已是 reps）。
- Q2 弹力带/悬挂带动作的 recordMode：本表把弹力带阻力视为负重、记 weightReps（重量栏填阻力值），悬挂带（TRX）是自重、记 reps；是否认可？
- Q3 热身类命名：本表统一为「动作 + 热身」并去掉「灵活性」「小幅」等描述词（如 肩胛骨后缩热身、膝关节绕环热身）；是否确认这一约定？
- Q4 去掉「单腿/单手/单臂」后与现有条目重名，按提示词规则第 6 条当作「已在库」，单侧变式因此不入库：单手俯卧撑→俯卧撑、杠铃单腿硬拉→杠铃硬拉、单腿哑铃硬拉→哑铃硬拉、哑铃轮换弯举→哑铃弯举；另有单腿臀桥、单腿罗马尼亚硬拉改成近似名后仍新增。是否接受，还是给单侧变式保留可区分名字（沿用 CX-D4 的「支撑/分腿」写法）？
- Q5 「绳索训练器」（上臂:55）不是动作名，映射到 Standing Biceps Cable Curl；是否按「绳索弯举」合并、不单独收录？
- Q6 哈克机深蹲：腿:35（固定器械）与臀:3（哈克机）是同一动作、器械列又互相矛盾，且都与现有「哈克深蹲」是同一动作；建议两行都按现有「哈克深蹲」处理、不再新增，是否确认？
- Q7 疑似重复：附录 E 列出机械规则没有判重、但实际是同一动作的候选↔现有配对（如 仰卧杠铃臂屈伸 vs 仰卧臂屈伸(碎颅者)、窄距卧推(靠近/散开) vs 窄距卧推、杠铃碎颅者 vs 仰卧臂屈伸(碎颅者)、哑铃推举 vs 哑铃肩上推举、哑铃划船/哑铃划船(手撑) vs 单臂哑铃划船），以及共用同一 wger 条目、但来源表器械/变式不同而按新条目保留的 10 行（如 悍马机侧平举 vs 器械侧平举）；请逐条确认是否按「已在库」处理。
- Q8 recordMode 拿不准的 4 行：「固定熊爬」按静止支撑记 duration、「平板肘撑转换」按交替动作记 reps、「仰卧交叉腿」按拉伸记 duration、「泡沫轴臀部放松」按泡沫轴放松记 duration；是否认可这 4 个判断？
- Q9 附录 A 的 21 条 low 行：本表建议采纳 6 条、不采纳 15 条；请逐条确认（采纳的按 CX-D5 记为 FineCoach 自建、MIT 许可）。
- Q10 来源表器材列不一致：胸表 44-47 行（史密斯机卧推、上斜/下斜史密斯机卧推、史密斯机 V-bar）写「固定器械」，其余表同类动作用「史密斯机」，且现有目录把同类动作归「史密斯机」；建议统一为「史密斯机」，是否确认？

## 完整名单

排序：主部位（胸、肩、背、大腿、小腿、臂、臀、核心）→ 器械（杠铃、哑铃、固定器械、史密斯机、绳索、哈克机、壶铃、徒手、悍马机、弹力带、悬挂带、单杠、其他）。

「已在库」判定：中文名相同，或英文名相同，或 wger UUID 相同。英文名 / wger UUID 命中时还要求器械类别一致（或同属自重类：徒手、单杠、悬挂带、其他），避免把来源表的近似映射（弹力带、品牌器械映射到通用库条目）误判成已在库。改名后与现有条目重名的行按规则当作已在库，列在附录 B。

| # | 主部位 | 次要部位 | 器械 | 中文名 | 原名 | English | 记录方式 | 单侧默认 | 来源 | 许可 | 置信度 | 备注 / 待决 |
|---:|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 胸 | 肩、臂 | 杠铃 | 宽距杠铃卧推 |  | Wide-Grip Barbell Bench Press | `weightReps` |  | free-exercise-db:Wide-Grip_Barbell_Bench_Press | Unlicense | high |  |
| 2 | 胸 | 臂 | 杠铃 | 抬腿杠铃卧推 |  | Larsen Press | `weightReps` |  | wger.de:87f30f6d-dc8a-4b26-8c4f-640b66ecacf0 | CC-BY-SA 4 (© Expenses7000) | medium |  |
| 3 | 胸 | 臂 | 杠铃 | 暂停卧推 |  | Pause Bench | `weightReps` |  | wger.de:6441ff9e-037e-48d9-8800-67b430dc8e37 | CC0 | high |  |
| 4 | 胸 | 肩、臂 | 杠铃 | 杠铃片夹胸 |  | Svend Press | `weightReps` |  | free-exercise-db:Svend_Press | Unlicense | high |  |
| 5 | 胸 | 肩、臂 | 杠铃 | 杠铃地板卧推 |  | Floor Press | `weightReps` |  | free-exercise-db:Floor_Press | Unlicense | high |  |
| 6 | 胸 | 肩、背 | 哑铃 | 平板哑铃提拉 |  | Bent-Arm Dumbbell Pullover | `weightReps` |  | free-exercise-db:Bent-Arm_Dumbbell_Pullover | Unlicense | high | 分类表为「肩」，按肌肉推为「胸」；近似映射：与「仰卧屈臂上拉」共用库内条目 fedb:Bent-Arm_Dumbbell_Pullover |
| 7 | 胸 | 肩、臂 | 哑铃 | 窄距哑铃卧推 |  | Close-Grip Dumbbell Press | `weightReps` |  | free-exercise-db:Close-Grip_Dumbbell_Press | Unlicense | high |  |
| 8 | 胸 | 肩 | 哑铃 | 仰卧旋转展臂 | 仰卧旋转展臂上 | Around The Worlds | `weightReps` |  | free-exercise-db:Around_The_Worlds | Unlicense | medium | 名称规范化 |
| 9 | 胸 | 肩、臂 | 哑铃 | 反手哑铃卧推 |  | DB Underhand bench press | `weightReps` |  | wger.de:7b40813b-80a3-42cc-8938-0c5199ef7620 | CC-BY-SA 4 (© JohnPreston) | high |  |
| 10 | 胸 | 肩、臂 | 哑铃 | 平板哑铃锤式卧推 |  | Dumbbell Bench Press with Neutral Grip | `weightReps` |  | free-exercise-db:Dumbbell_Bench_Press_with_Neutral_Grip | Unlicense | high | 近似映射：与「哑铃卧推(锤)」共用库内条目 fedb:Dumbbell_Bench_Press_with_Neutral_Grip |
| 11 | 胸 | 肩、臂 | 哑铃 | 下斜哑铃卧推 |  | Decline Dumbbell Bench Press | `weightReps` |  | free-exercise-db:Decline_Dumbbell_Bench_Press | Unlicense | high |  |
| 12 | 胸 | 肩、背、臂 | 哑铃 | 仰卧屈臂上拉 |  | Bent-Arm Dumbbell Pullover | `weightReps` |  | free-exercise-db:Bent-Arm_Dumbbell_Pullover | Unlicense | high | 近似映射：与「平板哑铃提拉」共用库内条目 fedb:Bent-Arm_Dumbbell_Pullover |
| 13 | 胸 | 肩、臂 | 哑铃 | 反手上斜哑铃卧推 |  | Incline Dumbbell Press | `weightReps` |  | free-exercise-db:Incline_Dumbbell_Press | Unlicense | medium |  |
| 14 | 胸 | 肩、臂 | 哑铃 | 哑铃卧推(锤) | 哑铃卧推（锤） | Dumbbell Bench Press with Neutral Grip | `weightReps` |  | free-exercise-db:Dumbbell_Bench_Press_with_Neutral_Grip | Unlicense | high | 近似映射：与「平板哑铃锤式卧推」共用库内条目 fedb:Dumbbell_Bench_Press_with_Neutral_Grip |
| 15 | 胸 | 肩 | 哑铃 | 哑铃下斜飞鸟 |  | Decline Dumbbell Flyes | `weightReps` |  | free-exercise-db:Decline_Dumbbell_Flyes | Unlicense | high |  |
| 16 | 胸 | 肩、臂 | 固定器械 | 器械推胸V4 | 器械推胸 - V4 | Machine Bench Press | `weightReps` |  | free-exercise-db:Machine_Bench_Press | Unlicense | medium | 近似映射：与「对握式器械推胸、直立器械推胸」共用库内条目 fedb:Machine_Bench_Press |
| 17 | 胸 | 肩、臂 | 固定器械 | 对握式器械推胸 |  | Machine Bench Press | `weightReps` |  | free-exercise-db:Machine_Bench_Press | Unlicense | medium | 近似映射：与「器械推胸V4、直立器械推胸」共用库内条目 fedb:Machine_Bench_Press |
| 18 | 胸 | 肩、臂 | 固定器械 | 悍马机推胸 |  | Leverage Chest Press | `weightReps` |  | free-exercise-db:Leverage_Chest_Press | Unlicense | medium | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；近似映射：与「悍马机推胸V2、悍马机推胸V3」共用库内条目 fedb:Leverage_Chest_Press；合并 2 行：胸:36（悍马机推胸）、胸:40（单边悍马机推胸） |
| 19 | 胸 | 肩、臂 | 固定器械 | 上斜悍马机推胸 |  | Leverage Incline Chest Press | `weightReps` |  | free-exercise-db:Leverage_Incline_Chest_Press | Unlicense | medium |  |
| 20 | 胸 | 肩、臂 | 固定器械 | 下斜悍马机推胸 |  | Leverage Decline Chest Press | `weightReps` |  | free-exercise-db:Leverage_Decline_Chest_Press | Unlicense | medium |  |
| 21 | 胸 | 肩、臂 | 固定器械 | 悍马机推胸V2 | 悍马机推胸 - V2 | Leverage Chest Press | `weightReps` |  | free-exercise-db:Leverage_Chest_Press | Unlicense | medium | 近似映射：与「悍马机推胸、悍马机推胸V3」共用库内条目 fedb:Leverage_Chest_Press |
| 22 | 胸 | 肩、臂 | 固定器械 | 悍马机推胸V3 | 悍马机推胸 - V3 | Leverage Chest Press | `weightReps` |  | free-exercise-db:Leverage_Chest_Press | Unlicense | medium | 近似映射：与「悍马机推胸、悍马机推胸V2」共用库内条目 fedb:Leverage_Chest_Press |
| 23 | 胸 | 肩、臂 | 固定器械 | 直立器械推胸 |  | Machine Bench Press | `weightReps` |  | free-exercise-db:Machine_Bench_Press | Unlicense | medium | 近似映射：与「器械推胸V4、对握式器械推胸」共用库内条目 fedb:Machine_Bench_Press |
| 24 | 胸 | 肩、臂 | 固定器械 | 史密斯机卧推 |  | Smith Machine Bench Press | `weightReps` |  | free-exercise-db:Smith_Machine_Bench_Press | Unlicense | high | Q10：来源器材写固定器械，实际为史密斯机 |
| 25 | 胸 | 肩、臂 | 固定器械 | 上斜史密斯机卧推 |  | Smith Machine Incline Bench Press | `weightReps` |  | free-exercise-db:Smith_Machine_Incline_Bench_Press | Unlicense | high | Q10：来源器材写固定器械，实际为史密斯机 |
| 26 | 胸 | 肩、臂 | 固定器械 | 下斜史密斯机卧推 |  | Smith Machine Decline Press | `weightReps` |  | free-exercise-db:Smith_Machine_Decline_Press | Unlicense | high | Q10：来源器材写固定器械，实际为史密斯机 |
| 27 | 胸 | 肩、臂 | 固定器械 | 史密斯机V把 | 史密斯机 V-bar | Smith Machine Close-Grip Bench Press | `weightReps` |  | free-exercise-db:Smith_Machine_Close-Grip_Bench_Press | Unlicense | medium | Q10：来源器材写固定器械，实际为史密斯机 |
| 28 | 胸 | 肩 | 绳索 | 平板绳索夹胸 |  | Flat Bench Cable Flyes | `weightReps` |  | free-exercise-db:Flat_Bench_Cable_Flyes | Unlicense | high |  |
| 29 | 胸 | 肩 | 绳索 | 上斜绳索夹胸 |  | Incline Cable Flye | `weightReps` |  | free-exercise-db:Incline_Cable_Flye | Unlicense | high |  |
| 30 | 胸 | 肩 | 绳索 | 下斜绳索夹胸 |  | Low Cable Crossover | `weightReps` |  | free-exercise-db:Low_Cable_Crossover | Unlicense | high |  |
| 31 | 胸 | 肩 | 绳索 | 绳索站姿飞鸟 | 绳索站姿单臂飞鸟 | Single-Arm Cable Crossover | `weightReps` | 是 | free-exercise-db:Single-Arm_Cable_Crossover | Unlicense | high |  |
| 32 | 胸 | 背 | 徒手 | 扩胸开合拉伸 | 拉伸 - 扩胸开合 | Dynamic Chest Stretch | `duration` |  | free-exercise-db:Dynamic_Chest_Stretch | Unlicense | high | 分类表为「肩」，按肌肉推为「胸」 |
| 33 | 胸 | 肩、臂 | 徒手 | 上斜俯卧撑 |  | Incline Push-Up | `reps` |  | free-exercise-db:Incline_Push-Up | Unlicense | high |  |
| 34 | 胸 | 肩、臂 | 徒手 | 下斜俯卧撑 |  | Decline Push-Up | `reps` |  | free-exercise-db:Decline_Push-Up | Unlicense | high | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；合并行来源不同：free-exercise-db:Decline_Push-Up、free-exercise-db:Single-Arm_Push-Up；合并 2 行：胸:65（下斜俯卧撑）、胸:75（单手下斜俯卧撑） |
| 35 | 胸 | 肩、臂 | 徒手 | 俯卧撑(负重) | 俯卧撑（负重） | Weighted push-ups | `weightReps` |  | wger.de:37abbe32-2fab-4818-8355-fffcff2dc3e3 | CC-BY-SA 4 (© nishant0712) | high | 近似映射：与「反手俯卧撑(负重)」共用库内条目 wger:1902 |
| 36 | 胸 | 肩、臂 | 徒手 | 反手俯卧撑 |  | Pushups | `reps` |  | free-exercise-db:Pushups | Unlicense | medium | 近似映射：与「俯卧撑(支撑)、弹力带阻力俯卧撑」共用库内条目 fedb:Pushups |
| 37 | 胸 | 肩、臂 | 徒手 | 反手俯卧撑(负重) | 反手俯卧撑（负重） | Weighted push-ups | `weightReps` |  | wger.de:37abbe32-2fab-4818-8355-fffcff2dc3e3 | CC-BY-SA 4 (© nishant0712) | medium | 近似映射：与「俯卧撑(负重)」共用库内条目 wger:1902 |
| 38 | 胸 | 肩、臂 | 徒手 | 臂屈伸式俯卧撑 |  | Push-Ups - Close Triceps Position | `reps` |  | free-exercise-db:Push-Ups_-_Close_Triceps_Position | Unlicense | high | 近似映射：与「窄距俯卧撑」共用库内条目 fedb:Push-Ups_-_Close_Triceps_Position |
| 39 | 胸 | 肩、臂 | 徒手 | 臀屈伸式俯卧撑 |  | Hindu Pushups | `reps` |  | wger.de:476c1d96-6590-4f86-98f0-3f12808fab53 | CC-BY-SA 4 (© Imobard) | medium |  |
| 40 | 胸 | 肩、臂 | 徒手 | 地板飞鸟 |  | Bodyweight Flyes | `reps` |  | free-exercise-db:Bodyweight_Flyes | Unlicense | high | 近似映射：与「地板飞鸟(负重)、跪姿地板飞鸟」共用库内条目 fedb:Bodyweight_Flyes |
| 41 | 胸 | 肩、臂 | 徒手 | 地板飞鸟(负重) | 地板飞鸟（负重） | Bodyweight Flyes | `weightReps` |  | free-exercise-db:Bodyweight_Flyes | Unlicense | medium | 近似映射：与「地板飞鸟、跪姿地板飞鸟」共用库内条目 fedb:Bodyweight_Flyes |
| 42 | 胸 | 肩、臂 | 徒手 | 俯卧撑(把柄) | 俯卧撑（把柄） | Push-Ups ｜ Parallettes | `reps` |  | wger.de:bd141adb-b9ad-4038-b11f-1db8665f72bc | CC-BY-SA 4 (© anon1337) | high |  |
| 43 | 胸 | 肩、臂 | 徒手 | 俯卧撑(支撑) | 俯卧撑（支撑） | Pushups | `reps` |  | free-exercise-db:Pushups | Unlicense | medium | 近似映射：与「反手俯卧撑、弹力带阻力俯卧撑」共用库内条目 fedb:Pushups |
| 44 | 胸 | 肩、臂 | 徒手 | 跪姿俯卧撑 |  | Knee Push-Ups | `reps` |  | wger.de:2b61df61-f71e-4b8f-9f95-6a565238a8ae | CC-BY-SA 4 (© PaukOne) | high |  |
| 45 | 胸 | 肩、臂 | 徒手 | 跪姿地板飞鸟 |  | Bodyweight Flyes | `reps` |  | free-exercise-db:Bodyweight_Flyes | Unlicense | medium | 近似映射：与「地板飞鸟、地板飞鸟(负重)」共用库内条目 fedb:Bodyweight_Flyes |
| 46 | 胸 | 肩、背 | 徒手 | 扶墙拉伸 | 拉伸 - 单手扶墙 | One Arm Against Wall | `duration` | 是 | free-exercise-db:One_Arm_Against_Wall | Unlicense | medium | 合并 2 行：胸:80（拉伸 - 单手扶墙）、腿:93（拉伸 - 单手扶墙） |
| 47 | 胸 | 肩 | 徒手 | 持杆扩胸拉伸 | 拉伸 - 杆扩胸 | Behind Head Chest Stretch | `duration` |  | free-exercise-db:Behind_Head_Chest_Stretch | Unlicense | medium | 名称规范化 |
| 48 | 胸 | 肩 | 徒手 | 辅助胸廓拉伸 | 拉伸 - 辅助胸腔 | Chest And Front Of Shoulder Stretch | `duration` |  | free-exercise-db:Chest_And_Front_Of_Shoulder_Stretch | Unlicense | medium | 名称规范化 |
| 49 | 胸 | 肩、臂、核心 | 徒手 | 宽距俯卧撑 |  | Push-Up Wide | `reps` |  | free-exercise-db:Push-Up_Wide | Unlicense | high |  |
| 50 | 胸 | 肩、臂、核心 | 徒手 | 鼓掌俯卧撑 |  | Clap Push-UP | `reps` |  | wger.de:fdeb0973-121f-494d-8b94-54f1d7ba003f | CC-BY-SA 4 (© Settebello) | high |  |
| 51 | 胸 | 肩、臂 | 弹力带 | 弹力带高位飞鸟 | 弹力带 - 高位飞鸟 | Cross Over - With Bands | `weightReps` |  | free-exercise-db:Cross_Over_-_With_Bands | Unlicense | medium | 近似映射：与「弹力带低位飞鸟、弹力带十字飞鸟」共用库内条目 fedb:Cross_Over_-_With_Bands |
| 52 | 胸 | 肩、臂 | 弹力带 | 弹力带低位飞鸟 | 弹力带 - 低位飞鸟 | Cross Over - With Bands | `weightReps` |  | free-exercise-db:Cross_Over_-_With_Bands | Unlicense | medium | 近似映射：与「弹力带十字飞鸟、弹力带高位飞鸟」共用库内条目 fedb:Cross_Over_-_With_Bands |
| 53 | 胸 | 肩、臂 | 弹力带 | 弹力带十字飞鸟 | 弹力带 - 十字飞鸟 | Cross Over - With Bands | `weightReps` |  | free-exercise-db:Cross_Over_-_With_Bands | Unlicense | high | 近似映射：与「弹力带低位飞鸟、弹力带高位飞鸟」共用库内条目 fedb:Cross_Over_-_With_Bands |
| 54 | 胸 | 肩、臂 | 弹力带 | 弹力带阻力俯卧撑 | 弹力带 - 阻力俯卧撑 | Pushups | `weightReps` |  | free-exercise-db:Pushups | Unlicense | medium | 近似映射：与「俯卧撑(支撑)、反手俯卧撑」共用库内条目 fedb:Pushups |
| 55 | 胸 | 肩、臂 | 弹力带 | 弹力带前推 | 弹力带 - 前推 | Bench Press - With Bands | `weightReps` |  | free-exercise-db:Bench_Press_-_With_Bands | Unlicense | medium | 近似映射：与「弹力带上推、弹力带卧推、弹力带坐姿前推」共用库内条目 fedb:Bench_Press_-_With_Bands |
| 56 | 胸 | 肩、臂 | 弹力带 | 弹力带上推 | 弹力带 - 上推 | Bench Press - With Bands | `weightReps` |  | free-exercise-db:Bench_Press_-_With_Bands | Unlicense | medium | 近似映射：与「弹力带前推、弹力带卧推、弹力带坐姿前推」共用库内条目 fedb:Bench_Press_-_With_Bands |
| 57 | 胸 | 肩、臂 | 弹力带 | 弹力带卧推 | 弹力带 - 卧推 | Bench Press - With Bands | `weightReps` |  | free-exercise-db:Bench_Press_-_With_Bands | Unlicense | high | 近似映射：与「弹力带上推、弹力带前推、弹力带坐姿前推」共用库内条目 fedb:Bench_Press_-_With_Bands |
| 58 | 胸 | 肩、臂 | 弹力带 | 弹力带坐姿前推 | 弹力带 - 坐姿前推 | Bench Press - With Bands | `weightReps` |  | free-exercise-db:Bench_Press_-_With_Bands | Unlicense | medium | 近似映射：与「弹力带上推、弹力带前推、弹力带卧推」共用库内条目 fedb:Bench_Press_-_With_Bands |
| 59 | 肩 |  | 杠铃 | 杠铃前平举 |  | Standing Front Barbell Raise Over Head | `weightReps` |  | free-exercise-db:Standing_Front_Barbell_Raise_Over_Head | Unlicense | medium |  |
| 60 | 肩 | 背 | 杠铃 | 杠铃直立划船 |  | Upright Barbell Row | `weightReps` |  | free-exercise-db:Upright_Barbell_Row | Unlicense | high |  |
| 61 | 肩 | 臂 | 杠铃 | 站姿杠铃推举 |  | Standing Military Press | `weightReps` |  | free-exercise-db:Standing_Military_Press | Unlicense | high | Q7：与现有「杠铃肩上推举」近似；合并 2 行：肩:33（站姿杠铃推举）、肩:38（杠铃过头顶臂） |
| 62 | 肩 | 臂 | 杠铃 | 站姿布拉德福德 |  | Standing Bradford Press | `weightReps` |  | free-exercise-db:Standing_Bradford_Press | Unlicense | high |  |
| 63 | 肩 | 臂 | 杠铃 | 坐姿杠铃推举 |  | Seated Barbell Military Press | `weightReps` |  | free-exercise-db:Seated_Barbell_Military_Press | Unlicense | high |  |
| 64 | 肩 | 背 | 杠铃 | 杠铃俯身提拉 |  | Barbell Rear Delt Row | `weightReps` |  | free-exercise-db:Barbell_Rear_Delt_Row | Unlicense | high |  |
| 65 | 肩 | 背、臂 | 杠铃 | 杠铃片旋转 |  | Plate Twist | `weightReps` |  | free-exercise-db:Plate_Twist | Unlicense | medium |  |
| 66 | 肩 |  | 杠铃 | 杠铃片前平举 |  | Front Plate Raise | `weightReps` |  | free-exercise-db:Front_Plate_Raise | Unlicense | high |  |
| 67 | 肩 | 臂 | 哑铃 | 哑铃推举 |  | Dumbbell Shoulder Press | `weightReps` |  | free-exercise-db:Dumbbell_Shoulder_Press | Unlicense | high | Q7：与现有「哑铃肩上推举」近似 |
| 68 | 肩 | 臂 | 哑铃 | 斯科特推举 |  | Arnold Dumbbell Press | `weightReps` |  | free-exercise-db:Arnold_Dumbbell_Press | Unlicense | medium |  |
| 69 | 肩 | 背 | 哑铃 | 古巴推举 |  | Cuban Press | `weightReps` |  | free-exercise-db:Cuban_Press | Unlicense | high |  |
| 70 | 肩 | 臂 | 哑铃 | 站姿哑铃推举 |  | Standing Dumbbell Press | `weightReps` |  | free-exercise-db:Standing_Dumbbell_Press | Unlicense | high |  |
| 71 | 肩 |  | 哑铃 | 平板上斜侧平举 |  | One-Arm Incline Lateral Raise | `weightReps` | 是 | free-exercise-db:One-Arm_Incline_Lateral_Raise | Unlicense | high |  |
| 72 | 肩 |  | 哑铃 | 哑铃半俯身侧平举 | 半俯身侧平举 | Seated Bent-Over Rear Delt Raise | `weightReps` |  | free-exercise-db:Seated_Bent-Over_Rear_Delt_Raise | Unlicense | medium | 名称规范化 |
| 73 | 肩 |  | 哑铃 | 哑铃上斜俯卧后束飞鸟 | 哑铃上斜俯卧臂 | Lying Rear Delt Raise | `weightReps` |  | free-exercise-db:Lying_Rear_Delt_Raise | Unlicense | medium | 名称规范化 |
| 74 | 肩 | 臂 | 哑铃 | 哑铃上斜仰卧臂上举 | 哑铃上斜仰卧臂 | Dumbbell Incline Shoulder Raise | `weightReps` |  | free-exercise-db:Dumbbell_Incline_Shoulder_Raise | Unlicense | high | 名称规范化 |
| 75 | 肩 | 臂 | 哑铃 | 哑铃锤式复合推 |  | Standing Palms-In Dumbbell Press | `weightReps` |  | free-exercise-db:Standing_Palms-In_Dumbbell_Press | Unlicense | medium |  |
| 76 | 肩 |  | 哑铃 | 哑铃坐姿侧平举 |  | Seated Side Lateral Raise | `weightReps` |  | free-exercise-db:Seated_Side_Lateral_Raise | Unlicense | high |  |
| 77 | 肩 | 背 | 哑铃 | 哑铃上斜Y字举 | 上斜哑铃 Y 字飞 | - | `weightReps` |  | finecoach-built | MIT | low | 名称规范化；low 行，建议采纳（附录 A）；CX-D5 自建条目 |
| 78 | 肩 | 臂 | 固定器械 | 器械坐姿推举 |  | Machine Shoulder (Military) Press | `weightReps` |  | free-exercise-db:Machine_Shoulder_Military_Press | Unlicense | high |  |
| 79 | 肩 |  | 固定器械 | 蝴蝶机反向飞鸟 |  | Reverse Machine Flyes | `weightReps` |  | free-exercise-db:Reverse_Machine_Flyes | Unlicense | high | 近似映射：与「悍马机半俯身侧平举、悍马机开肘俯身飞鸟」共用库内条目 fedb:Reverse_Machine_Flyes |
| 80 | 肩 |  | 固定器械 | 器械把手侧平举 |  | Machine Lateral Raise | `weightReps` |  | wger.de:3d2adf99-8fe9-45cb-b669-c5b18242e282 | CC-BY-SA 4 (© roneydya) | medium |  |
| 81 | 肩 | 臂 | 史密斯机 | 史密斯机推举 |  | Smith Machine Overhead Shoulder Press | `weightReps` |  | free-exercise-db:Smith_Machine_Overhead_Shoulder_Press | Unlicense | high | 近似映射：与「史密斯机站姿肩推」共用库内条目 fedb:Smith_Machine_Overhead_Shoulder_Press |
| 82 | 肩 | 臂 | 史密斯机 | 史密斯机站姿肩推 |  | Smith Machine Overhead Shoulder Press | `weightReps` |  | free-exercise-db:Smith_Machine_Overhead_Shoulder_Press | Unlicense | high | 近似映射：与「史密斯机推举」共用库内条目 fedb:Smith_Machine_Overhead_Shoulder_Press |
| 83 | 肩 | 背 | 绳索 | 肩胛骨后缩热身 | 热身 - 肩胛骨后缩灵活性 | - | `duration` |  | finecoach-built | MIT | low | 名称规范化；low 行，建议采纳（附录 A）；热身命名见 Q3 |
| 84 | 肩 | 背 | 绳索 | 肩胛骨上回旋热身 | 热身 - 肩胛骨上回旋灵活性 | Arm Circles | `duration` |  | free-exercise-db:Arm_Circles | Unlicense | medium | 名称规范化 |
| 85 | 肩 | 背 | 绳索 | 肩胛骨下回旋热身 | 热身 - 肩胛骨下回旋灵活性 | Shoulder Circles | `duration` |  | free-exercise-db:Shoulder_Circles | Unlicense | medium | 名称规范化 |
| 86 | 肩 | 背 | 绳索 | 绳索45度反向飞鸟 | 绳索 45 度单臂反向飞鸟 | Bent Over Low-Pulley Side Lateral | `weightReps` | 是 | free-exercise-db:Bent_Over_Low-Pulley_Side_Lateral | Unlicense | high |  |
| 87 | 肩 | 臂 | 壶铃 | 壶铃推举 |  | Two-Arm Kettlebell Military Press | `weightReps` |  | free-exercise-db:Two-Arm_Kettlebell_Military_Press | Unlicense | high |  |
| 88 | 肩 | 臂 | 壶铃 | 壶铃肩推 | 单臂壶铃肩推 | One-Arm Kettlebell Military Press To The Side | `weightReps` | 是 | free-exercise-db:One-Arm_Kettlebell_Military_Press_To_The_Side | Unlicense | medium |  |
| 89 | 肩 | 臂 | 徒手 | 靠墙倒立撑 |  | Handstand Push-Ups | `reps` |  | free-exercise-db:Handstand_Push-Ups | Unlicense | medium | 近似映射：与「倒立俯卧撑、自由倒立撑」共用库内条目 fedb:Handstand_Push-Ups |
| 90 | 肩 | 臂 | 徒手 | 自由倒立撑 |  | Handstand Push-Ups | `reps` |  | free-exercise-db:Handstand_Push-Ups | Unlicense | high | 近似映射：与「倒立俯卧撑、靠墙倒立撑」共用库内条目 fedb:Handstand_Push-Ups |
| 91 | 肩 | 胸、臂 | 徒手 | 肩内外旋拉伸 | 拉伸 - 肩内外旋 | Round The World Shoulder Stretch | `duration` | 是 | free-exercise-db:Round_The_World_Shoulder_Stretch | Unlicense | medium |  |
| 92 | 肩 |  | 徒手 | 侧转肩拉伸 | 拉伸 - 单臂侧转 | Shoulder Stretch | `duration` | 是 | free-exercise-db:Shoulder_Stretch | Unlicense | high | 名称规范化；近似映射：与「手臂交叉拉伸」共用库内条目 fedb:Shoulder_Stretch |
| 93 | 肩 |  | 徒手 | 手臂交叉拉伸 | 拉伸 - 手臂交叉 | Shoulder Stretch | `duration` | 是 | free-exercise-db:Shoulder_Stretch | Unlicense | medium | 近似映射：与「侧转肩拉伸」共用库内条目 fedb:Shoulder_Stretch |
| 94 | 肩 | 臂 | 徒手 | 倒立俯卧撑 |  | Handstand Push-Ups | `reps` |  | free-exercise-db:Handstand_Push-Ups | Unlicense | high | 近似映射：与「自由倒立撑、靠墙倒立撑」共用库内条目 fedb:Handstand_Push-Ups |
| 95 | 肩 | 臂 | 悍马机 | 悍马机坐姿推举 |  | Leverage Shoulder Press | `weightReps` |  | free-exercise-db:Leverage_Shoulder_Press | Unlicense | medium |  |
| 96 | 肩 |  | 悍马机 | 悍马机侧平举 |  | Machine Side Lateral Raises | `weightReps` |  | wger.de:dc87b735-016c-410b-915c-e3521fea4be7 | CC-BY-SA 4 (© Tierrasverdes) | medium | 近似映射：与现有「器械侧平举」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理） |
| 97 | 肩 |  | 悍马机 | 悍马机半俯身侧平举 | 悍马机半俯身侧 | Reverse Machine Flyes | `weightReps` |  | free-exercise-db:Reverse_Machine_Flyes | Unlicense | medium | 名称规范化；近似映射：与「悍马机开肘俯身飞鸟、蝴蝶机反向飞鸟」共用库内条目 fedb:Reverse_Machine_Flyes |
| 98 | 肩 |  | 悍马机 | 悍马机开肘俯身飞鸟 | 单手开肘悍马俯 | Reverse Machine Flyes | `weightReps` | 是 | free-exercise-db:Reverse_Machine_Flyes | Unlicense | medium | 名称规范化；原名「单手开肘悍马俯」不完整；近似映射：与「悍马机半俯身侧平举、蝴蝶机反向飞鸟」共用库内条目 fedb:Reverse_Machine_Flyes |
| 99 | 肩 | 背、臂 | 悍马机 | 悍马机开肘俯身划船 | 开肘悍马俯身划 | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 名称规范化；近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 100 | 肩 | 背 | 弹力带 | 弹力带面拉 | 弹力带 - 面拉 | Face Pull | `weightReps` |  | free-exercise-db:Face_Pull | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「悬垂带面拉」共用库内条目 fedb:Face_Pull |
| 101 | 肩 | 臂 | 弹力带 | 弹力带坐姿推举 | 弹力带 - 坐姿推举 | Shoulder Press - With Bands | `weightReps` |  | free-exercise-db:Shoulder_Press_-_With_Bands | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带站姿推举」共用库内条目 fedb:Shoulder_Press_-_With_Bands |
| 102 | 肩 | 臂 | 弹力带 | 弹力带站姿推举 | 弹力带 - 站姿推举 | Shoulder Press - With Bands | `weightReps` |  | free-exercise-db:Shoulder_Press_-_With_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带坐姿推举」共用库内条目 fedb:Shoulder_Press_-_With_Bands |
| 103 | 肩 |  | 弹力带 | 弹力带侧平举 | 弹力带 - 侧平举 | Lateral Raise - With Bands | `weightReps` |  | free-exercise-db:Lateral_Raise_-_With_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 104 | 肩 | 背 | 弹力带 | 弹力带侧拉 | 弹力带 - 侧拉 | Band Pull Apart | `weightReps` |  | free-exercise-db:Band_Pull_Apart | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 105 | 肩 | 背、臂 | 弹力带 | 弹力带俯身后束飞鸟 | 弹力带 - 俯身后束飞鸟 | Back Flyes - With Bands | `weightReps` |  | free-exercise-db:Back_Flyes_-_With_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「悬垂带后束飞鸟」共用库内条目 fedb:Back_Flyes_-_With_Bands |
| 106 | 肩 | 背 | 待决 | 悬垂带面拉 | 悬垂带 - 面拉 | Face Pull | `weightReps` |  | free-exercise-db:Face_Pull | Unlicense | medium | 器械待决：名称不含弹力带/悬挂带/TRX；近似映射：与「弹力带面拉」共用库内条目 fedb:Face_Pull；器械待决：原名前缀「悬垂带」不在归一规则内（Q1） |
| 107 | 肩 | 背、臂 | 待决 | 悬垂带后束飞鸟 | 悬垂带 - 后束飞鸟 | Back Flyes - With Bands | `weightReps` |  | free-exercise-db:Back_Flyes_-_With_Bands | Unlicense | medium | 器械待决：名称不含弹力带/悬挂带/TRX；近似映射：与「弹力带俯身后束飞鸟」共用库内条目 fedb:Back_Flyes_-_With_Bands；器械待决：原名前缀「悬垂带」不在归一规则内（Q1） |
| 108 | 背 | 臂 | 杠铃 | 地雷杆划船 | 地雷杆单手划船 | Bent Over One-Arm Long Bar Row | `weightReps` | 是 | free-exercise-db:Bent_Over_One-Arm_Long_Bar_Row | Unlicense | medium |  |
| 109 | 背 | 大腿、臂、臀 | 杠铃 | 半程硬拉 |  | Rack Pulls | `weightReps` |  | free-exercise-db:Rack_Pulls | Unlicense | medium |  |
| 110 | 背 | 臂 | 杠铃 | T杆划船(窄) | T 杆划船（窄） | T-Bar Row with Handle | `weightReps` |  | free-exercise-db:T-Bar_Row_with_Handle | Unlicense | high |  |
| 111 | 背 | 臂 | 杠铃 | T杆划船(宽) | T 杆划船（宽） | Bent Over Two-Arm Long Bar Row | `weightReps` |  | free-exercise-db:Bent_Over_Two-Arm_Long_Bar_Row | Unlicense | medium |  |
| 112 | 背 | 肩、臂 | 杠铃 | 反手杠铃划船 |  | Reverse Grip Bent-Over Rows | `weightReps` |  | free-exercise-db:Reverse_Grip_Bent-Over_Rows | Unlicense | high |  |
| 113 | 背 | 肩、臂 | 杠铃 | 潘德雷划船 |  | Bent Over Barbell Row | `weightReps` |  | free-exercise-db:Bent_Over_Barbell_Row | Unlicense | medium |  |
| 114 | 背 | 臂 | 杠铃 | 俯卧杠铃划船 |  | Lying Cambered Barbell Row | `weightReps` |  | free-exercise-db:Lying_Cambered_Barbell_Row | Unlicense | high |  |
| 115 | 背 | 肩 | 杠铃 | 海豹杠铃划船 |  | Incline Bench Pull | `weightReps` |  | free-exercise-db:Incline_Bench_Pull | Unlicense | medium |  |
| 116 | 背 | 肩、臂 | 哑铃 | 哑铃直立划船 |  | Standing Dumbbell Upright Row | `weightReps` |  | free-exercise-db:Standing_Dumbbell_Upright_Row | Unlicense | high | 分类表为「肩」，按肌肉推为「背」 |
| 117 | 背 | 肩、臂 | 哑铃 | 哑铃划船 |  | One-Arm Dumbbell Row | `weightReps` | 是 | free-exercise-db:One-Arm_Dumbbell_Row | Unlicense | high | Q7：与现有「单臂哑铃划船」（第 2 步改名为「哑铃支撑划船」）同一动作；近似映射：与「哑铃划船(手撑)」共用库内条目 fedb:One-Arm_Dumbbell_Row |
| 118 | 背 | 肩、臂 | 哑铃 | 站姿旋转划船 |  | Bent Over Two-Dumbbell Row | `weightReps` |  | free-exercise-db:Bent_Over_Two-Dumbbell_Row | Unlicense | medium | 近似映射：与「俯卧反手哑铃划船、站姿哑铃划船」共用库内条目 fedb:Bent_Over_Two-Dumbbell_Row |
| 119 | 背 | 肩、臂 | 哑铃 | 哑铃划船(手撑) | 哑铃划船（手） | One-Arm Dumbbell Row | `weightReps` | 是 | free-exercise-db:One-Arm_Dumbbell_Row | Unlicense | high | 名称规范化；Q7：与现有「单臂哑铃划船」（第 2 步改名为「哑铃支撑划船」）同一动作；近似映射：与「哑铃划船」共用库内条目 fedb:One-Arm_Dumbbell_Row |
| 120 | 背 | 肩、臂 | 哑铃 | 站姿哑铃划船 |  | Bent Over Two-Dumbbell Row | `weightReps` |  | free-exercise-db:Bent_Over_Two-Dumbbell_Row | Unlicense | high | 近似映射：与「俯卧反手哑铃划船、站姿旋转划船」共用库内条目 fedb:Bent_Over_Two-Dumbbell_Row |
| 121 | 背 | 胸、肩、臂 | 哑铃 | 平躺哑铃过头拉 |  | Cross-Bench Dumbbell Pullovers | `weightReps` |  | wger.de:6e00afb6-272d-44a2-8ae3-e7fa41b50f06 | CC-BY-SA 3 (© powerade69) | medium |  |
| 122 | 背 | 臂 | 哑铃 | 俯卧哑铃划船 |  | Dumbbell Incline Row | `weightReps` |  | free-exercise-db:Dumbbell_Incline_Row | Unlicense | high |  |
| 123 | 背 | 肩、臂 | 哑铃 | 俯卧反手哑铃划船 |  | Bent Over Two-Dumbbell Row | `weightReps` |  | free-exercise-db:Bent_Over_Two-Dumbbell_Row | Unlicense | medium | 近似映射：与「站姿哑铃划船、站姿旋转划船」共用库内条目 fedb:Bent_Over_Two-Dumbbell_Row |
| 124 | 背 | 臂 | 固定器械 | 器械耸肩 |  | Leverage Shrug | `weightReps` |  | free-exercise-db:Leverage_Shrug | Unlicense | high | 分类表为「肩」，按肌肉推为「背」；近似映射：与「硬拉器械耸肩、耸肩器械耸肩」共用库内条目 fedb:Leverage_Shrug |
| 125 | 背 | 臂 | 固定器械 | 硬拉器械耸肩 |  | Leverage Shrug | `weightReps` |  | free-exercise-db:Leverage_Shrug | Unlicense | medium | 分类表为「肩」，按肌肉推为「背」；近似映射：与「器械耸肩、耸肩器械耸肩」共用库内条目 fedb:Leverage_Shrug |
| 126 | 背 | 臂 | 固定器械 | 耸肩器械耸肩 |  | Leverage Shrug | `weightReps` |  | free-exercise-db:Leverage_Shrug | Unlicense | medium | 分类表为「肩」，按肌肉推为「背」；近似映射：与「器械耸肩、硬拉器械耸肩」共用库内条目 fedb:Leverage_Shrug |
| 127 | 背 |  | 固定器械 | 肩胛引体 |  | Scapular Pull-Up | `weightReps` |  | free-exercise-db:Scapular_Pull-Up | Unlicense | high | 分类表为「肩」，按肌肉推为「背」 |
| 128 | 背 | 肩、臂 | 固定器械 | 窄距引体向上 |  | V-Bar Pullup | `reps` |  | free-exercise-db:V-Bar_Pullup | Unlicense | medium | 近似映射：与「对握引体向上」共用库内条目 fedb:V-Bar_Pullup |
| 129 | 背 | 臂 | 固定器械 | 器械划船 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | Q7：与现有「胸撑器械划船」近似；近似映射：另 12 个中文名（反握式悍马划船、器械大剪刀、坐姿悍马机划船 等）共用库内条目 fedb:Leverage_Iso_Row |
| 130 | 背 | 肩、臂 | 固定器械 | 器械绳索划船 |  | Seated Cable Rows | `weightReps` |  | free-exercise-db:Seated_Cable_Rows | Unlicense | medium | Q7：与现有「坐姿绳索划船」近似；近似映射：与「V把划船、坐姿划船」共用库内条目 fedb:Seated_Cable_Rows |
| 131 | 背 | 臂 | 固定器械 | 器械下拉 |  | Machine Lat Pulldown | `weightReps` |  | wger.de:e6bf0364-ccce-4053-afe1-eef206a50291 | CC-BY-SA 4 (© wger.de) | medium |  |
| 132 | 背 | 臂、核心 | 固定器械 | 引体向上(辅助) | 引体向上（辅助） | Band Assisted Pull-Up | `reps` |  | free-exercise-db:Band_Assisted_Pull-Up | Unlicense | medium | 近似映射：与「辅助引体」共用库内条目 fedb:Band_Assisted_Pull-Up |
| 133 | 背 | 臂 | 固定器械 | 俯卧T杠划船 | 俯卧 T-bar 划船 | Lying T-Bar Row | `weightReps` |  | free-exercise-db:Lying_T-Bar_Row | Unlicense | high |  |
| 134 | 背 | 臂 | 固定器械 | 器械大剪刀 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、坐姿悍马机划船 等）共用库内条目 fedb:Leverage_Iso_Row |
| 135 | 背 | 大腿、臀 | 固定器械 | 水平山羊挺身 |  | Hyperextensions (Back Extensions) | `weightReps` |  | free-exercise-db:Hyperextensions_Back_Extensions | Unlicense | high | 分类表为「臀」，按肌肉推为「背」；Q7：与现有「山羊挺身」近似 |
| 136 | 背 | 肩 | 史密斯机 | 史密斯机背后肩 |  | Smith Machine Behind the Back Shrug | `weightReps` |  | free-exercise-db:Smith_Machine_Behind_the_Back_Shrug | Unlicense | high | 分类表为「肩」，按肌肉推为「背」 |
| 137 | 背 | 肩、臂 | 史密斯机 | 史密斯反手划船 |  | Smith Machine Bent Over Row | `weightReps` |  | free-exercise-db:Smith_Machine_Bent_Over_Row | Unlicense | high |  |
| 138 | 背 |  | 绳索 | 绳索耸肩 |  | Cable Shrugs | `weightReps` |  | free-exercise-db:Cable_Shrugs | Unlicense | high | 分类表为「肩」，按肌肉推为「背」 |
| 139 | 背 | 肩 | 绳索 | 绳索直立划船 |  | Upright Cable Row | `weightReps` |  | free-exercise-db:Upright_Cable_Row | Unlicense | high | 分类表为「肩」，按肌肉推为「背」 |
| 140 | 背 | 肩、臂 | 绳索 | 颈后下拉 |  | Wide-Grip Pulldown Behind The Neck | `weightReps` |  | free-exercise-db:Wide-Grip_Pulldown_Behind_The_Neck | Unlicense | high |  |
| 141 | 背 | 肩、臂 | 绳索 | 宽握反手下拉 |  | Underhand Cable Pulldowns | `weightReps` |  | free-exercise-db:Underhand_Cable_Pulldowns | Unlicense | high | 近似映射：与「窄握反手下拉」共用库内条目 fedb:Underhand_Cable_Pulldowns |
| 142 | 背 | 肩、臂 | 绳索 | V把划船 | V-bar 划船 | Seated Cable Rows | `weightReps` |  | free-exercise-db:Seated_Cable_Rows | Unlicense | medium | 近似映射：与「器械绳索划船、坐姿划船」共用库内条目 fedb:Seated_Cable_Rows |
| 143 | 背 | 肩、臂 | 绳索 | 对握高位下拉 |  | V-Bar Pulldown | `weightReps` |  | free-exercise-db:V-Bar_Pulldown | Unlicense | high | 近似映射：与「V把下拉」共用库内条目 fedb:V-Bar_Pulldown |
| 144 | 背 | 肩、臂 | 绳索 | 坐姿划船 |  | Seated Cable Rows | `weightReps` |  | free-exercise-db:Seated_Cable_Rows | Unlicense | high | 近似映射：与「V把划船、器械绳索划船」共用库内条目 fedb:Seated_Cable_Rows |
| 145 | 背 | 肩、臂 | 绳索 | V把下拉 | V-bar 下拉 | V-Bar Pulldown | `weightReps` |  | free-exercise-db:V-Bar_Pulldown | Unlicense | high | 近似映射：与「对握高位下拉」共用库内条目 fedb:V-Bar_Pulldown |
| 146 | 背 | 臂 | 绳索 | 绳索下拉 | 单手下拉 | One Arm Lat Pulldown | `weightReps` | 是 | free-exercise-db:One_Arm_Lat_Pulldown | Unlicense | high | 名称规范化；近似映射：与「弹力带下拉、绳索分腿站姿下拉」共用库内条目 fedb:One_Arm_Lat_Pulldown |
| 147 | 背 | 肩、臂 | 绳索 | 窄握反手下拉 |  | Underhand Cable Pulldowns | `weightReps` |  | free-exercise-db:Underhand_Cable_Pulldowns | Unlicense | medium | 近似映射：与「宽握反手下拉」共用库内条目 fedb:Underhand_Cable_Pulldowns |
| 148 | 背 | 臂 | 绳索 | 绳索俯身划船 | 绳索单边俯身划 | Shotgun Row | `weightReps` | 是 | free-exercise-db:Shotgun_Row | Unlicense | medium | 名称规范化；原名疑缺「船」 |
| 149 | 背 | 臂 | 绳索 | 绳索分腿站姿下拉 | 绳索分腿站姿单绳 | One Arm Lat Pulldown | `weightReps` | 是 | free-exercise-db:One_Arm_Lat_Pulldown | Unlicense | medium | 名称规范化；原名「绳索分腿站姿单绳」不完整；近似映射：与「弹力带下拉、绳索下拉」共用库内条目 fedb:One_Arm_Lat_Pulldown |
| 150 | 背 | 臂 | 壶铃 | 壶铃大猩猩划船 | 壶铃 大猩猩划船 | Alternating Kettlebell Row | `weightReps` |  | free-exercise-db:Alternating_Kettlebell_Row | Unlicense | high |  |
| 151 | 背 | 大腿、臀 | 徒手 | 超人式 |  | Superman | `reps` |  | free-exercise-db:Superman | Unlicense | high | 分类表为「臀」，按肌肉推为「背」 |
| 152 | 背 | 臀 | 徒手 | 抱膝提拉热身 | 热身 - 交替抱膝提拉 | Hug Knees To Chest | `duration` | 是 | free-exercise-db:Hug_Knees_To_Chest | Unlicense | medium | 分类表为「臀」，按肌肉推为「背」 |
| 153 | 背 | 臂 | 悍马机 | 悍马机划船 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row；合并 2 行：背:32（悍马机划船）、背:38（单手悍马机划船） |
| 154 | 背 | 臂 | 悍马机 | 悍马机大剪刀 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 155 | 背 | 臂 | 悍马机 | 轨道划船器划船 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 156 | 背 |  | 悍马机 | 分动式高位划船 | 分动式高位划 | Leverage High Row | `weightReps` |  | free-exercise-db:Leverage_High_Row | Unlicense | medium | 名称规范化；近似映射：与「悍马机下拉、悍马机高位下拉」共用库内条目 fedb:Leverage_High_Row；合并 2 行：背:36（分动式高位划）、背:42（分动式高位划船） |
| 157 | 背 |  | 悍马机 | 悍马机下拉 | 单手悍马机下拉 | Leverage High Row | `weightReps` | 是 | free-exercise-db:Leverage_High_Row | Unlicense | medium | 近似映射：与「分动式高位划船、悍马机高位下拉」共用库内条目 fedb:Leverage_High_Row |
| 158 | 背 | 臂 | 悍马机 | 支撑式悍马划船 | 单手支撑式悍马 | Leverage Iso Row | `weightReps` | 是 | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 名称规范化；原名「单手支撑式悍马」不完整；近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 159 | 背 | 臂 | 悍马机 | 反握式悍马划船 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（器械划船、器械大剪刀、坐姿悍马机划船 等）共用库内条目 fedb:Leverage_Iso_Row |
| 160 | 背 | 臂 | 悍马机 | 支撑式悍马俯身 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 161 | 背 |  | 悍马机 | 悍马机高位下拉 | 悍马机手下拉 | Leverage High Row | `weightReps` |  | free-exercise-db:Leverage_High_Row | Unlicense | medium | 名称规范化；近似映射：与「分动式高位划船、悍马机下拉」共用库内条目 fedb:Leverage_High_Row |
| 162 | 背 | 胸、臂 | 悍马机 | 悍马机鹦鹉螺 |  | Pullover Machine | `weightReps` |  | wger.de:ad20ef5e-e360-4859-9110-668ee0c24721 | CC-BY-SA 4 (© Paul@Chemistry) | medium | 近似映射：与现有「器械屈臂上拉」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理） |
| 163 | 背 | 臂 | 悍马机 | 坐姿悍马机划船 | 单手坐悍马机 | Leverage Iso Row | `weightReps` | 是 | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 名称规范化；原名「单手坐悍马机」不完整；近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 164 | 背 | 臂 | 悍马机 | 大剪刀划船 | 单边大剪刀划船 | Leverage Iso Row | `weightReps` | 是 | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 165 | 背 | 臂 | 悍马机 | 悍马俯身划船 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 166 | 背 | 臂 | 悍马机 | 挂片划船 |  | Leverage Iso Row | `weightReps` |  | free-exercise-db:Leverage_Iso_Row | Unlicense | medium | 近似映射：另 12 个中文名（反握式悍马划船、器械划船、器械大剪刀 等）共用库内条目 fedb:Leverage_Iso_Row |
| 167 | 背 | 肩 | 弹力带 | 弹力带提拉 | 弹力带 - 提拉 | Upright Row - With Bands | `weightReps` |  | free-exercise-db:Upright_Row_-_With_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「肩」，按肌肉推为「背」；近似映射：与「弹力带坐姿直立划船、弹力带站姿直立划船」共用库内条目 fedb:Upright_Row_-_With_Bands |
| 168 | 背 |  | 弹力带 | 弹力带耸肩 | 弹力带 - 弹力带耸肩 | - | `weightReps` |  | finecoach-built | MIT | low | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「肩」，按肌肉推为「背」；low 行，建议采纳（附录 A）；CX-D5 自建条目 |
| 169 | 背 | 臂 | 弹力带 | 弹力带俯身划船 | 弹力带 俯身划船 | Seated Band Row | `weightReps` |  | wger.de:6b6bd3ce-c40d-486c-9c47-21a3c639626d | CC-BY-SA 4 (© trs1800) | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带坐姿划船」共用库内条目 wger:2635 |
| 170 | 背 | 臂 | 弹力带 | 弹力带坐姿划船 | 弹力带 坐姿划船 | Seated Band Row | `weightReps` |  | wger.de:6b6bd3ce-c40d-486c-9c47-21a3c639626d | CC-BY-SA 4 (© trs1800) | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带俯身划船」共用库内条目 wger:2635 |
| 171 | 背 | 臂 | 弹力带 | 弹力带下拉 | 弹力带 单手下拉 | One Arm Lat Pulldown | `weightReps` | 是 | free-exercise-db:One_Arm_Lat_Pulldown | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「绳索下拉、绳索分腿站姿下拉」共用库内条目 fedb:One_Arm_Lat_Pulldown |
| 172 | 背 | 臂 | 弹力带 | 弹力带跪姿下拉 | 弹力带 跪姿下拉 | Kneeling High Pulley Row | `weightReps` |  | free-exercise-db:Kneeling_High_Pulley_Row | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 173 | 背 |  | 弹力带 | 弹力带直臂下拉 | 弹力带 直臂下拉 | Straight-Arm Pulldown | `weightReps` |  | free-exercise-db:Straight-Arm_Pulldown | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 174 | 背 | 肩 | 弹力带 | 弹力带坐姿直立划船 | 弹力带 坐姿直立划船 | Upright Row - With Bands | `weightReps` |  | free-exercise-db:Upright_Row_-_With_Bands | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带提拉、弹力带站姿直立划船」共用库内条目 fedb:Upright_Row_-_With_Bands |
| 175 | 背 | 肩 | 弹力带 | 弹力带站姿直立划船 | 弹力带 站姿直立划船 | Upright Row - With Bands | `weightReps` |  | free-exercise-db:Upright_Row_-_With_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带坐姿直立划船、弹力带提拉」共用库内条目 fedb:Upright_Row_-_With_Bands |
| 176 | 背 | 肩、臂 | 弹力带 | 弹力带高位下拉 | 弹力带 高位下拉 | Wide-Grip Lat Pulldown | `weightReps` |  | free-exercise-db:Wide-Grip_Lat_Pulldown | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 177 | 背 |  | 悬挂带 | 悬挂带深蹲划船 | 悬挂带 深蹲划船 | TRX Rows | `reps` |  | wger.de:e2599e86-d8b0-434e-8a48-aa3c2df7e790 | CC-BY-SA 4 (© clafal) | medium | 器械按名称拆分：悬挂带 & 弹力带→悬挂带；近似映射：与「悬挂带水平划船」共用库内条目 wger:959 |
| 178 | 背 |  | 悬挂带 | 悬挂带水平划船 | 悬挂带 水平划船 | TRX Rows | `reps` |  | wger.de:e2599e86-d8b0-434e-8a48-aa3c2df7e790 | CC-BY-SA 4 (© clafal) | medium | 器械按名称拆分：悬挂带 & 弹力带→悬挂带；近似映射：与「悬挂带深蹲划船」共用库内条目 wger:959 |
| 179 | 背 | 臂、核心 | 单杠 | 辅助引体 |  | Band Assisted Pull-Up | `reps` |  | free-exercise-db:Band_Assisted_Pull-Up | Unlicense | high | 近似映射：与「引体向上(辅助)」共用库内条目 fedb:Band_Assisted_Pull-Up |
| 180 | 背 | 肩、臂 | 单杠 | 对握引体向上 |  | V-Bar Pullup | `reps` |  | free-exercise-db:V-Bar_Pullup | Unlicense | high | 近似映射：与「窄距引体向上」共用库内条目 fedb:V-Bar_Pullup |
| 181 | 大腿 | 小腿、臀 | 杠铃 | 泽奇深蹲 |  | Zercher Squats | `weightReps` |  | free-exercise-db:Zercher_Squats | Unlicense | high |  |
| 182 | 大腿 | 小腿 | 杠铃 | 杠铃哈克深蹲 |  | Barbell Hack Squat | `weightReps` |  | free-exercise-db:Barbell_Hack_Squat | Unlicense | high |  |
| 183 | 大腿 | 背、臀 | 杠铃 | 高翻 |  | Power Clean | `weightReps` |  | free-exercise-db:Power_Clean | Unlicense | high |  |
| 184 | 大腿 | 背、臀 | 杠铃 | 杰弗森深蹲 |  | Jefferson Squats | `weightReps` |  | free-exercise-db:Jefferson_Squats | Unlicense | high |  |
| 185 | 大腿 | 臀 | 杠铃 | 杠铃保加利亚蹲 | 保加利亚蹲 | Elevated Back Lunge | `weightReps` | 是 | free-exercise-db:Elevated_Back_Lunge | Unlicense | medium | 名称规范化 |
| 186 | 大腿 | 臀 | 杠铃 | 杠铃箭步蹲 |  | Barbell Lunge | `weightReps` |  | free-exercise-db:Barbell_Lunge | Unlicense | high |  |
| 187 | 大腿 | 背、臀 | 杠铃 | 抓举 |  | Snatch | `weightReps` |  | free-exercise-db:Snatch | Unlicense | high |  |
| 188 | 大腿 | 臀 | 杠铃 | SSB深蹲 | SSB 深蹲 | Barbell Squat | `weightReps` |  | free-exercise-db:Barbell_Squat | Unlicense | medium |  |
| 189 | 大腿 | 肩、背、臀 | 杠铃 | 杠铃过头深蹲 |  | Overhead Squat | `weightReps` |  | free-exercise-db:Overhead_Squat | Unlicense | high |  |
| 190 | 大腿 | 臀 | 杠铃 | 杠铃停顿全蹲 |  | Paused Squats | `weightReps` |  | wger.de:a4c97a23-f044-4095-a041-94d92ffe44bd | CC-BY-SA 4 (© bbk) | medium |  |
| 191 | 大腿 | 臀 | 杠铃 | 杠铃相扑深蹲 |  | Wide Stance Barbell Squat | `weightReps` |  | free-exercise-db:Wide_Stance_Barbell_Squat | Unlicense | medium |  |
| 192 | 大腿 | 臀 | 杠铃 | 杠铃箭步蹲(反向) | 杠铃箭步蹲 (反向) | Barbell Step Back Lunge | `weightReps` |  | wger.de:928eeae3-d849-4605-a470-048ca259a8c5 | CC-BY-SA 4 (© wger.de) | high |  |
| 193 | 大腿 | 臀 | 杠铃 | 六角杆硬拉 |  | Trap Bar Deadlift | `weightReps` |  | free-exercise-db:Trap_Bar_Deadlift | Unlicense | high | 器械归一：六角杆→杠铃（CX-D7） |
| 194 | 大腿 |  | 杠铃 | 六角杆深蹲 |  | Trap Bar Squat | `weightReps` |  | wger.de:d18407c2-75d0-43d8-8bbc-dfbb256b6b2f | CC-BY-SA 4 (© kmcalderwood) | high | 器械归一：六角杆→杠铃（CX-D7） |
| 195 | 大腿 | 臀 | 杠铃 | 杠铃上凳 |  | Barbell Step Ups | `weightReps` | 是 | free-exercise-db:Barbell_Step_Ups | Unlicense | high | 分类表为「臀」，按肌肉推为「大腿」 |
| 196 | 大腿 | 臀 | 杠铃 | 杠铃箱式深蹲 |  | Box Squat | `weightReps` |  | free-exercise-db:Box_Squat | Unlicense | high | 分类表为「臀」，按肌肉推为「大腿」；近似映射：与「史密斯机坐蹲」共用库内条目 fedb:Box_Squat |
| 197 | 大腿 | 臂、臀 | 哑铃 | 哑铃二头弯举深蹲 |  | Dumbbell Squat | `weightReps` |  | free-exercise-db:Dumbbell_Squat | Unlicense | medium | 近似映射：与「哑铃深蹲」共用库内条目 fedb:Dumbbell_Squat |
| 198 | 大腿 | 背、臀 | 哑铃 | 哑铃深蹲 |  | Dumbbell Squat | `weightReps` |  | free-exercise-db:Dumbbell_Squat | Unlicense | high | 近似映射：与「哑铃二头弯举深蹲」共用库内条目 fedb:Dumbbell_Squat |
| 199 | 大腿 | 臀、核心 | 哑铃 | 哑铃前蹲 |  | Dumbbell Front Squat | `weightReps` |  | wger.de:4621b41f-0d32-4033-acff-dc079c792606 | CC-BY-SA 4 (© AlucardEvil40) | high |  |
| 200 | 大腿 | 小腿 | 哑铃 | 俯卧哑铃腿弯举 |  | Lying Leg Curls | `weightReps` |  | free-exercise-db:Lying_Leg_Curls | Unlicense | medium |  |
| 201 | 大腿 | 背、臀 | 哑铃 | 哑铃直腿硬拉 |  | Stiff-Legged Dumbbell Deadlift | `weightReps` |  | free-exercise-db:Stiff-Legged_Dumbbell_Deadlift | Unlicense | high |  |
| 202 | 大腿 | 小腿、臀 | 哑铃 | 哑铃箭步蹲 |  | Dumbbell Lunges | `weightReps` |  | free-exercise-db:Dumbbell_Lunges | Unlicense | high |  |
| 203 | 大腿 | 臀 | 哑铃 | 哑铃箭步蹲(反向) | 哑铃箭步蹲 (反向) | Dumbbell Rear Lunge | `weightReps` |  | free-exercise-db:Dumbbell_Rear_Lunge | Unlicense | high |  |
| 204 | 大腿 | 臀 | 哑铃 | 哑铃相扑蹲 |  | Plie Dumbbell Squat | `weightReps` |  | free-exercise-db:Plie_Dumbbell_Squat | Unlicense | medium |  |
| 205 | 大腿 | 肩、臀 | 哑铃 | 哑铃火箭推 |  | Dumbbell Thruster | `weightReps` |  | wger.de:ae6a522e-db10-45ba-9642-987468d8a4de | CC-BY-SA 4 (© meldun) | high |  |
| 206 | 大腿 | 臀 | 哑铃 | 哑铃上凳 |  | Dumbbell Step Ups | `weightReps` | 是 | free-exercise-db:Dumbbell_Step_Ups | Unlicense | high | 分类表为「臀」，按肌肉推为「大腿」 |
| 207 | 大腿 | 背、臀 | 哑铃 | 分腿硬拉 |  | Romanian Deadlift | `weightReps` |  | free-exercise-db:Romanian_Deadlift | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」；合并单侧与双侧两行，默认双侧（单侧由教练切换）；近似映射：与「挂片罗马尼亚硬拉」共用库内条目 fedb:Romanian_Deadlift；合并 2 行：臀:28（分腿硬拉）、臀:29（单手分腿硬拉） |
| 208 | 大腿 | 臀 | 哑铃 | 哑铃甩 |  | Vertical Swing | `weightReps` |  | free-exercise-db:Vertical_Swing | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」 |
| 209 | 大腿 | 臀 | 哑铃 | 哑铃罗马尼亚硬拉 | 哑铃单腿罗马尼亚硬拉 | Single-Leg Deadlift with Dumbbell | `weightReps` | 是 | wger.de:a630de17-9170-434c-b486-96a6b8705506 | CC-BY-SA 4 (© Tierrasverdes) | high | 分类表为「臀」，按肌肉推为「大腿」；Q4：原名「哑铃单腿罗马尼亚硬拉」，去「单腿」后与现有「罗马尼亚硬拉」近似，默认单侧 |
| 210 | 大腿 | 小腿、臀 | 固定器械 | 哈克机深蹲 |  | Hack Squat | `weightReps` |  | free-exercise-db:Hack_Squat | Unlicense | high | 待决 Q6：同一动作在臀:3 器械写哈克机 |
| 211 | 大腿 | 臀 | 固定器械 | 硬拉器硬拉 |  | Leverage Deadlift | `weightReps` |  | free-exercise-db:Leverage_Deadlift | Unlicense | medium |  |
| 212 | 大腿 |  | 固定器械 | 坐姿腿屈伸 |  | Leg Extensions | `weightReps` |  | free-exercise-db:Leg_Extensions | Unlicense | high |  |
| 213 | 大腿 | 臀 | 固定器械 | 器械深蹲 |  | Lying Machine Squat | `weightReps` |  | free-exercise-db:Lying_Machine_Squat | Unlicense | medium |  |
| 214 | 大腿 | 臀 | 固定器械 | 腰带机深蹲 |  | Belt Squat | `weightReps` |  | wger.de:e9f3446f-ca98-4bf2-817c-0dacd123cecd | CC-BY-SA 4 (© wger.de) | high |  |
| 215 | 大腿 | 臀 | 固定器械 | 直腿内收(坐姿) | 直腿内收（坐姿） | Thigh Adductor | `weightReps` |  | free-exercise-db:Thigh_Adductor | Unlicense | high | 分类表为「臀」，按肌肉推为「大腿」 |
| 216 | 大腿 | 臀 | 史密斯机 | 史密斯机保加利亚蹲 |  | Smith Single-Leg Split Squat | `weightReps` | 是 | free-exercise-db:Smith_Single-Leg_Split_Squat | Unlicense | medium |  |
| 217 | 大腿 | 背、臀 | 史密斯机 | 史密斯机坐蹲 |  | Box Squat | `weightReps` |  | free-exercise-db:Box_Squat | Unlicense | medium | 近似映射：与「杠铃箱式深蹲」共用库内条目 fedb:Box_Squat |
| 218 | 大腿 | 背、臀 | 史密斯机 | 史密斯机直腿硬拉 |  | Smith Machine Stiff-Legged Deadlift | `weightReps` |  | free-exercise-db:Smith_Machine_Stiff-Legged_Deadlift | Unlicense | high | 近似映射：与「史密斯罗马尼亚硬拉」共用库内条目 fedb:Smith_Machine_Stiff-Legged_Deadlift |
| 219 | 大腿 | 背、臀 | 史密斯机 | 史密斯机早安 |  | Good Morning | `weightReps` |  | free-exercise-db:Good_Morning | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」 |
| 220 | 大腿 | 背、臀 | 史密斯机 | 史密斯罗马尼亚硬拉 |  | Smith Machine Stiff-Legged Deadlift | `weightReps` |  | free-exercise-db:Smith_Machine_Stiff-Legged_Deadlift | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」；近似映射：与「史密斯机直腿硬拉」共用库内条目 fedb:Smith_Machine_Stiff-Legged_Deadlift |
| 221 | 大腿 | 背、臀 | 绳索 | 绳索直腿硬拉 |  | Cable Deadlifts | `weightReps` |  | free-exercise-db:Cable_Deadlifts | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」 |
| 222 | 大腿 | 臀 | 哈克机 | 哈克机深蹲 |  | Hack Squat | `weightReps` |  | free-exercise-db:Hack_Squat | Unlicense | high | 分类表为「臀」，按肌肉推为「大腿」；待决 Q6：同一动作在腿:35 器械写固定器械 |
| 223 | 大腿 | 小腿、臀 | 徒手 | 深蹲跳 |  | Freehand Jump Squat | `reps` |  | free-exercise-db:Freehand_Jump_Squat | Unlicense | high |  |
| 224 | 大腿 | 臀 | 徒手 | 自重深蹲 |  | Bodyweight Squat | `reps` |  | free-exercise-db:Bodyweight_Squat | Unlicense | high | 近似映射：与「悬吊带深蹲」共用库内条目 fedb:Bodyweight_Squat |
| 225 | 大腿 | 臀 | 徒手 | 自重保加利亚蹲 |  | Bulgarian split squats left | `reps` | 是 | wger.de:7ce489d2-1948-46de-aa80-277b2ca737aa | CC-BY-SA 4 (© wger.de) | medium |  |
| 226 | 大腿 | 小腿、臀 | 徒手 | 自重腿弯举 |  | Natural Glute Ham Raise | `reps` |  | free-exercise-db:Natural_Glute_Ham_Raise | Unlicense | medium |  |
| 227 | 大腿 | 小腿、臀 | 徒手 | 侧步深蹲 |  | Side Slides + Squats | `reps` |  | wger.de:cd7bbafc-4092-4194-aa20-e380f1fe45f0 | CC-BY-SA 4 (© Insight) | medium |  |
| 228 | 大腿 | 臀 | 徒手 | 前后摆腿热身 | 热身 - 腘后摆腿 | Leg Swings (Front-Back) | `duration` | 是 | wger.de:1fae7d45-0731-4640-8809-94c76b836571 | CC-BY-SA 4 (© Jhonatan) | high | 名称规范化；近似映射：与「侧向摆腿热身」共用库内条目 wger:1670 |
| 229 | 大腿 |  | 徒手 | 滑雪式拉伸 | 拉伸 - 滑雪 | - | `duration` |  | finecoach-built | MIT | low | 名称规范化；low 行，建议采纳（附录 A）；CX-D5 自建条目 |
| 230 | 大腿 | 小腿 | 徒手 | 坐姿腿拉伸 | 拉伸 - 坐姿腿拉 | Seated Floor Hamstring Stretch | `duration` | 是 | free-exercise-db:Seated_Floor_Hamstring_Stretch | Unlicense | high | 名称规范化 |
| 231 | 大腿 | 小腿 | 徒手 | 直腿弯腰拉伸 | 拉伸 - 直腿弯腰 | Standing Toe Touches | `duration` |  | free-exercise-db:Standing_Toe_Touches | Unlicense | high |  |
| 232 | 大腿 | 臀 | 徒手 | 箭步蹲拉伸 | 拉伸 - 箭步蹲拉 | Runners Lunge Stretch | `duration` | 是 | wger.de:92cd0459-5cd1-46a0-934d-e7cff8d4ccda | CC-BY-SA 4 (© Davidgj32) | high | 名称规范化 |
| 233 | 大腿 |  | 徒手 | 仰卧抬腿拉伸 | 拉伸 - 仰卧抬腿 | Leg-Up Hamstring Stretch | `duration` | 是 | free-exercise-db:Leg-Up_Hamstring_Stretch | Unlicense | high |  |
| 234 | 大腿 | 小腿 | 徒手 | 站姿腿拉伸 | 拉伸 - 站姿腿拉 | Standing Hamstring and Calf Stretch | `duration` | 是 | free-exercise-db:Standing_Hamstring_and_Calf_Stretch | Unlicense | high | 名称规范化 |
| 235 | 大腿 |  | 徒手 | 髋屈肌与股四头肌拉伸 | 拉伸 - 髋屈肌与股四头肌 | Intermediate Hip Flexor and Quad Stretch | `duration` | 是 | free-exercise-db:Intermediate_Hip_Flexor_and_Quad_Stretch | Unlicense | high |  |
| 236 | 大腿 | 背、臀 | 悍马机 | 挂片罗马尼亚硬拉 | 挂片式罗马尼亚 | Romanian Deadlift | `weightReps` |  | free-exercise-db:Romanian_Deadlift | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」；名称规范化；原名疑缺「硬拉」；近似映射：与「分腿硬拉」共用库内条目 fedb:Romanian_Deadlift |
| 237 | 大腿 | 背、臀 | 弹力带 | 弹力带反向早安 | 弹力带 反向早安 | Band Good Morning | `weightReps` |  | free-exercise-db:Band_Good_Morning | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「背」，按肌肉推为「大腿」；近似映射：与「弹力带早安、弹力带直腿硬拉」共用库内条目 fedb:Band_Good_Morning |
| 238 | 大腿 | 核心 | 弹力带 | 弹力带提腿 |  | Hip Flexion with Band | `weightReps` | 是 | free-exercise-db:Hip_Flexion_with_Band | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 239 | 大腿 | 臀 | 弹力带 | 弹力带箭步蹲 |  | Lunges | `weightReps` |  | wger.de:3284fd27-5402-4821-9c32-29066d4e2667 | CC-BY-SA 4 (© wger.de) | medium | 近似映射：与现有「徒手弓步」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）；器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 240 | 大腿 | 小腿 | 弹力带 | 弹力带平躺腿弯举 |  | Seated Band Hamstring Curl | `weightReps` |  | free-exercise-db:Seated_Band_Hamstring_Curl | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 241 | 大腿 | 小腿 | 弹力带 | 弹力带站姿腿弯举 |  | Leg Curls (standing) | `weightReps` |  | wger.de:49189e88-40b6-4c0d-a784-0cc3abbb8e75 | CC-BY-SA 3 (© wger.de) | medium | 近似映射：与现有「站姿腿弯举」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）；器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 242 | 大腿 |  | 弹力带 | 弹力带站姿内收 | 弹力带站姿单腿内收 | Band Hip Adductions | `weightReps` | 是 | free-exercise-db:Band_Hip_Adductions | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 243 | 大腿 | 肩 | 弹力带 | 弹力带登山者 |  | Mountain Climbers | `weightReps` |  | free-exercise-db:Mountain_Climbers | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 244 | 大腿 | 小腿、臀 | 弹力带 | 弹力带箭步走 |  | Bodyweight Walking Lunge | `weightReps` |  | free-exercise-db:Bodyweight_Walking_Lunge | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 245 | 大腿 | 背、臀 | 弹力带 | 弹力带深蹲 |  | Squats - With Bands | `weightReps` |  | free-exercise-db:Squats_-_With_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；合并单侧与双侧两行，默认双侧（单侧由教练切换）；合并行来源不同：free-exercise-db:Single-Leg_High_Box_Squat、free-exercise-db:Squats_-_With_Bands；合并 2 行：腿:76（弹力带深蹲）、腿:77（弹力带单腿深蹲） |
| 246 | 大腿 | 背、臀 | 弹力带 | 弹力带直腿硬拉 | 弹力带 - 直腿硬拉 | Band Good Morning | `weightReps` |  | free-exercise-db:Band_Good_Morning | Unlicense | medium | 分类表为「臀」，按肌肉推为「大腿」；近似映射：与「弹力带反向早安、弹力带早安」共用库内条目 fedb:Band_Good_Morning |
| 247 | 大腿 | 背、臀 | 弹力带 | 弹力带早安 | 弹力带 - 早安 | Band Good Morning | `weightReps` |  | free-exercise-db:Band_Good_Morning | Unlicense | high | 分类表为「臀」，按肌肉推为「大腿」；近似映射：与「弹力带反向早安、弹力带直腿硬拉」共用库内条目 fedb:Band_Good_Morning |
| 248 | 大腿 | 臀 | 其他 | 保加利亚蹲(负重) | 保加利亚蹲（负重） | Bulgarian Squat with Dumbbells | `weightReps` | 是 | wger.de:60d2c34b-43a1-48a3-b43b-160e4c0157f2 | CC-BY-SA 4 (© AlucardEvil40) | medium | 近似映射：与现有「哑铃保加利亚分腿蹲」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）；来源器材为「其他」，按规则保留 |
| 249 | 大腿 | 小腿、臀 | 其他 | 跳箱 |  | Box Jumps | `reps` |  | wger.de:002c6a4f-28ac-4b07-8e94-053e5b05d52b | CC-BY-SA 4 (© tekknokrat@gmx.de) | high | 来源器材为「其他」，按规则保留 |
| 250 | 大腿 | 臀 | 待决 | 悬吊带深蹲 |  | Bodyweight Squat | `reps` |  | free-exercise-db:Bodyweight_Squat | Unlicense | medium | 器械待决：名称不含弹力带/悬挂带/TRX；近似映射：与「自重深蹲」共用库内条目 fedb:Bodyweight_Squat；器械待决：原名前缀「悬吊带」不在归一规则内（Q1） |
| 251 | 小腿 |  | 杠铃 | 坐姿杠铃提踵 |  | Barbell Seated Calf Raise | `weightReps` |  | free-exercise-db:Barbell_Seated_Calf_Raise | Unlicense | high |  |
| 252 | 小腿 |  | 杠铃 | 杠铃站姿提踵 |  | Standing Barbell Calf Raise | `weightReps` |  | free-exercise-db:Standing_Barbell_Calf_Raise | Unlicense | high |  |
| 253 | 小腿 |  | 哑铃 | 站姿哑铃提踵 |  | Standing Dumbbell Calf Raise | `weightReps` |  | free-exercise-db:Standing_Dumbbell_Calf_Raise | Unlicense | high |  |
| 254 | 小腿 |  | 固定器械 | 坐姿器械提踵 |  | Seated Calf Raise | `weightReps` |  | free-exercise-db:Seated_Calf_Raise | Unlicense | high |  |
| 255 | 小腿 |  | 史密斯机 | 史密斯机提踵 |  | Smith Machine Calf Raise | `weightReps` |  | free-exercise-db:Smith_Machine_Calf_Raise | Unlicense | high |  |
| 256 | 小腿 |  | 徒手 | 踝关节绕环热身 | 热身 - 踝关节绕环 | Ankle Circles | `duration` |  | free-exercise-db:Ankle_Circles | Unlicense | high |  |
| 257 | 小腿 |  | 徒手 | 墙面小腿拉伸(直膝) | 拉伸 - 墙面小腿（直膝） | Calf Stretch Hands Against Wall | `duration` | 是 | free-exercise-db:Calf_Stretch_Hands_Against_Wall | Unlicense | high |  |
| 258 | 小腿 |  | 徒手 | 墙面比目鱼肌拉伸(屈膝) | 拉伸 - 墙面比目鱼肌（屈膝） | Standing Soleus And Achilles Stretch | `duration` | 是 | free-exercise-db:Standing_Soleus_And_Achilles_Stretch | Unlicense | high |  |
| 259 | 小腿 |  | 徒手 | 坐姿腓骨肌拉伸 | 拉伸 - 坐姿腓骨肌 | Peroneals Stretch | `duration` | 是 | free-exercise-db:Peroneals_Stretch | Unlicense | high |  |
| 260 | 小腿 |  | 徒手 | 跪姿胫骨肌拉伸 | 拉伸 - 跪姿胫骨肌 | Anterior Tibialis-SMR | `duration` | 是 | free-exercise-db:Anterior_Tibialis-SMR | Unlicense | medium |  |
| 261 | 小腿 | 大腿 | 徒手 | 膝关节绕环热身 | 热身 - 膝关节小幅环绕 | Knee Circles | `duration` |  | free-exercise-db:Knee_Circles | Unlicense | high | 分类表为「大腿」，按肌肉推为「小腿」；名称规范化 |
| 262 | 臂 |  | 杠铃 | EZ杠二头弯举 | EZ 杠二头弯举 | EZ-Bar Curl | `weightReps` |  | free-exercise-db:EZ-Bar_Curl | Unlicense | high |  |
| 263 | 臂 |  | 杠铃 | 仰卧杠铃臂屈伸 |  | Lying Triceps Press | `weightReps` |  | free-exercise-db:Lying_Triceps_Press | Unlicense | medium | Q7：与现有「仰卧臂屈伸(碎颅者)」疑同一动作 |
| 264 | 臂 | 胸、肩 | 杠铃 | 窄距卧推(靠近) | 窄距卧推（靠近） | Close-Grip Barbell Bench Press | `weightReps` |  | free-exercise-db:Close-Grip_Barbell_Bench_Press | Unlicense | high | Q7：与现有「窄距卧推」近似；近似映射：与「窄距卧推(散开)」共用库内条目 fedb:Close-Grip_Barbell_Bench_Press |
| 265 | 臂 |  | 杠铃 | 杠铃拖拉弯举 |  | Drag Curl | `weightReps` |  | free-exercise-db:Drag_Curl | Unlicense | high |  |
| 266 | 臂 |  | 杠铃 | 杠铃俯身上斜弯举 |  | Barbell Curls Lying Against An Incline | `weightReps` |  | free-exercise-db:Barbell_Curls_Lying_Against_An_Incline | Unlicense | high |  |
| 267 | 臂 |  | 杠铃 | 蜘蛛弯举 |  | Spider Curl | `weightReps` |  | free-exercise-db:Spider_Curl | Unlicense | high |  |
| 268 | 臂 |  | 杠铃 | 杠铃集中弯举 |  | Seated Close-Grip Concentration Barbell Curl | `weightReps` |  | free-exercise-db:Seated_Close-Grip_Concentration_Barbell_Curl | Unlicense | high |  |
| 269 | 臂 | 肩 | 杠铃 | 坐姿杠铃过头臂屈伸 |  | Standing Overhead Barbell Triceps Extension | `weightReps` |  | free-exercise-db:Standing_Overhead_Barbell_Triceps_Extension | Unlicense | medium |  |
| 270 | 臂 | 胸、肩 | 杠铃 | 窄距卧推(散开) | 窄距卧推（散开） | Close-Grip Barbell Bench Press | `weightReps` |  | free-exercise-db:Close-Grip_Barbell_Bench_Press | Unlicense | medium | Q7：与现有「窄距卧推」近似；近似映射：与「窄距卧推(靠近)」共用库内条目 fedb:Close-Grip_Barbell_Bench_Press |
| 271 | 臂 |  | 杠铃 | 杠铃碎颅者 |  | EZ-Bar Skullcrusher | `weightReps` |  | free-exercise-db:EZ-Bar_Skullcrusher | Unlicense | high | Q7：与现有「仰卧臂屈伸(碎颅者)」疑同一动作 |
| 272 | 臂 |  | 杠铃 | 正手杠铃手腕弯举 |  | Palms-Down Wrist Curl Over A Bench | `weightReps` |  | free-exercise-db:Palms-Down_Wrist_Curl_Over_A_Bench | Unlicense | high |  |
| 273 | 臂 |  | 杠铃 | EZ正手杠铃弯举 | EZ 正手杠铃弯举 | Reverse Barbell Curl | `weightReps` |  | free-exercise-db:Reverse_Barbell_Curl | Unlicense | medium |  |
| 274 | 臂 |  | 杠铃 | 杠铃片正手弯举 |  | Reverse Plate Curls | `weightReps` |  | free-exercise-db:Reverse_Plate_Curls | Unlicense | high |  |
| 275 | 臂 |  | 哑铃 | 坐姿哑铃牧师凳弯举 | 坐姿单手牧师凳弯举 | One Arm Dumbbell Preacher Curl | `weightReps` | 是 | free-exercise-db:One_Arm_Dumbbell_Preacher_Curl | Unlicense | high | 名称规范化；近似映射：与「哑铃牧师凳弯举」共用库内条目 fedb:One_Arm_Dumbbell_Preacher_Curl |
| 276 | 臂 |  | 哑铃 | 坐姿哑铃弯举 |  | Seated Dumbbell Curl | `weightReps` |  | free-exercise-db:Seated_Dumbbell_Curl | Unlicense | high |  |
| 277 | 臂 |  | 哑铃 | 牧师凳锤式弯举 |  | Preacher Hammer Dumbbell Curl | `weightReps` |  | free-exercise-db:Preacher_Hammer_Dumbbell_Curl | Unlicense | high |  |
| 278 | 臂 |  | 哑铃 | 集中弯举 |  | Concentration Curls | `weightReps` |  | free-exercise-db:Concentration_Curls | Unlicense | high | 近似映射：与「弹力带集中弯举」共用库内条目 fedb:Concentration_Curls |
| 279 | 臂 |  | 哑铃 | 上斜锤式弯举 |  | Incline Hammer Curls | `weightReps` |  | free-exercise-db:Incline_Hammer_Curls | Unlicense | high |  |
| 280 | 臂 | 胸、肩 | 哑铃 | 碎颅者 |  | Lying Dumbbell Tricep Extension | `weightReps` |  | free-exercise-db:Lying_Dumbbell_Tricep_Extension | Unlicense | high |  |
| 281 | 臂 |  | 哑铃 | 哑铃臂屈伸 |  | Standing Dumbbell Triceps Extension | `weightReps` |  | free-exercise-db:Standing_Dumbbell_Triceps_Extension | Unlicense | high |  |
| 282 | 臂 |  | 哑铃 | 坐姿哑铃臂屈伸 | 坐姿哑铃单臂臂屈伸 | Seated Bent-Over One-Arm Dumbbell Triceps Extension | `weightReps` | 是 | free-exercise-db:Seated_Bent-Over_One-Arm_Dumbbell_Triceps_Extension | Unlicense | high |  |
| 283 | 臂 |  | 哑铃 | 哑铃坐姿牧师凳弯举 |  | Two-Arm Dumbbell Preacher Curl | `weightReps` |  | free-exercise-db:Two-Arm_Dumbbell_Preacher_Curl | Unlicense | high |  |
| 284 | 臂 | 胸、肩 | 哑铃 | 哑铃Tate推举 | 哑铃 Tate 推举 | Tate Press | `weightReps` |  | free-exercise-db:Tate_Press | Unlicense | high |  |
| 285 | 臂 |  | 哑铃 | 哑铃酒杯弯举 |  | Dumbbell Bicep Curl | `weightReps` |  | free-exercise-db:Dumbbell_Bicep_Curl | Unlicense | medium |  |
| 286 | 臂 |  | 哑铃 | 哑铃牧师凳弯举 | 单臂牧师凳弯举 | One Arm Dumbbell Preacher Curl | `weightReps` | 是 | free-exercise-db:One_Arm_Dumbbell_Preacher_Curl | Unlicense | high | 名称规范化；近似映射：与「坐姿哑铃牧师凳弯举」共用库内条目 fedb:One_Arm_Dumbbell_Preacher_Curl |
| 287 | 臂 |  | 哑铃 | 上斜哑铃弯举 |  | Incline Dumbbell Curl | `weightReps` |  | free-exercise-db:Incline_Dumbbell_Curl | Unlicense | high |  |
| 288 | 臂 |  | 哑铃 | 卧姿弯举 |  | Lying Supine Dumbbell Curl | `weightReps` |  | free-exercise-db:Lying_Supine_Dumbbell_Curl | Unlicense | high |  |
| 289 | 臂 |  | 哑铃 | 哑铃反手腕弯举 |  | Palms-Down Dumbbell Wrist Curl Over A Bench | `weightReps` |  | free-exercise-db:Palms-Down_Dumbbell_Wrist_Curl_Over_A_Bench | Unlicense | high |  |
| 290 | 臂 |  | 哑铃 | 反握集中弯举 |  | Standing Dumbbell Reverse Curl | `weightReps` |  | free-exercise-db:Standing_Dumbbell_Reverse_Curl | Unlicense | medium |  |
| 291 | 臂 |  | 哑铃 | 哑铃佐特曼弯举 |  | Zottman Curl | `weightReps` |  | free-exercise-db:Zottman_Curl | Unlicense | high |  |
| 292 | 臂 |  | 哑铃 | 哑铃手腕弯举(反手) | 单手哑铃手腕弯举（反手） | Seated One-Arm Dumbbell Palms-Up Wrist Curl | `weightReps` | 是 | free-exercise-db:Seated_One-Arm_Dumbbell_Palms-Up_Wrist_Curl | Unlicense | high |  |
| 293 | 臂 |  | 哑铃 | 哑铃手腕弯举(正手) | 单手哑铃手腕弯举（正手） | Seated One-Arm Dumbbell Palms-Down Wrist Curl | `weightReps` | 是 | free-exercise-db:Seated_One-Arm_Dumbbell_Palms-Down_Wrist_Curl | Unlicense | high |  |
| 294 | 臂 |  | 哑铃 | 垂式哑铃手腕弯举 |  | Seated Dumbbell Palms-Down Wrist Curl | `weightReps` |  | free-exercise-db:Seated_Dumbbell_Palms-Down_Wrist_Curl | Unlicense | medium |  |
| 295 | 臂 |  | 固定器械 | 坐姿器械二头弯举 |  | Machine Bicep Curl | `weightReps` |  | free-exercise-db:Machine_Bicep_Curl | Unlicense | high | 近似映射：与「上斜器械弯举」共用库内条目 fedb:Machine_Bicep_Curl |
| 296 | 臂 |  | 固定器械 | 器械三头下压 |  | Machine Triceps Extension | `weightReps` |  | free-exercise-db:Machine_Triceps_Extension | Unlicense | high |  |
| 297 | 臂 |  | 固定器械 | 器械牧师凳弯举 | 牧师凳弯举 | Machine Preacher Curls | `weightReps` |  | free-exercise-db:Machine_Preacher_Curls | Unlicense | high | 名称规范化 |
| 298 | 臂 |  | 固定器械 | 上斜器械弯举 |  | Machine Bicep Curl | `weightReps` |  | free-exercise-db:Machine_Bicep_Curl | Unlicense | medium | 近似映射：与「坐姿器械二头弯举」共用库内条目 fedb:Machine_Bicep_Curl |
| 299 | 臂 |  | 绳索 | 直杆绳索弯举 |  | Straight Bar Cable Curls | `weightReps` |  | wger.de:36274d27-3812-4b8c-80e2-ab59acf82c4d | CC-BY-SA 4 (© novadani) | high |  |
| 300 | 臂 |  | 绳索 | 绳索过头臂屈伸 |  | Cable Rope Overhead Triceps Extension | `weightReps` |  | free-exercise-db:Cable_Rope_Overhead_Triceps_Extension | Unlicense | high |  |
| 301 | 臂 |  | 绳索 | 绳索高位前拉 |  | High Cable Curls | `weightReps` |  | free-exercise-db:High_Cable_Curls | Unlicense | medium |  |
| 302 | 臂 |  | 绳索 | 绳索三头肌臂屈伸 | 单手绳索三头肌 | Cable One Arm Tricep Extension | `weightReps` | 是 | free-exercise-db:Cable_One_Arm_Tricep_Extension | Unlicense | high | 名称规范化；原名疑缺「臂屈伸」 |
| 303 | 臂 |  | 绳索 | 直杆正手绳索弯举 |  | Reverse Cable Curl | `weightReps` |  | free-exercise-db:Reverse_Cable_Curl | Unlicense | high |  |
| 304 | 臂 |  | 绳索 | 背后绳索弯举 | 背后二头单边弯举 | Standing One-Arm Cable Curl | `weightReps` | 是 | free-exercise-db:Standing_One-Arm_Cable_Curl | Unlicense | medium | 名称规范化 |
| 305 | 臂 |  | 绳索 | 跪姿绳索臂屈伸 |  | Kneeling Cable Triceps Extension | `weightReps` |  | free-exercise-db:Kneeling_Cable_Triceps_Extension | Unlicense | high |  |
| 306 | 臂 |  | 绳索 | 反手三头臂屈伸 |  | Reverse Grip Triceps Pushdown | `weightReps` |  | free-exercise-db:Reverse_Grip_Triceps_Pushdown | Unlicense | high |  |
| 307 | 臂 | 胸、肩 | 绳索 | 绳索臂屈伸 | 单手绳索臂屈伸 | Standing Low-Pulley One-Arm Triceps Extension | `weightReps` | 是 | free-exercise-db:Standing_Low-Pulley_One-Arm_Triceps_Extension | Unlicense | high |  |
| 308 | 臂 |  | 绳索 | 绳索训练器 |  | Standing Biceps Cable Curl | `weightReps` |  | free-exercise-db:Standing_Biceps_Cable_Curl | Unlicense | medium | 待决：原名「绳索训练器」不是动作名（Q5） |
| 309 | 臂 |  | 绳索 | 绳索过头弯举 |  | Overhead Cable Curl | `weightReps` |  | free-exercise-db:Overhead_Cable_Curl | Unlicense | high |  |
| 310 | 臂 |  | 绳索 | 绳索手腕弯举 |  | Cable Wrist Curl | `weightReps` |  | free-exercise-db:Cable_Wrist_Curl | Unlicense | high |  |
| 311 | 臂 | 胸、肩 | 徒手 | 窄距俯卧撑 |  | Push-Ups - Close Triceps Position | `reps` |  | free-exercise-db:Push-Ups_-_Close_Triceps_Position | Unlicense | high | 近似映射：与「臂屈伸式俯卧撑」共用库内条目 fedb:Push-Ups_-_Close_Triceps_Position |
| 312 | 臂 | 胸、肩 | 徒手 | 平板臂屈伸 |  | Bench Dips | `reps` |  | free-exercise-db:Bench_Dips | Unlicense | high |  |
| 313 | 臂 |  | 徒手 | 手腕绕环热身 | 热身 - 手腕绕环 | Wrist Circles | `duration` |  | free-exercise-db:Wrist_Circles | Unlicense | high |  |
| 314 | 臂 |  | 徒手 | 手腕屈肌拉伸 | 拉伸 - 手腕屈肌 | Kneeling Forearm Stretch | `duration` | 是 | free-exercise-db:Kneeling_Forearm_Stretch | Unlicense | high |  |
| 315 | 臂 | 肩 | 徒手 | 手腕伸肌拉伸 | 拉伸 - 手腕伸肌 | Side Wrist Pull | `duration` | 是 | free-exercise-db:Side_Wrist_Pull | Unlicense | medium |  |
| 316 | 臂 | 背 | 徒手 | 三头肌拉伸 | 拉伸 - 三头肌 | Overhead Triceps | `duration` | 是 | free-exercise-db:Overhead_Triceps | Unlicense | high | 分类表为「肩」，按肌肉推为「臂」 |
| 317 | 臂 |  | 弹力带 | 弹力带站姿弯举 | 弹力带二头弯举（站姿） | - | `weightReps` |  | finecoach-built | MIT | low | 器械按名称拆分：悬挂带 & 弹力带→弹力带；名称规范化；low 行，建议采纳（附录 A）；CX-D5 自建条目 |
| 318 | 臂 |  | 弹力带 | 弹力带集中弯举 |  | Concentration Curls | `weightReps` |  | free-exercise-db:Concentration_Curls | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「集中弯举」共用库内条目 fedb:Concentration_Curls |
| 319 | 臂 |  | 弹力带 | 弹力带锤式弯举 |  | Hammer Curls | `weightReps` |  | free-exercise-db:Hammer_Curls | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 320 | 臂 |  | 弹力带 | 弹力带碎颅者 |  | Band Skull Crusher | `weightReps` |  | free-exercise-db:Band_Skull_Crusher | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 321 | 臂 |  | 弹力带 | 弹力带过头臂屈伸 |  | Speed Band Overhead Triceps | `weightReps` |  | free-exercise-db:Speed_Band_Overhead_Triceps | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带臂屈伸」共用库内条目 fedb:Speed_Band_Overhead_Triceps |
| 322 | 臂 |  | 弹力带 | 弹力带臂屈伸 | 弹力带单手臂屈伸 | Speed Band Overhead Triceps | `weightReps` | 是 | free-exercise-db:Speed_Band_Overhead_Triceps | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；近似映射：与「弹力带过头臂屈伸」共用库内条目 fedb:Speed_Band_Overhead_Triceps |
| 323 | 臂 |  | 弹力带 | 弹力带三头压拉 |  | Triceps Pushdown | `weightReps` |  | free-exercise-db:Triceps_Pushdown | Unlicense | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带 |
| 324 | 臂 |  | 悬挂带 | 悬挂带二头弯举 |  | Biceps with TRX | `reps` |  | wger.de:596b9d2d-0f01-41a0-97e1-1839ffdb824d | CC-BY-SA 4 (© clafal) | high | 器械按名称拆分：悬挂带 & 弹力带→悬挂带 |
| 325 | 臂 |  | 悬挂带 | 悬挂带臂屈伸 |  | TRX Tricep Extension | `reps` |  | wger.de:de8a3db6-2b05-4c4e-977b-b61342718356 | CC-BY-SA 4 (© cynomops) | high | 器械按名称拆分：悬挂带 & 弹力带→悬挂带 |
| 326 | 臀 | 大腿、小腿 | 杠铃 | 杠铃臀桥 |  | Barbell Glute Bridge | `weightReps` |  | free-exercise-db:Barbell_Glute_Bridge | Unlicense | high |  |
| 327 | 臀 | 背、大腿 | 杠铃 | 地雷杆硬拉 |  | Barbell Deadlift | `weightReps` |  | free-exercise-db:Barbell_Deadlift | Unlicense | medium |  |
| 328 | 臀 | 大腿 | 哑铃 | 哑铃臀冲 |  | Dumbbell Hip Thrust | `weightReps` |  | wger.de:af77220c-098c-47c2-9f8c-92a651998903 | CC-BY-SA 4 (© AlucardEvil40) | high | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；合并行来源不同：wger.de:7cc24acf-3fc9-4d14-a461-cd00d1d18f0e、wger.de:af77220c-098c-47c2-9f8c-92a651998903；合并 2 行：臀:24（哑铃臀冲）、臀:25（单腿哑铃臀冲） |
| 329 | 臀 | 大腿 | 哑铃 | 哑铃青蛙臀桥 |  | Dumbbell Frog Press | `weightReps` |  | wger.de:b407768d-d519-47b8-818a-44c9761a8be6 | CC-BY-SA 4 (© JohnPreston) | high |  |
| 330 | 臀 |  | 固定器械 | 坐姿髋外展 |  | Thigh Abductor | `weightReps` |  | free-exercise-db:Thigh_Abductor | Unlicense | high | 分类表为「大腿」，按肌肉推为「臀」；近似映射：与「悍马机外展、直腿髋外展(坐姿)」共用库内条目 fedb:Thigh_Abductor |
| 331 | 臀 | 大腿 | 固定器械 | 器械髋冲 |  | Glute Drive | `weightReps` |  | wger.de:ce21d3a2-cdc5-410c-9970-c25029ca3769 | CC-BY-SA 4 (© schweezer) | high | 近似映射：与「悍马机臀冲」共用库内条目 wger:1528 |
| 332 | 臀 |  | 固定器械 | 直腿髋外展(坐姿) | 直腿髋外展（坐姿） | Thigh Abductor | `weightReps` |  | free-exercise-db:Thigh_Abductor | Unlicense | high | 近似映射：与「坐姿髋外展、悍马机外展」共用库内条目 fedb:Thigh_Abductor |
| 333 | 臀 | 大腿 | 史密斯机 | 史密斯机上踢 |  | Glute Kickback (Machine) | `weightReps` | 是 | wger.de:66ed6788-a1d8-49a2-af4d-397107fbf5fb | CC-BY-SA 4 (© barry) | medium | 近似映射：与现有「器械臀屈伸」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）；分类表为「大腿」，按肌肉推为「臀」；近似映射：与「史密斯后踢、挂片后摆腿」共用库内条目 wger:1723 |
| 334 | 臀 | 大腿、小腿 | 史密斯机 | 史密斯臀冲 |  | - | `weightReps` |  | finecoach-built | MIT | low | low 行，建议采纳（附录 A）；CX-D5 自建条目 |
| 335 | 臀 | 大腿 | 史密斯机 | 史密斯后踢 |  | Glute Kickback (Machine) | `weightReps` | 是 | wger.de:66ed6788-a1d8-49a2-af4d-397107fbf5fb | CC-BY-SA 4 (© barry) | medium | 近似映射：与现有「器械臀屈伸」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）；近似映射：与「史密斯机上踢、挂片后摆腿」共用库内条目 wger:1723 |
| 336 | 臀 | 大腿 | 绳索 | 绳索站姿后踢 |  | One-Legged Cable Kickback | `weightReps` | 是 | free-exercise-db:One-Legged_Cable_Kickback | Unlicense | high | 近似映射：与「俯身驴踢、站姿驴踢」共用库内条目 fedb:One-Legged_Cable_Kickback |
| 337 | 臀 | 大腿 | 绳索 | 俯身驴踢 |  | One-Legged Cable Kickback | `weightReps` | 是 | free-exercise-db:One-Legged_Cable_Kickback | Unlicense | medium | 近似映射：与「站姿驴踢、绳索站姿后踢」共用库内条目 fedb:One-Legged_Cable_Kickback |
| 338 | 臀 | 大腿 | 绳索 | 站姿驴踢 |  | One-Legged Cable Kickback | `weightReps` | 是 | free-exercise-db:One-Legged_Cable_Kickback | Unlicense | medium | 近似映射：与「俯身驴踢、绳索站姿后踢」共用库内条目 fedb:One-Legged_Cable_Kickback |
| 339 | 臀 |  | 绳索 | 绳索侧踢 |  | Abduction while standing | `weightReps` | 是 | wger.de:d015a276-02ad-4c28-9d36-aedfbb431f53 | CC-BY-SA 4 (© tregga) | medium | 近似映射：与「弹力带站姿外展、站姿髋外展」共用库内条目 wger:1096 |
| 340 | 臀 | 肩、背、大腿 | 徒手 | 反向支撑交叉腿 |  | Reverse Plank | `duration` |  | wger.de:09349391-375b-42d5-8979-00a5d7196a5b | CC-BY-SA 4 (© spacetowaste) | medium | 分类表为「核心」，按肌肉推为「臀」 |
| 341 | 臀 | 大腿 | 徒手 | 跪姿青蛙拉伸 | 拉伸 - 跪姿青蛙 | Frog Stretch | `duration` |  | wger.de:a37001e9-b4b3-45db-8ee3-046f40350efa | CC-BY-SA 4 (© Croak6728) | high | 分类表为「大腿」，按肌肉推为「臀」；近似映射：与「摇摆青蛙式热身」共用库内条目 wger:1844 |
| 342 | 臀 | 大腿 | 徒手 | 后踢 |  | Glute Kickback | `reps` | 是 | free-exercise-db:Glute_Kickback | Unlicense | high |  |
| 343 | 臀 | 大腿 | 徒手 | 自重臀冲 |  | Butt Lift (Bridge) | `reps` |  | free-exercise-db:Butt_Lift_Bridge | Unlicense | high | 近似映射：与「垫高自重臀冲、腿后侧臀桥」共用库内条目 fedb:Butt_Lift_Bridge |
| 344 | 臀 | 大腿 | 徒手 | 垫高自重臀冲 |  | Butt Lift (Bridge) | `reps` |  | free-exercise-db:Butt_Lift_Bridge | Unlicense | medium | 近似映射：与「腿后侧臀桥、自重臀冲」共用库内条目 fedb:Butt_Lift_Bridge |
| 345 | 臀 | 大腿 | 徒手 | 腿后侧臀桥 |  | Butt Lift (Bridge) | `reps` |  | free-exercise-db:Butt_Lift_Bridge | Unlicense | medium | 近似映射：与「垫高自重臀冲、自重臀冲」共用库内条目 fedb:Butt_Lift_Bridge |
| 346 | 臀 | 核心 | 徒手 | 侧平板蛤壳 |  | Clamshell | `reps` | 是 | wger.de:ca3ca5d0-5231-4420-ad06-fa3d32693a1b | CC-BY-SA 4 (© teus_ergaster) | medium |  |
| 347 | 臀 |  | 徒手 | 仰卧交叉腿 |  | Lying Crossover | `duration` | 是 | free-exercise-db:Lying_Crossover | Unlicense | high | Q8：源条目 Lying Crossover 是拉伸，按时长 |
| 348 | 臀 | 大腿 | 徒手 | 臀桥 | 单腿臀桥 | Single Leg Glute Bridge | `reps` | 是 | free-exercise-db:Single_Leg_Glute_Bridge | Unlicense | high | Q4：去掉「单腿」后与现有「徒手臀桥」近似，默认单侧 |
| 349 | 臀 |  | 徒手 | 侧向摆腿热身 | 热身 - 侧向摆腿 | Leg Swings (Front-Back) | `duration` | 是 | wger.de:1fae7d45-0731-4640-8809-94c76b836571 | CC-BY-SA 4 (© Jhonatan) | medium | 近似映射：与「前后摆腿热身」共用库内条目 wger:1670 |
| 350 | 臀 | 大腿 | 徒手 | 摇摆青蛙式热身 | 热身 - 摇摆青蛙式 | Frog Stretch | `duration` |  | wger.de:a37001e9-b4b3-45db-8ee3-046f40350efa | CC-BY-SA 4 (© Croak6728) | high | 近似映射：与「跪姿青蛙拉伸」共用库内条目 wger:1844 |
| 351 | 臀 |  | 徒手 | 坐姿梨状肌拉伸 | 拉伸 - 坐姿梨状肌 | Seated Piriformis Stretch | `duration` | 是 | wger.de:ad5653e4-098e-4a84-af5b-a9349b108555 | CC-BY-SA 4 (© Pete-E automation) | high |  |
| 352 | 臀 |  | 徒手 | 仰卧四字臀肌拉伸 | 拉伸 - 仰卧四字臀肌 | Lying Figure Four Stretch | `duration` | 是 | wger.de:76b6e798-e484-4606-aa64-8421aea51e88 | CC-BY-SA 4 (© Davidgj32) | high |  |
| 353 | 臀 |  | 徒手 | 泡沫轴臀部放松 | 拉伸 - 泡沫轴臀冲 | Foam Roller Gluteus | `duration` | 是 | wger.de:164a31e9-ce70-4339-aee5-4ea7a3bdd246 | CC-BY-SA 4 (© Davidgj32) | medium | 名称规范化；泡沫轴放松，按 CX-D8 收入；不是拉伸；Q8：按泡沫轴放松记时长 |
| 354 | 臀 |  | 徒手 | 滚轮腿交叉拉伸 | 拉伸 - 滚轮腿交叉 | Piriformis-SMR | `duration` | 是 | free-exercise-db:Piriformis-SMR | Unlicense | medium |  |
| 355 | 臀 | 大腿 | 悍马机 | 悍马机臀冲 |  | Glute Drive | `weightReps` |  | wger.de:ce21d3a2-cdc5-410c-9970-c25029ca3769 | CC-BY-SA 4 (© schweezer) | medium | 近似映射：与「器械髋冲」共用库内条目 wger:1528 |
| 356 | 臀 |  | 悍马机 | 悍马机外展 |  | Thigh Abductor | `weightReps` |  | free-exercise-db:Thigh_Abductor | Unlicense | medium | 近似映射：与「坐姿髋外展、直腿髋外展(坐姿)」共用库内条目 fedb:Thigh_Abductor |
| 357 | 臀 | 大腿 | 悍马机 | 挂片后摆腿 |  | Glute Kickback (Machine) | `weightReps` | 是 | wger.de:66ed6788-a1d8-49a2-af4d-397107fbf5fb | CC-BY-SA 4 (© barry) | medium | 近似映射：与现有「器械臀屈伸」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理）；近似映射：与「史密斯后踢、史密斯机上踢」共用库内条目 wger:1723 |
| 358 | 臀 | 大腿 | 悍马机 | 挂片站姿臀冲 |  | Machine glute extension | `weightReps` |  | wger.de:ab872d04-ca20-4341-b3c9-76763b25ef42 | CC-BY-SA 4 (© Franpol) | medium | 近似映射：与现有「器械臀伸」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理） |
| 359 | 臀 |  | 悍马机 | 站姿髋外展 |  | Abduction while standing | `weightReps` | 是 | wger.de:d015a276-02ad-4c28-9d36-aedfbb431f53 | CC-BY-SA 4 (© tregga) | medium | 近似映射：与「弹力带站姿外展、绳索侧踢」共用库内条目 wger:1096 |
| 360 | 臀 | 大腿 | 弹力带 | 弹力带站姿踢腿 |  | Hip Extension with Bands | `weightReps` | 是 | free-exercise-db:Hip_Extension_with_Bands | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「大腿」，按肌肉推为「臀」；近似映射：与「弹力带跪姿腿屈伸」共用库内条目 fedb:Hip_Extension_with_Bands |
| 361 | 臀 |  | 弹力带 | 弹力带站姿外展 | 弹力带站姿单推外展 | Abduction while standing | `weightReps` | 是 | wger.de:d015a276-02ad-4c28-9d36-aedfbb431f53 | CC-BY-SA 4 (© tregga) | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「大腿」，按肌肉推为「臀」；名称规范化；近似映射：与「站姿髋外展、绳索侧踢」共用库内条目 wger:1096 |
| 362 | 臀 |  | 弹力带 | 弹力带坐姿腿外展 |  | Seated Hip Abduction | `weightReps` |  | wger.de:b144ac00-ec0c-4c43-898f-b2ac65048d98 | CC-BY-SA 4 (© Iko) | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「大腿」，按肌肉推为「臀」；合并 2 行：腿:78（弹力带坐姿腿外展）、臀:57（弹力带 - 坐姿腿外展） |
| 363 | 臀 |  | 弹力带 | 弹力带螃蟹行走 | 弹力带螃式走 | Monster Walk | `weightReps` |  | free-exercise-db:Monster_Walk | Unlicense | high | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「大腿」，按肌肉推为「臀」；名称规范化；合并 2 行：腿:79（弹力带螃式走）、臀:60（弹力带 - 螃蟹行走） |
| 364 | 臀 | 大腿 | 弹力带 | 弹力带仰卧腿外展 |  | Supine Hip Abduction | `weightReps` | 是 | wger.de:2fe15ae4-085b-4116-8d73-2a120cc2a231 | CC-BY-SA 4 (© teus_ergaster) | medium | 器械按名称拆分：悬挂带 & 弹力带→弹力带；分类表为「大腿」，按肌肉推为「臀」 |
| 365 | 臀 | 大腿 | 弹力带 | 弹力带跪姿腿屈伸 | 弹力带 - 跪姿腿屈伸 | Hip Extension with Bands | `weightReps` |  | free-exercise-db:Hip_Extension_with_Bands | Unlicense | high | 近似映射：与「弹力带站姿踢腿」共用库内条目 fedb:Hip_Extension_with_Bands |
| 366 | 臀 |  | 弹力带 | 弹力带侧躺腿外展 | 弹力带 - 侧躺腿外展 | Side Lying Hip Abduction | `weightReps` | 是 | wger.de:7212cc74-656e-47ce-8292-d211676f2ee1 | CC-BY-SA 4 (© wakanda90) | medium |  |
| 367 | 臀 |  | 弹力带 | 弹力带蚌式开合 | 弹力带 - 蚌式开合 | Banded Clamshell | `weightReps` | 是 | wger.de:8cc84753-e638-4c43-91c6-51c097813ca4 | CC-BY-SA 4 (© Croak6728) | high |  |
| 368 | 臀 | 大腿、小腿 | 弹力带 | 弹力带跪姿臀冲 | 弹力带 - 跪姿臀冲 | Hip Lift with Band | `weightReps` |  | free-exercise-db:Hip_Lift_with_Band | Unlicense | high |  |
| 369 | 臀 |  | 弹力带 | 弹力带髋外展 | 弹力带 - 髋外展 | Quadruped Hip Abduction | `weightReps` |  | wger.de:2a1f7c0c-c63d-43f1-9934-a209ed405ff8 | CC-BY-SA 4 (© treder) | high |  |
| 370 | 核心 | 肩 | 杠铃 | 地雷杆甩 |  | Landmine 180's | `weightReps` |  | free-exercise-db:Landmine_180s | Unlicense | medium |  |
| 371 | 核心 |  | 杠铃 | 负重下斜卷腹 |  | Decline Crunch | `weightReps` |  | free-exercise-db:Decline_Crunch | Unlicense | medium | 器械归一：杠铃片→杠铃（CX-D7）；近似映射：与「下斜卷腹」共用库内条目 fedb:Decline_Crunch |
| 372 | 核心 |  | 哑铃 | 哑铃侧弯 |  | Dumbbell Side Bend | `weightReps` |  | free-exercise-db:Dumbbell_Side_Bend | Unlicense | high |  |
| 373 | 核心 |  | 固定器械 | 器械侧卷腹 |  | Side Bends on Machine | `weightReps` |  | wger.de:919bb48a-42fe-4a11-9078-ea2b5087c49f | CC-BY-SA 3 (© klabautermann) | medium |  |
| 374 | 核心 |  | 固定器械 | 滑轮器卷腹 |  | Cable Crunch | `weightReps` |  | free-exercise-db:Cable_Crunch | Unlicense | high | Q7：与现有「龙门架卷腹」近似；近似映射：与「绳索跪姿卷腹」共用库内条目 fedb:Cable_Crunch |
| 375 | 核心 |  | 绳索 | 绳索跪姿卷腹 |  | Cable Crunch | `weightReps` |  | free-exercise-db:Cable_Crunch | Unlicense | high | Q7：与现有「龙门架卷腹」近似；近似映射：与「滑轮器卷腹」共用库内条目 fedb:Cable_Crunch |
| 376 | 核心 | 背 | 绳索 | 站姿绳索转体 |  | Trunk Rotation With Cable | `weightReps` |  | wger.de:90e9f590-7d68-4afb-9f95-8429246ea4aa | CC-BY-SA 4 (© Robertcoop) | high |  |
| 377 | 核心 |  | 绳索 | 站姿绳索卷腹 |  | Standing Rope Crunch | `weightReps` |  | free-exercise-db:Standing_Rope_Crunch | Unlicense | high |  |
| 378 | 核心 | 肩 | 徒手 | 静态侧卧支撑 |  | Side Bridge | `duration` |  | free-exercise-db:Side_Bridge | Unlicense | high |  |
| 379 | 核心 | 臀 | 徒手 | 平板支撑摆腿 | 平板支撑交替摆 | Plank with Alternating Leg Lift | `duration` |  | wger.de:94f2dea6-b336-41b2-a438-3ab7b13adbf7 | CC-BY-SA 4 (© hpmbala@gmail.com) | medium | 名称规范化 |
| 380 | 核心 | 肩、大腿、小腿、臂 | 徒手 | 固定熊爬 |  | Bear Walk 2 | `duration` |  | wger.de:b7267f90-8706-442b-b918-507e16092b8e | CC-BY-SA 4 (© nate303303) | medium | Q8：按静止熊爬记时长 |
| 381 | 核心 |  | 徒手 | 左右摸脚踝 |  | Alternate Heel Touchers | `reps` |  | free-exercise-db:Alternate_Heel_Touchers | Unlicense | high | 近似映射：与「仰卧触脚卷腹」共用库内条目 fedb:Alternate_Heel_Touchers |
| 382 | 核心 | 肩、臂 | 徒手 | 平板肘撑转换 | 平板交替手肘支 | Plank-to-Elbow Extension | `reps` |  | wger.de:e75629ed-4991-4a48-984c-b297f3f9fb58 | CC-BY-SA 4 (© clafal) | high | 名称规范化；Q8：按交替动作记次数 |
| 383 | 核心 |  | 徒手 | 坐姿提膝卷腹 | 坐姿交替提膝卷腹 | Seated Knee Tuck | `reps` |  | wger.de:371cfda2-1de6-419a-b40c-fc98fd3f7e41 | CC-BY-SA 4 (© utkb) | high |  |
| 384 | 核心 |  | 徒手 | 坐姿直腿抬腿 | 坐姿交替直腿抬腿 | Seated Flat Bench Leg Pull-In | `reps` |  | free-exercise-db:Seated_Flat_Bench_Leg_Pull-In | Unlicense | medium |  |
| 385 | 核心 |  | 徒手 | 坐姿交叉对侧提膝 |  | Seated Corkscrew | `reps` |  | wger.de:e9891a94-b1d4-47f4-a82b-c1aa82121abb | CC-BY-SA 4 (© Moffi) | medium |  |
| 386 | 核心 |  | 徒手 | 负重俄罗斯转体 |  | Russian Twist | `weightReps` |  | wger.de:10510fb5-6ebd-4ddc-b03e-423b15deceea | CC-BY-SA 4 (© lion) | high | 近似映射：与现有「俄罗斯转体」共用 wger 条目 UUID（来源表器械/变式不同，未按已在库处理） |
| 387 | 核心 |  | 徒手 | 负重仰卧起坐 |  | Sit-Up | `weightReps` |  | free-exercise-db:Sit-Up | Unlicense | medium |  |
| 388 | 核心 |  | 徒手 | 3/4仰卧起坐 |  | 3/4 Sit-Up | `reps` |  | free-exercise-db:3_4_Sit-Up | Unlicense | high |  |
| 389 | 核心 |  | 徒手 | 蝴蝶收腹 |  | Butterfly Sit Up | `reps` |  | wger.de:1bb3bbaf-2dc2-4651-95db-71faf5304075 | CC-BY-SA 4 (© Moffi) | high | 近似映射：与「平板蝴蝶收腹」共用库内条目 wger:1476 |
| 390 | 核心 |  | 徒手 | 平板蝴蝶收腹 |  | Butterfly Sit Up | `reps` |  | wger.de:1bb3bbaf-2dc2-4651-95db-71faf5304075 | CC-BY-SA 4 (© Moffi) | medium | 近似映射：与「蝴蝶收腹」共用库内条目 wger:1476 |
| 391 | 核心 |  | 徒手 | 空中单车 |  | Air Bike | `reps` |  | free-exercise-db:Air_Bike | Unlicense | high | 近似映射：与「空中单车(高难)」共用库内条目 fedb:Air_Bike |
| 392 | 核心 |  | 徒手 | 空中单车(高难) |  | Air Bike | `reps` |  | free-exercise-db:Air_Bike | Unlicense | medium | 近似映射：与「空中单车」共用库内条目 fedb:Air_Bike |
| 393 | 核心 |  | 徒手 | 平躺蹬姿转体 |  | Bicycle Crunches | `reps` |  | wger.de:fcf5039b-7784-4f82-830a-b213b597a646 | CC-BY-SA 4 (© hpmbala@gmail.com) | medium |  |
| 394 | 核心 |  | 徒手 | 上斜卷腹转体 |  | Incline Crunches | `reps` |  | wger.de:7de7b8a8-313d-465f-bb22-8527ae45110a | CC-BY-SA 3 (© wger.de) | medium |  |
| 395 | 核心 |  | 徒手 | 平躺曲腿旋转拉伸 | 拉伸-平躺曲腿旋转 | Torso rotation stretch | `duration` |  | wger.de:1e9b886f-0dbe-4434-829e-7159bcc40692 | CC-BY-SA 4 (© hpmbala@gmail.com) | medium |  |
| 396 | 核心 |  | 徒手 | 贴地俯卧撑转体拉伸 | 拉伸-贴地俯卧撑转体 | Push-up rotations | `duration` |  | wger.de:a9633731-1d86-4b4a-996f-33a1dee0b0e1 | CC-BY-SA 4 (© wger.de) | medium |  |
| 397 | 核心 |  | 徒手 | 抱头侧身拉伸 | 拉伸-单手抱头侧身 | Standing Lateral Stretch | `duration` | 是 | free-exercise-db:Standing_Lateral_Stretch | Unlicense | high |  |
| 398 | 核心 |  | 徒手 | 反向卷腹 |  | Reverse Crunch | `reps` |  | free-exercise-db:Reverse_Crunch | Unlicense | high |  |
| 399 | 核心 |  | 徒手 | 仰卧触脚卷腹 | 仰卧交替触脚卷腹 | Alternate Heel Touchers | `reps` |  | free-exercise-db:Alternate_Heel_Touchers | Unlicense | high | 近似映射：与「左右摸脚踝」共用库内条目 fedb:Alternate_Heel_Touchers |
| 400 | 核心 |  | 徒手 | 45度侧弯 |  | Side bend | `reps` |  | wger.de:d36fdd3c-9a35-4643-a3fd-57db78c866d6 | CC-BY-SA 4 (© wger.de) | medium |  |
| 401 | 核心 |  | 徒手 | 下斜卷腹 |  | Decline Crunch | `reps` |  | free-exercise-db:Decline_Crunch | Unlicense | high | 近似映射：与「负重下斜卷腹」共用库内条目 fedb:Decline_Crunch |
| 402 | 核心 |  | 徒手 | 空心摇摆 |  | Hollow Hold | `duration` |  | wger.de:d059c63d-0a81-48a3-912a-44070c0def2e | CC0 | medium | 名字是「摇摆」但源条目是 Hollow Hold 静态支撑，按时长 |
| 403 | 核心 |  | 徒手 | 仰卧摆脚 |  | Scissor Kick | `reps` |  | free-exercise-db:Scissor_Kick | Unlicense | high |  |
| 404 | 核心 |  | 徒手 | 蹬腿 |  | Flutter Kicks | `reps` |  | wger.de:fdc550b6-ec58-4023-ba62-b54045e9a10d | CC-BY-SA 4 (© nate303303) | medium |  |
| 405 | 核心 | 大腿、臂 | 徒手 | L坐 |  | L-sit | `duration` |  | wger.de:16202754-f567-4d23-a866-2c9cc8eba71d | CC-BY-SA 4 (© Croak6728) | high |  |
| 406 | 核心 |  | 徒手 | 仰卧肘碰膝 |  | Elbow to Knee | `reps` |  | free-exercise-db:Elbow_to_Knee | Unlicense | high |  |
| 407 | 核心 | 肩 | 徒手 | 龙旗 |  | Dragon-flag | `reps` |  | wger.de:f5ad82a8-adf8-4795-9874-1f6d183c56ed | CC-BY-SA 4 (© clafal) | high |  |
| 408 | 核心 |  | 弹力带 | 弹力带仰卧卷腹 | 弹力带-仰卧卷腹 | Crunches | `weightReps` |  | free-exercise-db:Crunches | Unlicense | medium |  |
| 409 | 核心 |  | 单杠 | 悬垂屈膝举腿 |  | Knee Raises | `reps` |  | wger.de:f4991a98-6422-4884-8ad3-43412f91fac1 | CC-BY-SA 4 (© clafal) | high |  |
| 410 | 核心 |  | 单杠 | 前悬举腿 |  | Hanging Leg Raise | `reps` |  | free-exercise-db:Hanging_Leg_Raise | Unlicense | high |  |
| 411 | 核心 | 大腿 | 单杠 | 悬垂举腿抬腿 |  | Leg raises pull up bar | `reps` |  | wger.de:b2025776-2397-4de7-a49e-296321169481 | CC-BY-SA 4 (© clafal) | high |  |

说明：中文名由来源表动作名按 CX-D3 规范化；原名只在改名时显示。空白的「单侧默认」表示默认双侧；「是」表示默认单侧。拉伸/热身类里一次只练一侧的（如 坐姿梨状肌拉伸、单腿拉伸）默认单侧，两侧同时做的默认双侧。来源 `finecoach-built` 的条目按 CX-D5 为 FineCoach 自建，作者 `FineCoach`，许可 `MIT`。

## 附录 A：low 行（21 行）采纳建议

| 结论 | 文件:行 | 原器械 | 原动作名 | 建议规范名 | 器械 | 记录方式 | 单侧默认 | 主部位 | 次要部位 | 理由 |
|---|---|---|---|---|---|---|---|---|---|---|
| 建议采纳 | 上臂:66 | 悬挂带 & 弹力带 | 弹力带二头弯举（站姿） | 弹力带站姿弯举 | 弹力带 | `weightReps` | 否 | 臂 | — | 弹力带站姿弯举是带新手、课前热身的常规手臂动作，现有目录弹力带器械完全空白。 |
| 不采纳 | 上臂:67 | 悬挂带 & 弹力带 | 弹力带站姿轮换弯举 | — | — | — | — | — | — | 与上臂:66 只差轮换节奏，CX-D3 又不能在名字里写交替，收进来是两条几乎一样的记录。 |
| 不采纳 | 上臂:70 | 悬挂带 & 弹力带 | 弹力带坐姿弯举 | — | — | — | — | — | — | 坐姿只是同一弹力带弯举换体位，教练课不会分开记录，站姿版已足够。 |
| 不采纳 | 上臂:80 | 无 | 铃铃二头弯举 | — | — | — | — | — | — | 「铃铃」是明显错字、器材列又填「无」，动作无法确认；按哑铃或杠铃读都会撞现有条目。 |
| 建议采纳 | 肩:21 | 哑铃 | 上斜哑铃 Y 字飞 | 哑铃上斜Y字举 | 哑铃 | `weightReps` | 否 | 肩 | 背 | 上斜 Y 字举是肩后束/下斜方肌和圆肩改善的常用辅助动作，现有「哑铃后束飞鸟」方向不同。 |
| 建议采纳 | 肩:58 | 绳索 | 热身 - 肩胛骨后缩灵活性 | 肩胛骨后缩热身 | 绳索 | `duration` | 否 | 肩 | 背 | 肩胛骨后缩是肩带热身和圆肩矫正常规练习；同表上/下回旋两条已按 medium 自动收录，缺后缩就断了序列。 |
| 建议采纳 | 肩:73 | 悬挂带 & 弹力带 | 弹力带 - 弹力带耸肩 | 弹力带耸肩 | 弹力带 | `weightReps` | 否 | 背 | — | 弹力带耸肩是弹力带热身和斜方肌基础训练常规动作；现有耸肩只有杠铃/哑铃/史密斯/绳索。 |
| 不采纳 | 背:18 | 绳索 | 绳索站旋转划 | — | — | — | — | — | — | 「站旋转划」名称残缺，不是标准动作名；划船和转体已分别被「坐姿绳索划船」「站姿绳索转体」覆盖。 |
| 不采纳 | 背:75 | 悬挂带 & 弹力带 | 悬挂带 坐姿下拉（负重） | — | — | — | — | — | — | 悬挂带坐姿下拉还要额外负重，固定方式别扭，不是教练课会用的做法；悬挂带拉类已有深蹲划船/水平划船。 |
| 不采纳 | 背:80 | 悬挂带 & 弹力带 | 弹力带 单手划船 | — | — | — | — | — | — | 单臂弹力带划船与已收录弹力带俯身/坐姿划船是同一动作的单侧版，去「单手」后无法区分。 |
| 不采纳 | 背:86 | 悬挂带 & 弹力带 | 弹力带 反手下拉 | — | — | — | — | — | — | 反手弹力带下拉只是已收录「弹力带高位下拉」的握法变式，弹力带下拉已有四条。 |
| 不采纳 | 腹:48 | 弹力带 | 弹力带-跪姿卷腹 | — | — | — | — | — | — | 跪姿卷腹已被「绳索跪姿卷腹」覆盖，弹力带仰卧卷腹也已收录，不新增动作模式。 |
| 不采纳 | 腹:50 | 弹力带 | 弹力带-下上转体 | — | — | — | — | — | — | 「下上转体」不是通用动作名，与「上下转体」只差字序、肌肉列相同，无法确认区别。 |
| 不采纳 | 腹:51 | 弹力带 | 弹力带-上下转体 | — | — | — | — | — | — | 与腹:50 只差字序、肌肉列完全相同，是重复行。 |
| 不采纳 | 腹:52 | 弹力带 | 弹力带-十字转体 | — | — | — | — | — | — | 「十字转体」名称不通用、动作路线无法确认；旋转/抗旋已由绳索转体、帕洛夫、伐木覆盖。 |
| 不采纳 | 腿:65 | 无 | 手枪深蹲 (有支撑) | — | — | — | — | — | — | 现有目录已有「手枪深蹲」，支撑版只是同一动作的退阶，CX-D3 又不许名字写「有支撑」，收进来就是重名。 |
| 不采纳 | 腿:73 | 悬挂带 & 弹力带 | 弹力带仰卧登山者 | — | — | — | — | — | — | 「仰卧登山者」不是通用动作名、动作形式不清；已收录「弹力带登山者」。 |
| 不采纳 | 腿:80 | 悬挂带 & 弹力带 | 弹力带鸭式前行 | — | — | — | — | — | — | 弹力带鸭步是田径式热身，教练课记录频率低；同类弹力带走类已有「弹力带螃蟹行走」。 |
| 建议采纳 | 腿:89 | 无 | 拉伸 - 滑雪 | 滑雪式拉伸 | 徒手 | `duration` | 否 | 大腿 | — | 滑雪式（宽距体前屈）是腘绳肌+内收肌的常见静态拉伸；现有「直腿弯腰」是窄距版，覆盖不了内收肌。 |
| 建议采纳 | 臀:19 | 史密斯机 | 史密斯臀冲 | 史密斯臀冲 | 史密斯机 | `weightReps` | 否 | 臀 | 大腿、小腿 | 史密斯机臀冲是健身房臀冲的主流器械做法，现有目录只有杠铃臀冲和徒手臀桥，史密斯版是真实需要的器械区分。 |
| 不采纳 | 臀:23 | 史密斯机 | 史密斯机俯卧蛙 | — | — | — | — | — | — | 「俯卧蛙」是青蛙式臀激活的非标准叫法，史密斯机上怎么做无法确认；同类已有哑铃青蛙臀桥、摇摆青蛙式。 |

采纳的 6 条按 CX-D5 作为 FineCoach 自建条目（作者 `FineCoach`，许可 `MIT`）；来源表这 6 行的动作英文名是 `-`，第 2 步写 `provenance.json` 时需要为自建条目确定 `sourceEnglishName`（建议用对应英文动作名，或按自建标记处理）。

来源表数据质量问题（不改输入，仅记录）：`上臂:80` 的「铃铃二头弯举」是错字；`背:18` 的「绳索站旋转划」名称残缺；`腹:50/51/52` 三条弹力带转体名称互相矛盾、肌肉列不一致。

## 附录 B：已在库（不新增，以现有条目为准）

| 文件:行 | 原器械 | 原名 | 规范名 | 现有中文名 | 现有 id | 匹配依据 | 备注 |
|---|---|---|---|---|---|---|---|
| 上臂:3 | 哑铃 | 哑铃弯举 | 哑铃弯举 | 哑铃弯举 | `1ae6a28d-10e7-4ecf-af4f-905f8193e2c6` | 中文名相同 |  |
| 上臂:4 | 哑铃 | 哑铃轮换弯举 | 哑铃弯举 | 哑铃弯举 | `1ae6a28d-10e7-4ecf-af4f-905f8193e2c6` | 中文名相同 | 去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4） |
| 上臂:10 | 哑铃 | 哑铃过头臂屈伸 | 哑铃过头臂屈伸 | 哑铃过头臂屈伸 | `19133a0d-e6b2-4d57-8a84-8aac3d962a99` | 中文名相同 |  |
| 上臂:19 | 哑铃 | 锤式弯举 | 锤式弯举 | 哑铃锤式弯举 | `c0d9fe98-f4fe-49f3-8037-05e1984e7d2d` | 英文名相同 |  |
| 上臂:25 | 杠铃 | 牧师凳弯举 | 牧师凳弯举 | 牧师凳弯举 | `dd52fb99-9426-4a78-b446-20a8e3e4ec47` | 中文名相同 |  |
| 上臂:26 | 杠铃 | 杠铃弯举 | 杠铃弯举 | 杠铃弯举 | `7b99a081-6b1a-4aa5-b86a-5a935d083a35` | 中文名相同 |  |
| 上臂:36 | 杠铃 | 正手杠铃弯举 | 杠铃弯举 | 杠铃弯举 | `7b99a081-6b1a-4aa5-b86a-5a935d083a35` | 中文名相同 |  |
| 上臂:38 | 绳索 | 绳索弯举 | 绳索弯举 | 绳索弯举 | `479ef6f0-5274-4da7-b5ad-67528ff3c8fd` | 中文名相同 |  |
| 上臂:42 | 绳索 | V-Bar 绳索下压 | V把下压 | V把下压 | `ea63d85c-8579-4dda-b99f-c4c8930f9af6` | 中文名相同 |  |
| 上臂:43 | 绳索 | 绳索臂屈伸（站姿） | 绳索下压 | 绳索下压 | `fc608f0e-d754-4911-ae59-8856952e7064` | 中文名相同 |  |
| 上臂:46 | 绳索 | 绳索下压（站姿） | 绳索下压(站姿) | 直杆下压 | `6ebb138e-bb0a-402e-84e5-68fe0896e897` | 英文名相同 |  |
| 上臂:51 | 绳索 | 直杆绳索下压 | 直杆绳索下压 | 直杆下压 | `6ebb138e-bb0a-402e-84e5-68fe0896e897` | 英文名相同 |  |
| 上臂:54 | 绳索 | 单手绳索弯举 | 绳索弯举 | 绳索弯举 | `479ef6f0-5274-4da7-b5ad-67528ff3c8fd` | 中文名相同 | 去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4） |
| 上臂:57 | 固定器械 | 器械弯举 | 器械弯举 | 器械弯举 | `e68f6d51-fe02-4175-b277-dec0c1521f36` | 中文名相同 |  |
| 上臂:61 | 固定器械 | 器械臂屈伸 | 器械臂屈伸 | 器械臂屈伸 | `6c671e43-497f-4863-8d78-b592f3b5e7c6` | 中文名相同 |  |
| 上臂:79 | 无 | 钻石俯卧撑 | 钻石俯卧撑 | 钻石俯卧撑 | `de22963a-5d42-4999-860e-377f64359432` | 中文名相同 |  |
| 小腿:12 | 固定器械 | 站姿器械提踵 | 站姿器械提踵 | 站姿提踵 | `7ce443b6-eb84-4f65-b05f-461c1cc8bcc0` | 英文名相同 |  |
| 小腿:13 | 固定器械 | 腿举机提踵 | 腿举提踵 | 腿举提踵 | `0d79f259-3b28-4258-8a08-cffec062a710` | 中文名相同 |  |
| 核心:6 | 无 | 鸟狗式 | 鸟狗式 | 鸟狗式 | `6349365e-e901-4280-a1b7-65734986f47d` | 中文名相同 |  |
| 肩:6 | 哑铃 | 阿诺德推举 | 阿诺德推举 | 阿诺德推举 | `f24cb758-9c0d-42d4-ad9e-6025c527dd13` | 中文名相同 |  |
| 肩:8 | 哑铃 | 侧平举 | 哑铃侧平举 | 哑铃侧平举 | `63375f5b-2d81-471c-bea4-fc3d207e96cb` | 中文名相同 |  |
| 肩:11 | 哑铃 | 前平举 | 哑铃前平举 | 哑铃前平举 | `9c35594c-bbcc-4656-bdcb-376814c90e96` | 中文名相同 |  |
| 肩:12 | 哑铃 | 俯身飞鸟 | 哑铃后束飞鸟 | 哑铃后束飞鸟 | `3f93459a-d06e-465c-85db-2137da759440` | 中文名相同 |  |
| 肩:17 | 哑铃 | 哑铃耸肩 | 哑铃耸肩 | 哑铃耸肩 | `72a945ec-3a7f-424b-9a05-1616ef7dce91` | 中文名相同 |  |
| 肩:20 | 哑铃 | 哑铃后束飞鸟 | 哑铃后束飞鸟 | 哑铃后束飞鸟 | `3f93459a-d06e-465c-85db-2137da759440` | 中文名相同 |  |
| 肩:22 | 固定器械 | 器械侧平举 | 器械侧平举 | 器械侧平举 | `dc87b735-016c-410b-915c-e3521fea4be7` | 中文名相同 |  |
| 肩:26 | 固定器械 | 站姿器械侧平举 | 站姿器械侧平举 | 器械侧平举 | `dc87b735-016c-410b-915c-e3521fea4be7` | wger UUID 相同 |  |
| 肩:37 | 杠铃 | 杠铃耸肩 | 杠铃耸肩 | 杠铃耸肩 | `270e108d-3cd2-45a9-807b-c357317eb15c` | 中文名相同 |  |
| 肩:39 | 杠铃 | 杠铃上斜推举 | 杠铃肩上推举 | 杠铃肩上推举 | `8b0a0371-c0a9-42a7-aab7-68d520542fb2` | 中文名相同 |  |
| 肩:43 | 史密斯机 | 史密斯耸肩 | 史密斯耸肩 | 史密斯耸肩 | `6199b3c7-3ccb-47fa-89bb-ef7fef12c0e3` | 中文名相同 |  |
| 肩:51 | 绳索 | 俯身绳索飞鸟 | 俯身绳索飞鸟 | 绳索后束飞鸟 | `5d244235-cd56-472a-876e-6e530a899ef2` | 英文名相同 |  |
| 肩:52 | 绳索 | 绳索胸前平举 | 绳索前平举 | 绳索前平举 | `be9dfe16-9fc3-463d-a9cd-7aade27ef571` | 中文名相同 |  |
| 肩:53 | 绳索 | 面拉 | 面拉 | 绳索面拉 | `d7a418d4-d0cb-4f85-8a7c-1e9d97152cbd` | 英文名相同 |  |
| 肩:54 | 绳索 | 绳索侧平举 | 绳索侧平举 | 绳索侧平举 | `81942f3d-d92c-431c-b9d0-0da12918d1e4` | 中文名相同 |  |
| 肩:55 | 绳索 | 绳索侧平举（单边） | 绳索侧平举 | 绳索侧平举 | `81942f3d-d92c-431c-b9d0-0da12918d1e4` | 中文名相同 |  |
| 肩:56 | 绳索 | 绳索交叉后束飞鸟 | 绳索交叉后束飞鸟 | 绳索后束飞鸟 | `5d244235-cd56-472a-876e-6e530a899ef2` | 英文名相同 |  |
| 肩:74 | 无 | V - 俯卧撑 | V字俯卧撑 | 折刀俯卧撑 | `3b96a05b-9705-48da-b43e-6e098234bb35` | wger UUID 相同 |  |
| 肩:75 | 无 | V - 俯卧撑 - 负重 | V字俯卧撑(负重) | 折刀俯卧撑 | `3b96a05b-9705-48da-b43e-6e098234bb35` | wger UUID 相同 |  |
| 肩:84 | 无 | 派克俯卧撑（辅） | 派克俯卧撑(辅助) | 折刀俯卧撑 | `3b96a05b-9705-48da-b43e-6e098234bb35` | wger UUID 相同 |  |
| 肩:87 | 地雷杆 | 地雷杆单推举 | 地雷杆单推举 | 地雷管推举 | `91c47c8b-6290-4885-8921-df9aa7958c00` | wger UUID 相同 |  |
| 背:3 | 绳索 | 宽距下拉 | 宽握高位下拉 | 宽握高位下拉 | `55b9d286-c4cc-4a29-97ad-58cb13c2bb7e` | 中文名相同 |  |
| 背:4 | 绳索 | 绳索直臂下压 | 绳索直臂下拉 | 绳索直臂下拉 | `a45123c6-34c2-43cf-b6bf-914a8f40995a` | 中文名相同 |  |
| 背:5 | 绳索 | 拉杆坐姿划船 | 坐姿绳索划船 | 坐姿绳索划船 | `0ecfec6f-5d0f-4e8a-8d37-f6203a8923b8` | 中文名相同 |  |
| 背:7 | 绳索 | 绳索坐姿划船 | 坐姿绳索划船 | 坐姿绳索划船 | `0ecfec6f-5d0f-4e8a-8d37-f6203a8923b8` | 中文名相同 |  |
| 背:9 | 绳索 | 坐姿单手划船 | 坐姿绳索划船 | 坐姿绳索划船 | `0ecfec6f-5d0f-4e8a-8d37-f6203a8923b8` | 中文名相同 | 去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4） |
| 背:11 | 绳索 | 坐姿绳索双边下 | 宽握高位下拉 | 宽握高位下拉 | `55b9d286-c4cc-4a29-97ad-58cb13c2bb7e` | 中文名相同 |  |
| 背:13 | 绳索 | 窄距下拉 | 窄握高位下拉 | 窄握高位下拉 | `63fbb8e5-6ebc-4def-8844-3e65e097213b` | 中文名相同 |  |
| 背:16 | 绳索 | 铁杆直臂下压 | 绳索直臂下拉 | 绳索直臂下拉 | `a45123c6-34c2-43cf-b6bf-914a8f40995a` | 中文名相同 |  |
| 背:19 | 绳索 | 竖直坐姿绳索划 | 坐姿绳索划船 | 坐姿绳索划船 | `0ecfec6f-5d0f-4e8a-8d37-f6203a8923b8` | 中文名相同 |  |
| 背:23 | 杠铃 | 杠铃划船 | 杠铃俯身划船 | 杠铃俯身划船 | `4af6dbd9-8991-484b-9810-68f117c21edf` | 中文名相同 |  |
| 背:51 | 固定器械 | 坐姿器械背屈伸 | 坐姿器械背屈伸 | 器械下背伸展 | `50a8f1f6-6772-4319-be9d-3bad1374dadf` | wger UUID 相同 |  |
| 背:59 | 哑铃 | 俯身哑铃划船 | 哑铃俯身划船 | 哑铃俯身划船 | `94a5c406-7bcd-47f3-9687-bdf92a763932` | 中文名相同 |  |
| 背:65 | 单杠 | 引体向上 | 引体向上 | 引体向上 | `8e420408-0682-4ab6-89f5-2681e54c7ce0` | 中文名相同 |  |
| 背:68 | 单杠 | 反手引体向上 | 反手引体向上 | 反手引体向上 | `87e6abc5-a701-442a-b4fb-bb2a7598a754` | 中文名相同 |  |
| 背:69 | 无 | 山羊挺身 | 山羊挺身 | 山羊挺身 | `37f6bd56-815a-4975-99af-05e749fae4b2` | 中文名相同 |  |
| 背:70 | 无 | 平板手肘撑 | 平板手肘撑 | 平板支撑 | `c9e57bbe-e839-44c6-861d-1c8dd2845e36` | 英文名相同 |  |
| 背:71 | 单杠 | 弹跳引体 | 弹跳引体 | 引体向上 | `8e420408-0682-4ab6-89f5-2681e54c7ce0` | 英文名相同 | 近似映射：来源表映射到通用引体向上条目，弹跳变式不单列 |
| 背:72 | 单杠 | 引体上拉 | 引体上拉 | 引体向上 | `8e420408-0682-4ab6-89f5-2681e54c7ce0` | 英文名相同 | 近似映射：来源表映射到通用引体向上条目，变式不单列 |
| 背:88 | 固定器械 | 罗马椅背部伸展 | 山羊挺身 | 山羊挺身 | `37f6bd56-815a-4975-99af-05e749fae4b2` | 中文名相同 |  |
| 胸:3 | 杠铃 | 杠铃卧推 | 杠铃平板卧推 | 杠铃平板卧推 | `3717d144-7815-4a97-9a56-956fb889c996` | 中文名相同 |  |
| 胸:5 | 杠铃 | 下斜杠铃卧推 | 杠铃下斜卧推 | 杠铃下斜卧推 | `bcd801f0-9a38-4615-a91c-900153c8c234` | 中文名相同 |  |
| 胸:8 | 杠铃 | 上斜杠铃卧推 | 杠铃上斜卧推 | 杠铃上斜卧推 | `275fb49f-975c-4d6e-9d63-2c86ed740f40` | 中文名相同 |  |
| 胸:11 | 哑铃 | 哑铃卧推 | 哑铃平板卧推 | 哑铃平板卧推 | `28321cf3-70e6-48a4-ade1-d11382180cb3` | 中文名相同 |  |
| 胸:12 | 哑铃 | 上斜哑铃卧推 | 哑铃上斜卧推 | 哑铃上斜卧推 | `57e17672-52b9-43cf-8d0d-4b3f06a0c0d0` | 中文名相同 |  |
| 胸:14 | 哑铃 | 平板哑铃飞鸟 | 哑铃飞鸟 | 哑铃飞鸟 | `95d226ad-3bf7-4cd6-aa64-2f26b526d8b6` | 中文名相同 |  |
| 胸:16 | 哑铃 | 上斜哑铃飞鸟 | 哑铃上斜飞鸟 | 哑铃上斜飞鸟 | `55ff32e6-24ab-4303-9b50-176d60d48796` | 中文名相同 |  |
| 胸:18 | 哑铃 | 地板哑铃卧推 | 地板哑铃卧推 | 哑铃地板卧推 | `e4966cb8-9089-4595-9c78-99a27821e6ff` | 英文名相同 |  |
| 胸:20 | 哑铃 | 平板哑铃卧推 | 哑铃平板卧推 | 哑铃平板卧推 | `28321cf3-70e6-48a4-ade1-d11382180cb3` | 中文名相同 |  |
| 胸:22 | 哑铃 | 哑铃飞鸟 | 哑铃飞鸟 | 哑铃飞鸟 | `95d226ad-3bf7-4cd6-aa64-2f26b526d8b6` | 中文名相同 |  |
| 胸:25 | 哑铃 | 地板反手哑铃卧推 | 地板反手哑铃卧推 | 哑铃地板卧推 | `e4966cb8-9089-4595-9c78-99a27821e6ff` | 英文名相同 |  |
| 胸:28 | 固定器械 | 器械推胸 | 器械推胸 | 器械推胸 | `5c414175-fe72-455a-ba8f-a0575cf792bd` | 中文名相同 |  |
| 胸:29 | 固定器械 | 双杠臂屈伸（辅） | 助力双杠臂屈伸 | 助力双杠臂屈伸 | `3dd0db1c-450a-46d1-ad46-d7854bdc26ed` | 中文名相同 |  |
| 胸:30 | 固定器械 | 站姿器械夹胸 | 站姿器械夹胸 | 蝴蝶机夹胸 | `99449eae-0eae-44ab-a57f-fc094bbdda13` | 英文名相同 |  |
| 胸:32 | 固定器械 | 蝴蝶机飞鸟 - V2 | 蝴蝶机飞鸟V2 | 蝴蝶机夹胸 | `99449eae-0eae-44ab-a57f-fc094bbdda13` | 英文名相同 |  |
| 胸:33 | 固定器械 | 蝴蝶机夹胸 V2 | 蝴蝶机夹胸V2 | 蝴蝶机夹胸 | `99449eae-0eae-44ab-a57f-fc094bbdda13` | 英文名相同 |  |
| 胸:34 | 固定器械 | 器械坐姿夹胸 | 器械坐姿夹胸 | 蝴蝶机夹胸 | `99449eae-0eae-44ab-a57f-fc094bbdda13` | 英文名相同 |  |
| 胸:39 | 固定器械 | 上斜悍马机飞鸟 | 上斜悍马机飞鸟 | 蝴蝶机夹胸 | `99449eae-0eae-44ab-a57f-fc094bbdda13` | 英文名相同 | 近似映射：来源表映射到通用蝴蝶机夹胸条目，上斜悍马变式不单列 |
| 胸:48 | 绳索 | 绳索十字夹胸 | 绳索十字夹胸 | 绳索十字夹胸 | `b16e3e5d-8401-4d2b-919c-15b536f9ec5e` | 中文名相同 |  |
| 胸:49 | 绳索 | 绳索夹胸 | 绳索夹胸 | 绳索十字夹胸 | `b16e3e5d-8401-4d2b-919c-15b536f9ec5e` | 英文名相同 |  |
| 胸:62 | 无 | 双杠臂屈伸 | 双杠臂屈伸 | 双杠臂屈伸 | `09dd3e3c-e53a-4e2c-a2e3-645d334f53e2` | 中文名相同 |  |
| 胸:63 | 无 | 俯卧撑 | 俯卧撑 | 俯卧撑 | `f5b84269-18af-4464-a61f-b767cbcd81dc` | 中文名相同 |  |
| 胸:73 | 无 | 派克俯卧撑 | 派克俯卧撑 | 折刀俯卧撑 | `3b96a05b-9705-48da-b43e-6e098234bb35` | wger UUID 相同 |  |
| 胸:77 | 无 | 单手俯卧撑 | 俯卧撑 | 俯卧撑 | `f5b84269-18af-4464-a61f-b767cbcd81dc` | 中文名相同 | 去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4） |
| 腹:8 | 无 | 死虫 | 死虫式 | 死虫式 | `816d8bff-73c0-436c-8479-e0145f2324fc` | 中文名相同 |  |
| 腹:9 | 无 | 俄罗斯转体 | 俄罗斯转体 | 俄罗斯转体 | `10510fb5-6ebd-4ddc-b03e-423b15deceea` | 中文名相同 |  |
| 腹:13 | 无 | 仰卧抬腿 | 仰卧抬腿 | 仰卧抬腿 | `c2078aac-e4e2-4103-a845-6252a3eb795e` | 中文名相同 |  |
| 腹:14 | 无 | 抬腿 | 仰卧抬腿 | 仰卧抬腿 | `c2078aac-e4e2-4103-a845-6252a3eb795e` | 中文名相同 |  |
| 腹:20 | 无 | 保护式卷腹 | 保护式卷腹 | 卷腹 | `b186f1f8-4957-44dc-bf30-d0b00064ce6f` | 英文名相同 |  |
| 腹:21 | 无 | 平躺抬腿 | 仰卧抬腿 | 仰卧抬腿 | `c2078aac-e4e2-4103-a845-6252a3eb795e` | 中文名相同 |  |
| 腹:22 | 无 | 腹肌轮收 | 健腹轮 | 健腹轮 | `203a6fee-7436-4313-858f-c1e364136793` | 中文名相同 |  |
| 腹:24 | 无 | 卷腹 | 卷腹 | 卷腹 | `b186f1f8-4957-44dc-bf30-d0b00064ce6f` | 中文名相同 |  |
| 腹:25 | 无 | 平板支撑 | 平板支撑 | 平板支撑 | `c9e57bbe-e839-44c6-861d-1c8dd2845e36` | 中文名相同 |  |
| 腹:26 | 无 | 器械抬腿 | 器械抬腿 | 仰卧抬腿 | `c2078aac-e4e2-4103-a845-6252a3eb795e` | wger UUID 相同 |  |
| 腹:40 | 固定器械 | 器械卷腹 | 器械卷腹 | 器械卷腹 | `401989e0-64c3-459d-bc47-2c171ab4f41d` | 中文名相同 |  |
| 腹:43 | 固定器械 | 坐姿器械卷腹 | 坐姿器械卷腹 | 器械卷腹 | `401989e0-64c3-459d-bc47-2c171ab4f41d` | wger UUID 相同 |  |
| 腹:47 | 绳索 | 绳索水平帕洛夫 | 绳索水平帕洛夫 | 帕洛夫推压 | `e56f2970-e4c9-45eb-8e8c-52abb590e7a6` | 英文名相同 |  |
| 腿:3 | 杠铃 | 深蹲 | 杠铃深蹲 | 杠铃深蹲 | `a2f5b6ef-b780-49c0-8d96-fdaff23e27ce` | 中文名相同 |  |
| 腿:6 | 杠铃 | 前蹲 | 杠铃前蹲 | 杠铃前蹲 | `d677de4c-5bd9-412a-91f1-857116a666a2` | 中文名相同 |  |
| 腿:7 | 杠铃 | 硬拉 | 杠铃硬拉 | 杠铃硬拉 | `ee8e8db4-2d82-49e1-ab7f-891e9a354934` | 中文名相同 |  |
| 腿:8 | 杠铃 | 相扑硬拉 | 相扑硬拉 | 相扑硬拉 | `0c2d9b74-3d1e-481f-a7bf-3b3532f7d6b0` | 中文名相同 |  |
| 腿:9 | 杠铃 | 杠铃罗马尼亚硬拉 | 杠铃罗马尼亚硬拉 | 罗马尼亚硬拉 | `2e7ffff9-e603-4b28-98c8-31d1a6ce8cd9` | 英文名相同 |  |
| 腿:12 | 杠铃 | 杠铃直腿硬拉 | 直腿硬拉 | 直腿硬拉 | `22c59ede-970b-43e1-bb51-ac1c2be0b0e0` | 中文名相同 |  |
| 腿:16 | 杠铃 | 杠铃火箭推 | 杠铃火箭推 | 杠铃推进器 | `51420ded-5c17-4ce0-b005-89f1b67b7c65` | wger UUID 相同 |  |
| 腿:23 | 哑铃 | 罗马尼亚硬拉 | 罗马尼亚硬拉 | 罗马尼亚硬拉 | `2e7ffff9-e603-4b28-98c8-31d1a6ce8cd9` | 中文名相同 |  |
| 腿:25 | 哑铃 | 哑铃酒杯深蹲 | 哑铃酒杯深蹲 | 哑铃高脚杯深蹲 | `b7c6a444-90ea-4f5b-9fea-748311606eaa` | wger UUID 相同 |  |
| 腿:31 | 哑铃 | 哑铃保加利亚蹲 | 哑铃保加利亚蹲 | 哑铃保加利亚分腿蹲 | `60d2c34b-43a1-48a3-b43b-160e4c0157f2` | wger UUID 相同 |  |
| 腿:34 | 哑铃 | 哑铃行走箭步蹲 | 哑铃行走箭步蹲 | 哑铃行走弓步 | `dcc6e237-a8bb-4eca-bbc5-7fb852636f6a` | wger UUID 相同 |  |
| 腿:37 | 固定器械 | 腿弯举 | 腿弯举 | 腿弯举 | `48836f44-efcd-4471-a456-5f024936025a` | 中文名相同 |  |
| 腿:38 | 固定器械 | 坐姿腿弯举 | 坐姿腿弯举 | 坐姿腿弯举 | `440a5184-de58-4a86-a7ba-76ddeafaa855` | 中文名相同 |  |
| 腿:39 | 固定器械 | 单边腿弯举 (器械) | 站姿腿弯举 | 站姿腿弯举 | `49189e88-40b6-4c0d-a784-0cc3abbb8e75` | 中文名相同 |  |
| 腿:41 | 固定器械 | 器械倒蹬 | 器械倒蹬 | 腿举 | `66a42396-c207-44da-bc75-758a89d32404` | 英文名相同 |  |
| 腿:44 | 固定器械 | 坐姿髋内收 | 坐姿髋内收 | 坐姿髋内收 | `53906cd1-61f1-4d56-ac60-e4fcc5824861` | 中文名相同 |  |
| 腿:46 | 固定器械 | 器械单腿屈伸 | 腿屈伸 | 腿屈伸 | `62170477-90ec-463c-907e-9e523abc0a15` | 中文名相同 |  |
| 腿:47 | 史密斯机 | 史密斯机深蹲 | 史密斯机深蹲 | 史密斯深蹲 | `f3ef220b-a070-449c-a463-876d30cd9b14` | 英文名相同 |  |
| 腿:48 | 史密斯机 | 史密斯机箭步蹲 | 史密斯机箭步蹲 | 史密斯分腿蹲 | `b382dcb2-60a8-412d-b0ee-6afe9c9f36d7` | wger UUID 相同 |  |
| 腿:59 | 无 | 箭步蹲 | 箭步蹲 | 徒手弓步 | `3284fd27-5402-4821-9c32-29066d4e2667` | wger UUID 相同 |  |
| 腿:60 | 无 | 箭步踢腿 | 箭步踢腿 | 徒手弓步 | `3284fd27-5402-4821-9c32-29066d4e2667` | wger UUID 相同 |  |
| 腿:61 | 无 | 手枪深蹲 | 手枪深蹲 | 手枪深蹲 | `fe04cf35-1af5-4b51-89d4-c38d7eaa0db1` | 中文名相同 |  |
| 腿:62 | 无 | 反向箭步蹲 | 反向箭步蹲 | 徒手反向弓步 | `616f9026-1a1d-4ed8-b068-cfbb81b6a000` | wger UUID 相同 |  |
| 腿:64 | 无 | 相扑深蹲 | 相扑深蹲 | 徒手相扑深蹲 | `0a5a7661-1e24-4c15-bb2b-503672141307` | wger UUID 相同 |  |
| 腿:84 | 其他 | 北欧腿弯举 | 北欧腿弯举 | 北欧腿弯举 | `9b0f7101-b78a-4c47-b680-fbef15469a8a` | 中文名相同 |  |
| 腿:85 | 其他 | 臀桥 | 臀桥 | 徒手臀桥 | `ceb0c2d0-06ac-4a49-89e7-8d7b1c1e5672` | wger UUID 相同 |  |
| 臀:4 | 固定器械 | 器械后踢 | 器械后踢 | 器械臀屈伸 | `66ed6788-a1d8-49a2-af4d-397107fbf5fb` | wger UUID 相同 |  |
| 臀:6 | 固定器械 | 器械驴踢 | 器械驴踢 | 器械臀屈伸 | `66ed6788-a1d8-49a2-af4d-397107fbf5fb` | wger UUID 相同 |  |
| 臀:7 | 固定器械 | 器械倒蹬 | 器械倒蹬 | 腿举 | `66a42396-c207-44da-bc75-758a89d32404` | 英文名相同 |  |
| 臀:11 | 杠铃 | 早安 | 杠铃早安式 | 杠铃早安式 | `5abe2fee-6b82-4fce-9ff0-4f5fd2d3d01c` | 中文名相同 |  |
| 臀:13 | 杠铃 | 杠铃臀冲 | 杠铃臀冲 | 杠铃臀冲 | `19a289c0-33af-4055-bb34-3570c2975d3d` | 中文名相同 |  |
| 臀:14 | 杠铃 | 地雷杆罗马尼亚硬拉 | 地雷杆罗马尼亚硬拉 | 罗马尼亚硬拉 | `2e7ffff9-e603-4b28-98c8-31d1a6ce8cd9` | 英文名相同 |  |
| 臀:18 | 杠铃 | 杠铃单腿硬拉 | 杠铃硬拉 | 杠铃硬拉 | `ee8e8db4-2d82-49e1-ab7f-891e9a354934` | 中文名相同 | 去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4） |
| 臀:26 | 哑铃 | 单腿哑铃硬拉 | 哑铃硬拉 | 哑铃硬拉 | `b199baca-7353-4dee-bbcf-620f96dba5b4` | 中文名相同 | 去掉单侧字样后与现有双侧条目同名，单侧变式不再单独入库（Q4） |
| 臀:53 | 绳索 | 绳索站姿臀冲 | 绳索站姿臀冲 | 龙门架臀屈伸 | `19a9f67b-60f5-4367-9134-b805f3e73956` | wger UUID 相同 |  |
| 臀:69 | 壶铃 | 壶铃甩 | 壶铃摆荡 | 壶铃摆荡 | `d813ef7c-b10a-4c5c-ba55-6b9518e7ff4c` | 中文名相同 |  |

## 附录 C：校准差异（已在库行：按规则推出的部位/器械与现有条目不一致）

| 文件:行 | 现有中文名 | 项目 | 本表推出 | 现有条目 | 处理 |
|---|---|---|---|---|---|
| 上臂:10 | 哑铃过头臂屈伸 | 次要部位 | （空） | 肩 | 只记录，不改现有条目 |
| 上臂:61 | 器械臂屈伸 | 次要部位 | 胸、肩 | （空） | 只记录，不改现有条目 |
| 上臂:79 | 钻石俯卧撑 | 次要部位 | 胸、肩 | 胸 | 只记录，不改现有条目 |
| 核心:6 | 鸟狗式 | 次要部位 | 肩、臀 | 背、臀 | 只记录，不改现有条目 |
| 肩:12 | 哑铃后束飞鸟 | 次要部位 | （空） | 背 | 只记录，不改现有条目 |
| 肩:17 | 哑铃耸肩 | 次要部位 | （空） | 肩 | 只记录，不改现有条目 |
| 肩:20 | 哑铃后束飞鸟 | 次要部位 | （空） | 背 | 只记录，不改现有条目 |
| 肩:37 | 杠铃耸肩 | 次要部位 | （空） | 肩 | 只记录，不改现有条目 |
| 肩:51 | 绳索后束飞鸟 | 次要部位 | （空） | 背 | 只记录，不改现有条目 |
| 肩:54 | 绳索侧平举 | 次要部位 | 臂 | （空） | 只记录，不改现有条目 |
| 肩:56 | 绳索后束飞鸟 | 次要部位 | （空） | 背 | 只记录，不改现有条目 |
| 肩:74 | 折刀俯卧撑 | 次要部位 | 胸、臂 | 臂 | 只记录，不改现有条目 |
| 肩:75 | 折刀俯卧撑 | 次要部位 | 胸、臂 | 臂 | 只记录，不改现有条目 |
| 肩:84 | 折刀俯卧撑 | 次要部位 | 胸、臂 | 臂 | 只记录，不改现有条目 |
| 肩:87 | 地雷管推举 | 次要部位 | 胸、臂 | 胸、核心 | 只记录，不改现有条目 |
| 背:3 | 宽握高位下拉 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:5 | 坐姿绳索划船 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:7 | 坐姿绳索划船 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:11 | 宽握高位下拉 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:13 | 窄握高位下拉 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:19 | 坐姿绳索划船 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:23 | 杠铃俯身划船 | 次要部位 | 肩、臂 | 臂、核心 | 只记录，不改现有条目 |
| 背:51 | 器械下背伸展 | 次要部位 | 大腿、臀 | 臀 | 只记录，不改现有条目 |
| 背:59 | 哑铃俯身划船 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 背:65 | 引体向上 | 器械 | 单杠 | 徒手 | 只记录，不改现有条目 |
| 背:68 | 反手引体向上 | 器械 | 单杠 | 徒手 | 只记录，不改现有条目 |
| 背:69 | 山羊挺身 | 器械 | 徒手 | 固定器械 | 只记录，不改现有条目 |
| 背:69 | 山羊挺身 | 次要部位 | 大腿、臀 | 臀 | 只记录，不改现有条目 |
| 背:70 | 平板支撑 | 次要部位 | 背 | （空） | 只记录，不改现有条目 |
| 背:71 | 引体向上 | 器械 | 单杠 | 徒手 | 只记录，不改现有条目 |
| 背:72 | 引体向上 | 器械 | 单杠 | 徒手 | 只记录，不改现有条目 |
| 背:88 | 山羊挺身 | 次要部位 | 大腿、臀 | 臀 | 只记录，不改现有条目 |
| 胸:29 | 助力双杠臂屈伸 | 主部位 | 胸 | 臂 | 只记录，不改现有条目 |
| 胸:29 | 助力双杠臂屈伸 | 次要部位 | 肩、臂 | 胸 | 只记录，不改现有条目 |
| 胸:63 | 俯卧撑 | 次要部位 | 肩、臂 | 肩、臂、核心 | 只记录，不改现有条目 |
| 胸:73 | 折刀俯卧撑 | 主部位 | 胸 | 肩 | 只记录，不改现有条目 |
| 胸:73 | 折刀俯卧撑 | 次要部位 | 肩、臂 | 臂 | 只记录，不改现有条目 |
| 胸:77 | 俯卧撑 | 次要部位 | 肩、臂 | 肩、臂、核心 | 只记录，不改现有条目 |
| 腹:9 | 俄罗斯转体 | 器械 | 徒手 | 哑铃 | 只记录，不改现有条目 |
| 腹:9 | 俄罗斯转体 | 次要部位 | 背 | （空） | 只记录，不改现有条目 |
| 腹:22 | 健腹轮 | 器械 | 徒手 | 其他 | 只记录，不改现有条目 |
| 腹:22 | 健腹轮 | 次要部位 | 肩 | （空） | 只记录，不改现有条目 |
| 腹:47 | 帕洛夫推压 | 次要部位 | 胸、肩 | （空） | 只记录，不改现有条目 |
| 腿:3 | 杠铃深蹲 | 次要部位 | 背、臀 | 臀、核心 | 只记录，不改现有条目 |
| 腿:6 | 杠铃前蹲 | 次要部位 | 臀 | 臀、核心 | 只记录，不改现有条目 |
| 腿:8 | 相扑硬拉 | 主部位 | 大腿 | 背 | 只记录，不改现有条目 |
| 腿:8 | 相扑硬拉 | 次要部位 | 臀 | 大腿、臀 | 只记录，不改现有条目 |
| 腿:16 | 杠铃推进器 | 主部位 | 大腿 | 肩 | 只记录，不改现有条目 |
| 腿:16 | 杠铃推进器 | 次要部位 | 肩、臀 | 大腿、臂 | 只记录，不改现有条目 |
| 腿:23 | 罗马尼亚硬拉 | 器械 | 哑铃 | 杠铃 | 只记录，不改现有条目 |
| 腿:25 | 哑铃高脚杯深蹲 | 次要部位 | 臀 | 臀、核心 | 只记录，不改现有条目 |
| 腿:37 | 腿弯举 | 次要部位 | 小腿 | （空） | 只记录，不改现有条目 |
| 腿:41 | 腿举 | 次要部位 | 小腿、臀 | 臀 | 只记录，不改现有条目 |
| 腿:44 | 坐姿髋内收 | 次要部位 | 臀 | （空） | 只记录，不改现有条目 |
| 腿:47 | 史密斯深蹲 | 次要部位 | 背、臀 | 臀 | 只记录，不改现有条目 |
| 腿:61 | 手枪深蹲 | 次要部位 | 臀 | 臀、核心 | 只记录，不改现有条目 |
| 腿:84 | 北欧腿弯举 | 器械 | 其他 | 徒手 | 只记录，不改现有条目 |
| 腿:85 | 徒手臀桥 | 器械 | 其他 | 徒手 | 只记录，不改现有条目 |
| 腿:85 | 徒手臀桥 | 次要部位 | 大腿 | 大腿、核心 | 只记录，不改现有条目 |
| 臀:7 | 腿举 | 次要部位 | 小腿、臀 | 臀 | 只记录，不改现有条目 |
| 臀:13 | 杠铃臀冲 | 次要部位 | 大腿、小腿 | 大腿 | 只记录，不改现有条目 |
| 臀:18 | 杠铃硬拉 | 主部位 | 大腿 | 背 | 只记录，不改现有条目 |
| 臀:18 | 杠铃硬拉 | 次要部位 | 臀 | 大腿、臀 | 只记录，不改现有条目 |
| 臀:26 | 哑铃硬拉 | 主部位 | 大腿 | 背 | 只记录，不改现有条目 |
| 臀:26 | 哑铃硬拉 | 次要部位 | 臀 | 大腿、臀 | 只记录，不改现有条目 |
| 臀:69 | 壶铃摆荡 | 次要部位 | 大腿 | 大腿、核心 | 只记录，不改现有条目 |

## 附录 D：合并记录（规范化后器械与中文名都相同的行）

| 合并后中文名 | 器械 | 成员（文件:行，原名） | 备注 |
|---|---|---|---|
| 悍马机推胸 | 固定器械 | 胸:36（悍马机推胸）；胸:40（单边悍马机推胸） | 合并单侧与双侧两行，默认双侧（单侧由教练切换） |
| 下斜俯卧撑 | 徒手 | 胸:65（下斜俯卧撑）；胸:75（单手下斜俯卧撑） | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；合并行来源不同：free-exercise-db:Decline_Push-Up、free-exercise-db:Single-Arm_Push-Up |
| 扶墙拉伸 | 徒手 | 胸:80（拉伸 - 单手扶墙）；腿:93（拉伸 - 单手扶墙） |  |
| 站姿杠铃推举 | 杠铃 | 肩:33（站姿杠铃推举）；肩:38（杠铃过头顶臂） |  |
| 悍马机划船 | 悍马机 | 背:32（悍马机划船）；背:38（单手悍马机划船） | 合并单侧与双侧两行，默认双侧（单侧由教练切换） |
| 分动式高位划船 | 悍马机 | 背:36（分动式高位划）；背:42（分动式高位划船） |  |
| 分腿硬拉 | 哑铃 | 臀:28（分腿硬拉）；臀:29（单手分腿硬拉） | 合并单侧与双侧两行，默认双侧（单侧由教练切换） |
| 弹力带深蹲 | 弹力带 | 腿:76（弹力带深蹲）；腿:77（弹力带单腿深蹲） | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；合并行来源不同：free-exercise-db:Single-Leg_High_Box_Squat、free-exercise-db:Squats_-_With_Bands |
| 哑铃臀冲 | 哑铃 | 臀:24（哑铃臀冲）；臀:25（单腿哑铃臀冲） | 合并单侧与双侧两行，默认双侧（单侧由教练切换）；合并行来源不同：wger.de:7cc24acf-3fc9-4d14-a461-cd00d1d18f0e、wger.de:af77220c-098c-47c2-9f8c-92a651998903 |
| 弹力带坐姿腿外展 | 弹力带 | 腿:78（弹力带坐姿腿外展）；臀:57（弹力带 - 坐姿腿外展） |  |
| 弹力带螃蟹行走 | 弹力带 | 腿:79（弹力带螃式走）；臀:60（弹力带 - 螃蟹行走） |  |

## 附录 E：疑似重复（机械规则没有判重，请确认）

| 候选 | 候选来源 | 对照 | 依据 | 建议 |
|---|---|---|---|---|
| 悍马机侧平举 | 肩:47 | 现有「器械侧平举」（`dc87b735-016c-410b-915c-e3521fea4be7`） | 共用 wger 条目 UUID dc87b735-016c-410b-915c-e3521fea4be7，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 悍马机鹦鹉螺 | 背:44 | 现有「器械屈臂上拉」（`ad20ef5e-e360-4859-9110-668ee0c24721`） | 共用 wger 条目 UUID ad20ef5e-e360-4859-9110-668ee0c24721，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 负重俄罗斯转体 | 腹:10 | 现有「俄罗斯转体」（`10510fb5-6ebd-4ddc-b03e-423b15deceea`） | 共用 wger 条目 UUID 10510fb5-6ebd-4ddc-b03e-423b15deceea，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 史密斯机上踢 | 腿:52 | 现有「器械臀屈伸」（`66ed6788-a1d8-49a2-af4d-397107fbf5fb`） | 共用 wger 条目 UUID 66ed6788-a1d8-49a2-af4d-397107fbf5fb，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 弹力带箭步蹲 | 腿:67 | 现有「徒手弓步」（`3284fd27-5402-4821-9c32-29066d4e2667`） | 共用 wger 条目 UUID 3284fd27-5402-4821-9c32-29066d4e2667，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 弹力带站姿腿弯举 | 腿:69 | 现有「站姿腿弯举」（`49189e88-40b6-4c0d-a784-0cc3abbb8e75`） | 共用 wger 条目 UUID 49189e88-40b6-4c0d-a784-0cc3abbb8e75，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 保加利亚蹲(负重) | 腿:83 | 现有「哑铃保加利亚分腿蹲」（`60d2c34b-43a1-48a3-b43b-160e4c0157f2`） | 共用 wger 条目 UUID 60d2c34b-43a1-48a3-b43b-160e4c0157f2，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 史密斯后踢 | 臀:20 | 现有「器械臀屈伸」（`66ed6788-a1d8-49a2-af4d-397107fbf5fb`） | 共用 wger 条目 UUID 66ed6788-a1d8-49a2-af4d-397107fbf5fb，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 挂片后摆腿 | 臀:65 | 现有「器械臀屈伸」（`66ed6788-a1d8-49a2-af4d-397107fbf5fb`） | 共用 wger 条目 UUID 66ed6788-a1d8-49a2-af4d-397107fbf5fb，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 挂片站姿臀冲 | 臀:67 | 现有「器械臀伸」（`ab872d04-ca20-4341-b3c9-76763b25ef42`） | 共用 wger 条目 UUID ab872d04-ca20-4341-b3c9-76763b25ef42，来源表器械/变式不同 | 请确认是否按「已在库」处理 |
| 仰卧杠铃臂屈伸 | 上臂:28 | 现有「仰卧臂屈伸(碎颅者)」（`8a356e9a-0058-4f60-b8d7-89147c3c371f`） | 同一动作（Lying Triceps Press / Extensions） | 请确认是否按「已在库」处理 |
| 杠铃碎颅者 | 上臂:37 | 现有「仰卧臂屈伸(碎颅者)」（`8a356e9a-0058-4f60-b8d7-89147c3c371f`） | 同一动作（EZ-Bar Skullcrusher / Lying Triceps Extensions） | 请确认是否按「已在库」处理 |
| 窄距卧推(靠近) | 上臂:29 | 现有「窄距卧推」（`3db63138-a047-4a4d-b616-1a0b7dfca105`） | 同一动作的肘位变式（Close-Grip Barbell Bench Press） | 请确认是否按「已在库」处理 |
| 窄距卧推(散开) | 上臂:35 | 现有「窄距卧推」（`3db63138-a047-4a4d-b616-1a0b7dfca105`） | 同一动作的肘位变式（Close-Grip Barbell Bench Press） | 请确认是否按「已在库」处理 |
| 哑铃推举 | 肩:3 | 现有「哑铃肩上推举」（`87affa4b-395b-437c-9581-2bd20ea5aa7c`） | 同一动作（Dumbbell Shoulder Press / Shoulder Press, Dumbbells） | 请确认是否按「已在库」处理 |
| 站姿杠铃推举 | 肩:33 | 现有「杠铃肩上推举」（`8b0a0371-c0a9-42a7-aab7-68d520542fb2`） | 同一动作（Standing Military Press / Shoulder Press, Barbell） | 请确认是否按「已在库」处理 |
| 器械划船 | 背:50 | 现有「胸撑器械划船」（`fd595232-b9ad-4216-bba1-92298f993ea9`） | 同一动作（Leverage Iso Row / Leverage Machine Iso Row） | 请确认是否按「已在库」处理 |
| 器械绳索划船 | 背:52 | 现有「坐姿绳索划船」（`0ecfec6f-5d0f-4e8a-8d37-f6203a8923b8`） | 同一动作（Seated Cable Rows）但来源表器材写固定器械 | 请确认是否按「已在库」处理 |
| 哑铃划船 | 背:57 | 现有「单臂哑铃划船」（`d8ec22e5-8575-483f-bd66-5203fd4bfe84`） | 同一动作（One-Arm Dumbbell Row；第 2 步现有条目改名为「哑铃支撑划船」） | 请确认是否按「已在库」处理 |
| 哑铃划船(手撑) | 背:60 | 现有「单臂哑铃划船」（`d8ec22e5-8575-483f-bd66-5203fd4bfe84`） | 同一动作的手撑变式（One-Arm Dumbbell Row；第 2 步现有条目改名为「哑铃支撑划船」） | 请确认是否按「已在库」处理 |
| 滑轮器卷腹 | 腹:42 | 现有「龙门架卷腹」（`29175281-afaf-4ffd-85e8-cfc38493e304`） | 同一动作（Cable Crunch / Crunches With Cable），来源表器材写固定器械 | 请确认是否按「已在库」处理 |
| 绳索跪姿卷腹 | 腹:44 | 现有「龙门架卷腹」（`29175281-afaf-4ffd-85e8-cfc38493e304`） | 同一动作（Cable Crunch / Crunches With Cable） | 请确认是否按「已在库」处理 |
| 水平山羊挺身 | 臀:10 | 现有「山羊挺身」（`37f6bd56-815a-4975-99af-05e749fae4b2`） | 同一动作（Hyperextensions） | 请确认是否按「已在库」处理 |
| 哈克机深蹲 | 腿:35 | 现有「哈克深蹲」（`f462df26-3264-48c2-b5aa-2374d0670c24`） | 同一动作（Hack Squat），器械列与臀:3 互相矛盾（Q6） | 请确认是否按「已在库」处理 |
| 哈克机深蹲 | 臀:3 | 现有「哈克深蹲」（`f462df26-3264-48c2-b5aa-2374d0670c24`） | 同一动作（Hack Squat），器械列与腿:35 互相矛盾（Q6） | 请确认是否按「已在库」处理 |
| 哑铃罗马尼亚硬拉 | 臀:31 | 现有「罗马尼亚硬拉」（`2e7ffff9-e603-4b28-98c8-31d1a6ce8cd9`） | 单腿罗马尼亚硬拉，去「单腿」后与现有近似（Q4） | 请确认是否按「已在库」处理 |
| 臀桥 | 臀:40 | 现有「徒手臀桥」（`ceb0c2d0-06ac-4a49-89e7-8d7b1c1e5672`） | 单腿臀桥，去「单腿」后与现有「徒手臀桥」近似（Q4） | 请确认是否按「已在库」处理 |

