# S3 集中走查（T052 已完成 / PASS，2026-11-26）

**负责人已按 S3-D25「全部批准」完成本清单集中走查、三张核心屏及两张 P7 sheet 审阅；S3-D21 入口回归已修复。宿主已在 FineCoach_QPR2_API36_1 全新安装 seed v6 multi，独立复核 PASS；写入与批准哈希见 T051/T052，checkpoint 见 T053。下表保留为已完成的走查清单。**

| 要看哪页 | 找哪位学员 | 从哪进 |
|---|---|---|
| 训练趋势（核心屏）、估算 1RM、个人最佳 | 虚构趋势松鼠 | 学员 → 学员详情 → 训练趋势 |
| 身体数据、录入单位和长趋势 | 虚构趋势松鼠 | 学员 → 学员详情 → 身体数据 |
| 本节收获四类同时出现 | 虚构收获海星 | 学员 → 学员详情 → 训练历史 → 最新一节完成课 |
| 进步停滞及直达动作趋势 | 虚构停滞云雀 | 今日 → 需要留意 → 全部 → 该学员的停滞行 |
| 很久没来及预填新建安排 | 虚构久别鲸鱼 | 今日 → 需要留意 → 全部 → 该学员的久未到访行 |
| 课包预警及直达课包 | 虚构课包青蛙 | 今日 → 需要留意 → 全部 → 该学员的课包行 |
| 两课对比及不兼容说明 | 虚构趋势松鼠 | 学员 → 学员详情 → 训练历史 → 选择 |

以上均为新增且互不重名的虚构学员；原 S1/S2 学员、课包、历史、模板、预约完整保留。趋势专人有 24 节完成课，跨度超过三个月；身体数据四项各八个日期。收获专人恰好十节，最新历史课同时有新纪录、进步、第十节、连续四周。停滞专人有四节同动作历史；久未到访专人最后一课距 seed 基准九十天且无未来安排；课包专人余额预警。

只用专用虚构数据 AVD 的 `multi` seed v6。沿用 `.handoff/bin/s2-seed-walkthrough.sh` 的新安装、重复安装校验和留窗流程，由宿主执行，本轮未运行脚本、模拟器或手动截图。历史固定 UTC / `2026-11-09T00:00:00Z`，预约仍按首次安装设备日期偏移；实际 App 用墙上时钟，洞察会随日期、安排、训练而变化。测试同时核对 seed 时刻与 2026-11-25 的专人洞察；超过停滞窗口后该提示自然消失，不保证永久显示。

| 从哪进 | 点什么 | 期望看到什么 | 对应 design PNG（仓库根目录相对路径） |
|---|---|---|---|
| 虚构趋势松鼠 → 训练趋势（核心屏） | 动作、重量/次数/容量分段 | 跨月历史点、日期、上升趋势和个人最佳真实计算；无顶层三段 | `design/insights/screens/trends-s3.png` |
| 虚构趋势松鼠 → 训练趋势 → 清单内杠铃动作 | 估算 1RM（one-repetition maximum，单次最大重量） | 有估算序列、公式与推算值说明；估算不当个人最佳 | `design/insights/screens/E-c-trend-estimated-1rm.png` |
| 虚构趋势松鼠 → 训练趋势 → 清单外次数动作 | 动作选择 → 次数 | 有逐步上升的次数趋势，不出现估算 1RM 分段 | `design/insights/screens/trends-s3.png` |
| 今日（核心屏） | 需要留意、全部 · N | 预约后最多三行；完整列表按课包/很久没来/停滞分组，能找到三个提示专人 | `design/m1-b-hifi/screens/01-today-s3.png`；`design/insights/screens/E-a2-insights-list.png` |
| 完整列表 → 虚构课包青蛙 / 虚构久别鲸鱼 / 虚构停滞云雀 | 各自提示行 | 分别到课包、预填该学员的新建安排、对应动作趋势；点行不自动创建安排 | `design/insights/screens/E-a2-insights-list.png` |
| 今日/完整列表 → 任一提示专人 | 左滑后可见「暂不提醒」，再点撤销 | 四秒内撤销恢复；不撤销则隐藏并跨返回/重开保留；首次轻推只一次，关闭动画不播放 | `design/insights/screens/E-d-insights-swipe-snooze.png` |
| 虚构停滞云雀 → 学员详情（核心屏） | 需要留意、下一节课、训练趋势、身体数据 | 提示主文字不重复学员名；两个记录入口真正到达目的地；无安排时下一节课预填新建安排 | `design/m1-b-hifi/screens/26-student-detail-s3.png` |
| 虚构收获海星 → 训练历史 → 最新完成课 | 本节收获 | 同节同时有新纪录、比上次进步、第十节、连续四周；不写进教练备注 | `design/progress-milestones/screens/D-b-session-gains.png`；`design/progress-milestones/screens/D-b2-session-gains-states.png` |
| 虚构收获海星 → 开始训练 → 添加历史同一内置动作 | 确认超过历史主指标的新组，再编辑/删组/撤销 | 新纪录胶囊重算，确认反馈一次；不把已有第十节徽章错误延续到新课 | `design/progress-milestones/screens/D-a-record-row.png`；`design/progress-milestones/screens/D-a2-record-partial-states.png` |
| 新完成课 → 总结，再到同一课历史详情 | 本节收获 | 两入口一致；均空时整块不出现，不改原备注 | `design/progress-milestones/screens/D-b-session-gains.png`；`design/progress-milestones/screens/D-b2-session-gains-states.png` |
| 虚构趋势松鼠 → 训练历史 | 选择 → 两节胸部重点课；改选最早背部重点课与胸部课 | 同重点集合可比；不同集合有不兼容说明；不写历史 | `design/m1-b-hifi/screens/07-training-history.png`（批准基础屏，比较为 S3 新交互） |
| 虚构趋势松鼠 → 身体数据 | 体重、腰围、体脂率、自定义指标 | 四项均有八天历史与趋势，身体值变化；自定义单位保留 | `design/m1-b-hifi/screens/06-body-data.png` |
| 虚构趋势松鼠 → 身体数据 → 内置指标 | 切 kg/lb、cm/in；返回、换指标/学员、重开 | 教练全局显示偏好保留；内置输入保存为 kg/cm，百分比不换单位；切显示不重写测量 | `design/m1-b-hifi/screens/06-body-data.png` |
| 虚构趋势松鼠 → 身体数据 → 指标 | 同日再次保存；删除 → 取消/确认；自定义指标 → 保存 | 同日编辑一条，取消不删、确认后趋势重算；自定义值与单位原样保存 | `design/m1-b-hifi/screens/06-body-data.png` |

三张核心屏：训练趋势、今日 S3、学员详情 S3。设计/Android/差异材料沿用 [T033](T033.md)、[T044](T044.md)。S3-D21 已记录负责人认为三张对照页和模拟器视觉无问题，但入口回归要求复查；不据此代写基线批准。R4 修复后 JVM 真实导航证据与其他 gate 见 [T050](T050.md)、[T053](T053.md)，宿主重新安装、独立复验、负责人复查及 manifest/基线写入 PENDING。
