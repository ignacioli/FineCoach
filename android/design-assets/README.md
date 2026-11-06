# Material Symbols 接入与许可

13 项均已接入，状态见 `material-symbols-manifest.txt`；不使用 material-icons-* 依赖。Material Symbols by Google，采用 Apache License 2.0；完整许可见 `material-symbols-LICENSE.txt`，署名和修改说明见 `material-symbols-NOTICE.txt`。

来源为编排方 2026-11-06 在宿主下载的 Google `material-design-icons`，commit `10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7`。本轮未联网。原始 `SOURCE.txt`、`SHA256SUMS` 已分别保存为 `material-symbols-SOURCE.txt`、`material-symbols-SHA256SUMS`；每项 SVG、权重、输入 SHA-256、上游路径/commit、输出 drawable 和输出 SHA-256 见 `material-symbols-provenance.json`。输入 digest 已逐项实算并与宿主 SHA256SUMS 比对；原始 SVG 保存在 `material-symbols-svg/` 供复核。

转换方式：SVG `viewBox="0 -960 960 960"` → Android vector viewport `960×960`、intrinsic `24dp×24dp`（来自 SVG width/height=24）；`<group android:translateY="960">` 修正 Y 原点；pathData 原样保留。白色填充 `@android:color/white` 仅为占位，实际由调用方 Compose `tint` 使用生成设计 token 着色。转换属于修改，NOTICE 已记录；不改变 glyph path，不新增设计色。

复现（产品根，无 Gradle、无网络）：

```sh
node android/design-assets/convert-material-symbols.mjs /path/to/verified-host-assets
```

转换器先校验来源 commit、13 SVG 和 LICENSE 的固定输入 digest/受支持 SVG 结构，再生成 drawable、provenance 与许可副本。若结构变化或校验不一致则失败，不猜测转换。

组件保持 Painter 注入；debug catalog 用 `painterResource(R.drawable.ic_ms_<name>)` 提供真实 vector。`‹ › ✓` 继续用随包 Noto Sans SC，不转图标。图标默认装饰性；图标按钮由外层提供非空可访问名称。

当前 Android 没有应用内开源许可说明页面约定；本轮不新增产品页面。为使许可随 APK 分发，完整 LICENSE/NOTICE 同时打包在 `app/src/main/assets/licenses/material-symbols-{LICENSE,NOTICE}.txt`。FictionalDataPolicy 仅豁免这两份文件的精确 source/APK 路径与固定 SHA-256；篡改（即使添加 fictional-data 声明）、邻居文件和其他路径仍被拒绝。OFL 规则不变。将来建立许可页时可读取这些已打包文件。

本轮资源 XML/路径/digest 的静态核对不替代 Android 编译、资源加载、运行测试或负责人视觉验收。
