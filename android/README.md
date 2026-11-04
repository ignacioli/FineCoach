## Environment

核实日期：2026-11-03。范围：T001 / plan §2 第 1～2 步。本文是环境事实与版本申请，精确版本尚未获负责人逐项批准，T001 的批准条件尚未满足；不进入 T002。本轮只读取官方文档、release/API、repository XML 和 POM metadata，没有下载二进制依赖、创建 Gradle 工程、运行构建、安装 SDK、修改全局配置或 commit。

**路径与基线**

- canonical product root：`~/gitrepo/ignacioli/FineCoach/.claude/worktrees/android-s0`；branch：`feat/android-s0-infrastructure`；HEAD：`b3980c8d409d791997b80b9c0718a154131cc267`。`pwd -P`、`git branch --show-current`、`git rev-parse HEAD` 均退出 0。
- 开工 `git status --short`、`git diff --stat`、`git diff --cached --stat` 均为空、退出 0：tracked modifications 0、staged 0、untracked 0。计划写入白名单仅本 README；结束新增 untracked `android/README.md`，不 stage。
- P0-07 已在基线：`AGENTS.md:13` 的 Kotlin/Compose/Room/minSdk31 获批段落，`:60` 的 Android 隐私约束，`:84` 的 Android 测试例外，`:100` 的运行清单/逐次 commit 批准；`CLAUDE.md:19`、`:215`、`:239` 对应 Android 获批、隐私和 agent run-list 段落。
- 编排方已执行 bootstrap。本轮 `ig-worktree-gate` audit 退出 0：linked worktree、protected=no、missing links=(none)，`GATE: PASS`；primary 为 `~/gitrepo/ignacioli/FineCoach`。
- 批准规格从 canonical specs root `~/gitrepo/ignacioli/.worktree/specs-android-s0` 读取，目录 `FineCoach/007-android-port/s0-infrastructure/`，及上级 ADR-001；specs `git status --short` 为空。未修改规格，未在 specs 仓执行 bootstrap。产品 `specs` 链接值为 `../../../specs`，不以该链接作为本轮批准规格的绑定或写入入口。

**已装环境**

| 检查 | 实测结果 | 证据与限制 |
|---|---|---|
| 宿主架构 | arm64 | `uname -m` 退出 0 |
| 默认 Java | Oracle JDK `21.0.5+9-LTS-239`，x86_64 | `java -version`、`/usr/libexec/java_home -V` 退出 0；不是下表拟议的 Temurin |
| Android Studio JBR | OpenJDK `25.0.3+-15898627-b508.16` | `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java -version` 退出 0；未切换默认 Java |
| Node | `v26.8.2` | `node --version` 退出 0；不安装新运行时 |
| SDK | `~/Library/Android/sdk` | `ANDROID_HOME` 为该路径；`ANDROID_SDK_ROOT` 未设置 |
| platforms | `android-36` rev 2（API36、extension17）；`android-37.0` rev 2（API37.0、extension22、PreviewSdkInt=0） | 读取 `source.properties`；无 `android-36.1` |
| build-tools | `35.0.0`、`36.0.0` | 读取 `source.properties` |
| emulator | `37.2.12` | 读取 `emulator/source.properties`；未启动 emulator |
| system-images | `system-images;android-36;google_apis_playstore;arm64-v8a` rev 7 | `build.prop`：`BE2A.250530.026.D1`，`sdk_full=36.0`；不是 QPR2。API31、32、36.1 镜像均未安装 |
| cmdline-tools / sdkmanager | 目录存在但为空，SDK 树中未找到 sdkmanager | 首次含空 glob 的 `ls` 返回 1；随后用目录枚举和文件检索确认，不再尝试启动 |
| 既有 Gradle 缓存 | wrapper distributions 有 `8.14.3-all`、`9.2.0-bin`、`9.5.1-bin`、`9.7.1-bin`；caches 有对应版本 | 仅名称，不证明完整性；没有拟议 `9.7.0` distribution；`~/.m2/repository/org/robolectric` 不存在 |
| 网络 | Google Maven、Maven Central、Gradle 服务、Plugin Portal、GitHub、Google SDK repository XML 均有 HTTP 200 metadata 响应；拟议Gradle ZIP的HEAD重定向后也返回200 | 使用 Node 内建 fetch；未GET大型ZIP/JAR，不证明完整下载成功。未设置常见 HTTP(S)/ALL proxy 环境变量；未枚举或输出凭据 |
| 写权限 | worktree、`/private/tmp` 的 `test -w` 退出 0；`~/.gradle`、SDK 的 `test -w` 退出 1 | 当前 sandbox 仅允许指定 worktree 与临时目录写入；全局缓存/SDK 不可写。不尝试越权写入，也不声称完成缓存实际写入测试 |

