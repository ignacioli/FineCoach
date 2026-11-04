# Environment smoke 基线

本目录只接收负责人亲自录制并批准的 `fixed-geometry.png`；agent 禁止生成、修改或查看 PNG。首次缺基线必须失败，不能自动录制。负责人专用命令见 `android/README.md` 的 T003 段落。

fixture 只有 96×64 dp 固定色块与边框，无文字、图标或产品组件；字面颜色非 DS token，仅环境 smoke。固定 Robolectric API36、NATIVE graphics、`zh-rCN-w320dp-h480dp-notnight-mdpi`、fontScale=1；mdpi 下预期 96×64 pixels。录制和 verify 使用相同批准的 JDK、依赖与宿主环境。

负责人批准时登记文件 SHA-256、宿主/JDK、Robolectric/Roborazzi/Compose 版本与批准时间。差异图仅写入 `android/app/build/`，不放本目录。本基线不代表正式 DS 组件或 G5 验收。