建议 `targetSdk=36`：2026-08-31 起 Google Play 手机/平板新应用与更新要求 API36 或更高；本机已有 API36 platform/镜像，可提供起步环境。Play 要求只作为 D01 版本依据，不增加分发验收。建议 `compileSdk=37.0`，复用本机已装 stable platform rev 2；`minSdk=31` 保持 ADR 决定。[Play 要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)

`<cross-platform-transfer>` 的系统支持从 Android16 QPR2/API36.1 起；按官方 API/toolchain 支持表，所需最低编译平台取 **36.1**、最低 **AGP8.13.0**；若使用本建议的 compileSdk37.0，最低 **AGP9.1.1**。选定 AGP9.3.1 支持最高 API37。`compileSdk37.0` 不能替代 QPR2 runtime：API36.1 platform 本机缺失但本方案不必另装，**QPR2 镜像仍缺失**。XML 是否接受无 params 的全排除段、三段九域系统正向解析，仍由 T006 验证；本轮没有编译或系统解析证据。[Auto Backup](https://developer.android.com/identity/data/autobackup#configure-cross-platform-transfers)、[API/AGP 最低版本表](https://developer.android.com/build/releases/about-agp#api-level-support)、[minor API 配置](https://developer.android.com/build#android-sdk-settings)

**当前批准状态：已批准（负责人 2026-11-03）。** 以下版本表及其“待批准”描述保留为 T001 申请时的历史记录；负责人现已批准表内版本，并接受 AGP 传递依赖 UTP `1.0.0-beta10` 的 beta 例外。JDK 固定 Temurin `21.0.13+9`（arm64）；未修改表内版本值。

## 版本批准表（待负责人批准）

每行均为待批准候选，负责人结论统一为 **待批准**；带“待核实”的兼容项不可据此宣称已验证。scope 中 build 表示宿主工具，plugin/implementation/test/debug/androidTest 表示拟议引入边界。第三方按“非 Google Android/AndroidX 平台库”区分；Google 维护的 KSP 仍单列外部构建工具。

选择稳定发布、固定版本的组合，不机械叠加各组件最高版本：官方当前 Gradle 为9.8.2、AGP为9.5.0，但 Kotlin2.4.21 的完全支持表上限是 Gradle9.7.0 / AGP9.3.1，因此候选取这两个上限。AGP9.3.1 是已发布 stable，并非9.3系列最新 patch；9.3.2/9.3.3 的修复说明需负责人一并审阅。超出 Kotlin 完全支持范围的升级不在本表默许。AGP9 内建 Kotlin，拟按官方方法把 KGP 提升至2.4.21，**不同时应用 `org.jetbrains.kotlin.android`**。[Kotlin 兼容表](https://kotlinlang.org/docs/gradle-configure-project.html)、[AGP9.3 release notes](https://developer.android.com/build/releases/agp-9-3-0-release-notes)、[内建 Kotlin 升级方法](https://developer.android.com/build/releases/agp-9-0-0-release-notes#upgrade-to-a-higher-kgp-version)

| 精确坐标 / 工具 | 精确版本 | 用途 | scope | license | 官方来源 URL | 与其他行的兼容依据 | 第三方 |
|---|---|---|---|---|---|---|---|
| Eclipse Temurin JDK，macOS aarch64 | 21.0.13+9 | Gradle/JVM 宿主 | build | GPL-2.0 with Classpath Exception | [release](https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.13%2B9)、[license](https://adoptium.net/docs/faq) | [Gradle Java 表](https://docs.gradle.org/9.7.0/userguide/compatibility.html)：Java21 可运行；AGP≥17；Robolectric API36/37要求Java21 | 是，Adoptium |
| Gradle distribution `gradle-9.7.0-bin.zip` | 9.7.0 | Wrapper 构建器 | build | Apache-2.0 | [distribution/checksum](https://services.gradle.org/distributions/gradle-9.7.0-bin.zip.sha256) | [AGP9.3](https://developer.android.com/build/releases/agp-9-3-0-release-notes) 要求≥9.5.0；[KGP 表](https://kotlinlang.org/docs/gradle-configure-project.html)上限9.7.0 | 是，Gradle |
| `com.android.application` → `com.android.tools.build:gradle` | 9.3.1 | Android 构建/lint | plugin | Apache-2.0 | [AGP9.3](https://developer.android.com/build/releases/agp-9-3-0-release-notes) | [官方表](https://developer.android.com/build/releases/agp-9-3-0-release-notes)：API≤37、Build Tools36.0.0、JDK≥17；在KGP完全支持上限内 | 否，Google |
| `org.jetbrains.kotlin:kotlin-gradle-plugin`（AGP内建 Kotlin 升级；不应用 `org.jetbrains.kotlin.android`） | 2.4.21 | Kotlin 编译 | plugin | Apache-2.0 | [release](https://kotlinlang.org/docs/releases.html)、[内建升级](https://developer.android.com/build/releases/agp-9-0-0-release-notes#upgrade-to-a-higher-kgp-version) | [KGP表](https://kotlinlang.org/docs/gradle-configure-project.html)：Gradle7.6.3～9.7.0，AGP8.5.2～9.3.1 | 是，JetBrains |
| `org.jetbrains.kotlin:kotlin-stdlib` | 2.4.21 | Kotlin runtime | implementation | Apache-2.0 | [Kotlin 依赖对齐](https://kotlinlang.org/docs/gradle-configure-project.html#dependency-on-the-standard-library) | 与KGP同版；完整resolved graph待核实 | 是，JetBrains |
| `org.jetbrains.kotlin.plugin.compose` → `org.jetbrains.kotlin:compose-compiler-gradle-plugin` | 2.4.21 | Compose compiler | plugin | Apache-2.0 | [compiler setup](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler) | 官方要求与Kotlin同版本；不由Compose BOM管理 | 是，JetBrains |
| `androidx.compose:compose-bom` | 2026.09.00 | Compose版本约束 | implementation/test platform | Apache-2.0 | [官方POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.09.00/compose-bom-2026.09.00.pom) | 本轮POM核实下列版本；[BOM说明](https://developer.android.com/develop/ui/compose/bom) | 否，AndroidX |
| `androidx.compose.runtime:runtime` | 1.12.1 | 状态 runtime | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-runtime) | 由上述[BOM POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.09.00/compose-bom-2026.09.00.pom)约束 | 否，AndroidX |
| `androidx.compose.ui:ui` | 1.12.1 | Compose UI | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-ui) | 同BOM；与选定compiler端到端运行待T003 | 否，AndroidX |
| `androidx.compose.ui:ui-text` | 1.12.1 | 随包字体/排版 | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-ui) | 同BOM | 否，AndroidX |
| `androidx.compose.foundation:foundation` | 1.12.1 | 几何/布局fixture与基础交互 | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-foundation) | 同BOM | 否，AndroidX |
| `androidx.compose.material3:material3` | 1.4.0 | 后续已批准Material平台组件 | implementation，后续组件阶段 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-material3) | 同BOM；不为T002最小壳预先添加 | 否，AndroidX |
| `com.google.devtools.ksp` → `com.google.devtools.ksp:symbol-processing-gradle-plugin` | 2.3.13 | Room代码生成 | plugin，KSP2 | Apache-2.0 | [release](https://github.com/google/ksp/releases/tag/2.3.13)、[KSP2](https://github.com/google/ksp/blob/2.3.13/docs/ksp2.md) | KSP2不沿用KSP1版本前缀配对；与Kotlin2.4.21/AGP9.3.1/Room2.8.5的精确组合官方矩阵待核实 | 外部工具，Google维护 |
| `androidx.room:room-runtime` | 2.8.5 | 私有SQLite ORM | implementation，T007 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/room) | 官方要求Kotlin≥2.0、建议KSP2，minSdk23≤31；精确KSP组合待核实 | 否，AndroidX |
| `androidx.room:room-compiler` | 2.8.5 | DAO/schema生成 | ksp，T007 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/room) | 与runtime同版，KSP2；生成实跑待后续 | 否，AndroidX |
| `androidx.room:room-testing` | 2.8.5 | synthetic migration helper | test，T008 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/room) | 与runtime/compiler同版；Robolectric集成待后续 | 否，AndroidX |
| `androidx.navigation:navigation-compose` | 2.10.2 | 单Activity导航壳 | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/navigation) | [官方POM](https://dl.google.com/dl/android/maven2/androidx/navigation/navigation-compose/2.10.2/navigation-compose-2.10.2.pom)；与BOM合并后的精确图/AAR约束待核实 | 否，AndroidX |
| `androidx.activity:activity-compose` | 1.13.0 | Activity/Compose宿主 | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/activity) | [官方POM](https://dl.google.com/dl/android/maven2/androidx/activity/activity-compose/1.13.0/activity-compose-1.13.0.pom)；BOM合并图待核实 | 否，AndroidX |
| `org.robolectric:robolectric` | 4.17 | JVM Android/Compose测试 | test | MIT | [release](https://github.com/robolectric/robolectric/releases/tag/robolectric-4.17)、[setup](https://robolectric.org/getting-started/) | [SDK/provider源码](https://github.com/robolectric/robolectric/blob/robolectric-4.17/robolectric/src/main/java/org/robolectric/plugins/DefaultSdkProvider.java)：API31～37；API36/37需Java21；不是QPR2系统证明 | 是，Robolectric |
| `io.github.takahirom.roborazzi` → `io.github.takahirom.roborazzi:roborazzi-gradle-plugin` | 1.77.0 | 最小spike verify任务 | plugin，仅spike | Apache-2.0 | [release](https://github.com/takahirom/roborazzi/releases/tag/1.77.0) | [上游固定组合](https://github.com/takahirom/roborazzi/blob/1.77.0/gradle/libs.versions.toml)较旧；与本表精确组合待T003核实 | 是，非平台 |
| `io.github.takahirom.roborazzi:roborazzi` | 1.77.0 | 像素捕获/比较 | test，仅spike | Apache-2.0 | [上游](https://github.com/takahirom/roborazzi/tree/1.77.0)、[POM](https://repo.maven.apache.org/maven2/io/github/takahirom/roborazzi/roborazzi/1.77.0/roborazzi-1.77.0.pom) | 与plugin同版；Robolectric4.17/Compose1.12.1组合待核实 | 是，非平台 |
| `androidx.test:runner`；runner class `androidx.test.runner.AndroidJUnitRunner` | 1.7.0 | Android KDF instrumentation | androidTest | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/test) | 与同批core1.7.0/ext.junit1.3.0配套；真实设备/provider证明待T032 | 否，AndroidX |
| `androidx.test:core` | 1.7.0 | ApplicationProvider | test/androidTest | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/test) | 官方同批版本；与Robolectric4.17组合待T003 | 否，AndroidX |
| `androidx.test.ext:junit` | 1.3.0 | AndroidJUnit4 | test/androidTest | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/test) | 同批Test1.7.0 + JUnit4；实际组合待核实 | 否，AndroidX |
| `junit:junit` | 4.13.2 | JUnit4 runner/assertions | test/androidTest | EPL-1.0 | [官方坐标](https://junit.org/junit4/dependency-info.html)、[POM/license](https://repo.maven.apache.org/maven2/junit/junit/4.13.2/junit-4.13.2.pom) | [Robolectric官方setup](https://robolectric.org/getting-started/)明确使用4.17 + JUnit4.13.2 | 是，JUnit |
| `androidx.compose.ui:ui-test-junit4` | 1.12.1 | Compose入口/布局spike | test | Apache-2.0 | [Compose UI release](https://developer.android.com/jetpack/androidx/releases/compose-ui) | 同BOM；Robolectric/Roborazzi精确组合待T003 | 否，AndroidX |
| `androidx.compose.ui:ui-test-manifest` | 1.12.1 | Compose测试Activity | debug | Apache-2.0 | [测试setup](https://developer.android.com/develop/ui/compose/testing) | 同BOM；不进入release | 否，AndroidX |
| SDK `platforms;android-37.0` / compileSdk | 37.0，rev 2 | 编译平台 | build | Android SDK License Agreement | [官方repository XML](https://dl.google.com/android/repository/repository2-3.xml)、[SDK terms](https://developer.android.com/studio/terms) | stable channel-0；本机已装；[API/AGP表](https://developer.android.com/build/releases/about-agp#api-level-support)要求AGP≥9.1.1 | 否，Google工具 |
| targetSdk（非Maven坐标） | 36 | 目标行为/Play要求 | build config | 不适用 | [Play要求](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) | compile37≥target36≥min31；本机有API36镜像 | 否，平台配置 |
| minSdk（非Maven坐标） | 31 | 支持下限 | build config | 不适用 | [API levels](https://developer.android.com/guide/topics/manifest/uses-sdk-element#ApiLevels)；ADR-001 D1/Q2 | 已批准下限；API31/32系统证据仍缺镜像 | 否，平台配置 |
| SDK `build-tools;36.0.0` | 36.0.0 | aapt2/dex等构建工具 | build | Android SDK License Agreement | [官方repository XML](https://dl.google.com/android/repository/repository2-3.xml) | stable channel-0；[AGP9.3默认/最低](https://developer.android.com/build/releases/agp-9-3-0-release-notes)；已装 | 否，Google工具 |
| SDK `emulator` | 37.2.13 | 后续宿主系统验证 | build/test | Android SDK License Agreement及随包第三方声明 | [官方repository XML](https://dl.google.com/android/repository/repository2-3.xml) | stable channel-0；本机37.2.12，拟议patch未装；QPR2镜像实际启动待核实 | 否，Google工具 |
| `system-images;android-36.1;google_apis;arm64-v8a` | API36.1，rev 4 | QPR2规则系统验证 | test，T006 | Android SDK License Agreement及镜像随包条款 | [官方image XML](https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml) | stable channel-0；与arm64宿主匹配；未装，具体build/解析证据待宿主核实 | 否，Google工具 |

Wrapper SHA-256（仅拉取官方checksum文本，未下载ZIP）：`84fbba45c7f4c64abc77460e1c00f541e9f960e3c7ed2538f1ede19eacd873ae`，对应上表 `gradle-9.7.0-bin.zip`。

**最小集合与排除项**

- Roborazzi spike先申请plugin + `roborazzi`，用Compose测试rule直接捕获；本轮还核实了 `roborazzi-compose:1.77.0`、`roborazzi-junit-rule:1.77.0` 的官方POM/Apache-2.0，但不列入拟引入集合，不默认增加。Paparazzi不选；不引入Compose Multiplatform或上游样例的完整依赖集合。
- `androidx.room` Gradle plugin暂不申请；后续用已批准KSP的schema参数方案。`core-ktx`、显式 lifecycle、coroutines、sqlite-framework、ui-tooling/preview均不申请为直接依赖；如被已选库传递引入，必须在完整图中逐坐标/版本核实，不能省略。Material3仅预报后续组件需求，T002/spike不预加。
- D12已定按需Material Symbols SVG转vector drawable，附Apache-2.0署名；不新增图标Maven库。具体资产commit、文件映射和provenance在资产任务核实。[官方Material Symbols](https://github.com/google/material-design-icons)
- D13只用平台 `javax.crypto` / `java.text.Normalizer`，无额外Maven库；Android provider归所运行镜像，JVM provider归JDK，不伪造独立库版本。T032必须核实NFC/UTF-8非ASCII口令双端key字节，不能仅查询算法名。[Android SecretKeyFactory](https://developer.android.com/reference/javax/crypto/SecretKeyFactory)
- D05复用已批准Noto Sans SC资产与OFL，不增加联网字体依赖；此轮不复制或修改字体。Node沿用已装26.8.2，仅未来generator使用内建模块，不下载npm包。[Node26.8.2 release](https://nodejs.org/en/blog/release/v26.8.2)

**批准后安装/下载与缓存边界**

| 阶段 | 预计内容 | 预计位置与限制 |
|---|---|---|
| T002前环境准备 | 批准的Temurin21.0.13+9 macOS/aarch64；如需CLI安装能力，另报cmdline-tools23.0（当前官方stable metadata），不使用动态版本选择 | 安装方式/位置由宿主执行方确认；本轮不改全局Java/SDK |
| T002 Wrapper首次运行 | Gradle9.7.0 bin distribution；wrapper JAR/scripts的官方来源与校验另核 | 默认 `~/.gradle/wrapper/dists/`；沙箱全局缓存不可写，后续可用临时 `GRADLE_USER_HOME`（如 `/private/tmp/finecoach-s0-gradle-home`），届时实测，不改全局配置 |
| T002构建/测试 | AGP/KGP/Compose compiler插件及marker、stdlib、Compose BOM/所需AAR、Activity/Navigation、JUnit/Test；相应传递Maven POM/module/JAR/AAR、aapt2/lint/R8等工具 | Google Maven、Maven Central、Plugin Portal → Gradle user home的 `caches/modules-2/`、transforms等；项目会有 `android/.gradle/`、`android/app/build/`，当前均未创建 |
| T003最小spike | Robolectric4.17、Roborazzi1.77.0、Compose UI测试依赖及传递图、native graphics运行库 | 同上；字体/locale/运行耗时尚未实跑；负责人自行录制并批准smoke基线后agent才verify |
| Robolectric测试首次运行 | API36示例：`org.robolectric:android-all:16-robolectric-13921718` 或默认preinstrumented `org.robolectric:android-all-instrumented:16-robolectric-13921718-i7`；compile37的compile资源可能另需API37 jar，按测试配置实际请求核实 | 版本来自[4.17 DefaultSdkProvider](https://github.com/robolectric/robolectric/blob/robolectric-4.17/robolectric/src/main/java/org/robolectric/plugins/DefaultSdkProvider.java)，不能冒称已下载。动态resolver缓存与Gradle cache分开，默认本地Maven仓库 `~/.m2/repository`，可由 `maven.repo.local` 指定；[resolver源码](https://github.com/robolectric/robolectric/blob/robolectric-4.17/plugins/maven-dependency-resolver/src/main/java/org/robolectric/internal/dependency/MavenDependencyResolver.java)另有 `~/.robolectric-download-lock`。只改Gradle缓存不足以解决该锁的沙箱写权限；后续按plan退路定位或交宿主执行 |
| T006/T010宿主系统验证 | 上表QPR2镜像、批准的emulator patch；API31/32镜像的精确坐标/revision另报批准 | 默认 `~/Library/Android/sdk/{system-images,emulator}` 与 `~/.android/avd/`；当前沙箱不可写，交宿主执行方，不安装 |
| T007/T008 | Room runtime/compiler/testing与KSP及实际SQLite/coroutines传递项 | 按实际使用阶段下载，进入同一逐坐标resolved allowlist，不为T002预下载 |

**待核实 / 阻塞**

1. 负责人逐行批准D01/D04及D03最小spike精确集合；未取得前T001保持待批准，T002不启动。D12/D13已有决定，不重开产品选择。
2. KSP2.3.13 + Kotlin2.4.21 + Room2.8.5 + AGP9.3.1没有找到覆盖全组合的官方兼容矩阵；记录为待核实。Roborazzi1.77.0上游固定AGP8.13.2、Robolectric4.14.1、Compose1.8.3，且有Compose compiler classloader回归注释；不能据其release存在推定本组合兼容。批准后通过T003定向spike收证据，同问题两次失败即停止上报。
3. 完整build/runtime/test传递图、每个artifact的license/minCompileSdk/Kotlin metadata约束、依赖checksum和allowlist未生成。已读AGP9.3.1 POM中存在UTP `1.0.0-beta10` 内部依赖标记；本表仅选择stable直接版本，不把内部预发布依赖自动视为已批准。如“仅稳定版”要求覆盖全部传递项，此处须先裁决或另找组合，不擅自强制替换AGP内部依赖。Roborazzi也传递引入`com.dropbox.differ:differ`等第三方，须逐项批准，不能用group通配放行。
4. Compose BOM最新性存在官方来源差异：检索出现2026.10.01，但Google Maven metadata release为2026.09.00、2026.10.01 POM返回404；停止追查该版本，候选采用已返回200且映射已核实的2026.09.00，不声称它是所有来源中的最新。未下载artifact。
5. 本机缺拟议Temurin、Gradle9.7.0、sdkmanager、QPR2/API31/API32镜像；无本轮Gradle、Robolectric、Compose、截图、KDF、Android系统解析或模拟器可运行证据。宿主/沙箱结果必须分开；metadata联网可用不能记作依赖下载或离线构建PASS。
6. SDK工具、镜像、JDK archives与wrapper JAR的精确hash/随包license、QPR2 build、必要时D10公开params均待后续核实。本轮不提供未跑过的build/test命令，不修改AGENTS命令段落或tasks复选框。

## 构建

T002 只建立单 `:app` 的 Compose / Navigation 空白壳，无功能页、数据或网络调用。`namespace` 与 `applicationId` 均为 `com.ignacioli.finecoach`（负责人 2026-11-04 决定）。Google Play 首次上传后 applicationId 不可再改；Android 与 Apple Bundle ID 互不约束。此壳不代表 DS-LAUNCH 或 Android 功能界面已获视觉验收；无新交互，entry/layout map 无条目。没有图标资产，AD-04 后续处理。

从产品 worktree 的 `android/` 运行。宿主预先安装批准的 Temurin `21.0.13+9` arm64、SDK `platforms;android-37.0` 和 `build-tools;36.0.0`；不自动安装 SDK 或 JDK，不改系统默认 Java。Wrapper 固定 Gradle `9.7.0` 和批准的 distribution SHA-256；构建脚本使用 Java toolchain 21，AGP 内建 Kotlin 通过 KGP classpath 固定为 `2.4.21`，不应用 `org.jetbrains.kotlin.android`。

```sh
export JAVA_HOME="$HOME/Library/Java/JavaVirtualMachines/jdk-21.0.13+9/Contents/Home"
export GRADLE_USER_HOME="$HOME/.cache/finecoach-android/gradle-home"
export ANDROID_USER_HOME="$HOME/.cache/finecoach-android/android-user-home"
mkdir -p "$GRADLE_USER_HOME" "$ANDROID_USER_HOME"
printf 'sdk.dir=%s/Library/Android/sdk\n' "$HOME" > local.properties

./gradlew --stop   # 清掉沙箱里启动的 daemon，避免复用
perl -e 'alarm shift; exec @ARGV' 1800 ./gradlew --version
perl -e 'alarm shift; exec @ARGV' 720 ./gradlew assembleDebug lint
perl -e 'alarm shift; exec @ARGV' 720 ./gradlew :app:testDebugUnitTest --tests '*InfrastructureConfigurationTests'
```

`local.properties`、`.gradle/`、`.kotlin/`、所有 module `build/` 和备用 `.gradle-home/` 均被忽略。若指定的用户缓存不可写，可将 `GRADLE_USER_HOME` 改为当前目录的 `.gradle-home/`。不要写全局 `~/.gradle/gradle.properties`。首次依赖准备上限 30 分钟，之后每次调用上限 12 分钟；macOS 没有 GNU `timeout`，上面用 `perl -e 'alarm N; exec @ARGV'` 限时：超时进程收到 SIGALRM 退出，退出码非零。

Gradle 和 Robolectric 测试在宿主机运行，不在 agent 沙箱内运行：沙箱内 Maven 依赖下载会 TLS 握手失败，Robolectric 也无法写 `~/.robolectric-download-lock`。若之前在沙箱里跑过 Gradle，先 `./gradlew --stop`，否则宿主命令会复用沙箱 daemon 并继承它的限制。

`app/build.gradle.kts` 给所有 `Test` task 加 `--add-exports=java.base/jdk.internal.access=ALL-UNNAMED`：Robolectric 4.17 在 JDK 21 上需要读取 `FileDescriptor` 内部字段，缺这一行时 Robolectric 测试全部以 `IllegalAccessException` 失败。

`InfrastructureConfigurationTests` 用 AGP `SingleArtifact.MERGED_MANIFEST` 产物检查 SDK 下限/目标、无 `INTERNET`、`allowBackup=false` 和唯一 launcher Activity；compileSdk 从实际 Gradle DSL 传入测试，独立断言批准值。Robolectric 固定 API36，在 JVM 启动 `MainActivity`；这不是设备启动或系统隐私行为证据。JUnit XML 位于 `app/build/test-results/testDebugUnitTest/`，必须实际执行数 >0、0 failures、0 errors、0 skipped。

预置标准 main/debug/release/test/androidTest source sets；JVM test resources 指向同一产品根的 `shared/test-vectors/`，synthetic schema assets 预留 `app/src/test/assets/`。未创建或复制共享向量、Room schema、字体或基线。JUnit、Robolectric、Compose UI test 与 Android instrumentation runner/core/ext.junit 已配置；Room/KSP/Roborazzi 仅 pin 到 catalog，待对应任务应用和接入，不代表兼容性 smoke 已通过。

预留 `s0G1`、`s0G2`、`s0G3`、`s0G4`、`s0G5`、`s0G6`、`s0G8`、`s0Room`、`s0SeedIsolation`、`s0InstallSeededDebug`、`s0EnvironmentSmoke`、`generateDesignTokens`、`checkDesignTokens`，目前每个执行时均抛出「未实现」错误，不能 PASS。后续按 plan §4 接入独立 Test task、专属 filter/结果目录及非空报告验证；G5 只接 verify。不注册 G7。

T002 Manifest 仅落地无 `INTERNET` 和 `allowBackup=false`。三段九域 dataExtractionRules、debug/release 完整隐私检查及 QPR2 系统解析留 T004～T006；API31/32 onPause 遮盖、API33+ 最近任务截图策略及系统验证留 T009～T010；不使用 `FLAG_SECURE`。KDF 双端证明、环境截图 spike 及完整 resolved allowlist 分别留 T032、T003、T005。按本轮白名单不改 `AGENTS.md`，实际命令登记由 T003 完成。

**T002 验证结果（2026-11-03，宿主机，Temurin 21.0.13+9 arm64）**

- `./gradlew assembleDebug lint`：退出 0。lint 无 error，1 条 warning `OldTargetApi`（targetSdk 36 为负责人批准值）。
- `./gradlew :app:testDebugUnitTest --tests '*InfrastructureConfigurationTests'`：退出 0；JUnit XML 实际执行 4，0 failures、0 errors、0 skipped。
- `./gradlew :app:s0G1`：退出 1，输出「s0G1 未实现」；其余预留 gate 用同一实现。
- Wrapper：Gradle 9.7.0 分发 SHA-256 与批准值一致；Wrapper JAR SHA-256 `7a9ce74cff467ca1bf60a4fcd9f05185acceda4d0f382434d393e17864262c5d` 与官方 checksum 一致。
- 沙箱内首轮（Codex）因依赖下载 TLS 握手失败未能完成，以上为宿主复跑结果。
- debug merged manifest 中 AndroidX Core 传递引入 `com.ignacioli.finecoach.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`（signature）。未新增源码权限声明，未静默移除库声明；该项纳入 T005 权限/传递依赖白名单审查，当前不宣称空权限集合或完整 G8 PASS。
- 已知 warning：source set 旧式 `srcDir` API deprecation、native library 无法 strip；不影响本轮结果。
