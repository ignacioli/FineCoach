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

**当前批准状态：已批准（负责人 2026-11-03）。** 以下版本表及其“待批准”描述保留为 T001 申请时的历史记录；负责人现已批准表内版本，并接受 AGP 传递依赖 `1.0.0-beta10` 的 beta 例外（实为 `jetifier-core` 与 `jetifier-processor`，旧称「UTP」有误，2026-11-04 改正）。JDK 固定 Temurin `21.0.13+9`（arm64）；未修改表内版本值。

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
| `org.jetbrains.kotlinx:kotlinx-serialization-bom` | 1.8.1 | 对齐 Room 2.8.5 测试依赖与 navigation/lifecycle 的传递版本 | implementation platform | Apache-2.0 | 负责人 2026-11-05 裁决（见 T008 修复轮 2） | **负责人已批准（2026-11-05）**；core/core-jvm/json 对齐，宿主 resolved graph 与设备复跑待核实 | 是，JetBrains |
| `org.jetbrains.kotlin.plugin.compose` → `org.jetbrains.kotlin:compose-compiler-gradle-plugin` | 2.4.21 | Compose compiler | plugin | Apache-2.0 | [compiler setup](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler) | 官方要求与Kotlin同版本；不由Compose BOM管理 | 是，JetBrains |
| `androidx.compose:compose-bom` | 2026.09.00 | Compose版本约束 | implementation/test platform | Apache-2.0 | [官方POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.09.00/compose-bom-2026.09.00.pom) | 本轮POM核实下列版本；[BOM说明](https://developer.android.com/develop/ui/compose/bom) | 否，AndroidX |
| `androidx.compose.runtime:runtime` | 1.12.1 | 状态 runtime | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-runtime) | 由上述[BOM POM](https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.09.00/compose-bom-2026.09.00.pom)约束 | 否，AndroidX |
| `androidx.compose.ui:ui` | 1.12.1 | Compose UI | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-ui) | 同BOM；与选定compiler端到端运行待T003 | 否，AndroidX |
| `androidx.compose.ui:ui-text` | 1.12.1 | 随包字体/排版 | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-ui) | 同BOM | 否，AndroidX |
| `androidx.compose.foundation:foundation` | 1.12.1 | 几何/布局fixture与基础交互 | implementation | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-foundation) | 同BOM | 否，AndroidX |
| `androidx.compose.material3:material3` | 1.4.0 | 后续已批准Material平台组件 | implementation，后续组件阶段 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/compose-material3) | T013 接入（2026-11-05）；由 Compose BOM 管理版本 | 否，AndroidX |
| `com.google.devtools.ksp` → `com.google.devtools.ksp:symbol-processing-gradle-plugin` | 2.3.13 | Room代码生成 | plugin，KSP2 | Apache-2.0 | [release](https://github.com/google/ksp/releases/tag/2.3.13)、[KSP2](https://github.com/google/ksp/blob/2.3.13/docs/ksp2.md) | KSP2不沿用KSP1版本前缀配对；与Kotlin2.4.21/AGP9.3.1/Room2.8.5的精确组合官方矩阵待核实 | 外部工具，Google维护 |
| `androidx.room:room-runtime` | 2.8.5 | 私有SQLite ORM | implementation，T007 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/room) | 官方要求Kotlin≥2.0、建议KSP2，minSdk23≤31；精确KSP组合待核实 | 否，AndroidX |
| `androidx.room:room-compiler` | 2.8.5 | DAO/schema生成 | ksp，T007 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/room) | 与runtime同版，KSP2；生成实跑待后续 | 否，AndroidX |
| `androidx.room:room-testing` | 2.8.5 | synthetic migration helper | androidTest，T008 | Apache-2.0 | [release](https://developer.android.com/jetpack/androidx/releases/room) | 与runtime/compiler同版；T008 改为 instrumentation，设备运行待宿主验证 | 否，AndroidX |
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
3. 完整build/runtime/test传递图、每个artifact的license/minCompileSdk/Kotlin metadata约束、依赖checksum和allowlist未生成。已读AGP9.3.1 POM中存在 `1.0.0-beta10` 内部依赖标记（实为 jetifier，旧称 UTP 有误）；本表仅选择stable直接版本，不把内部预发布依赖自动视为已批准。如“仅稳定版”要求覆盖全部传递项，此处须先裁决或另找组合，不擅自强制替换AGP内部依赖。Roborazzi也传递引入`com.dropbox.differ:differ`等第三方，须逐项批准，不能用group通配放行。
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
perl -e 'alarm shift; exec @ARGV' 300 ./gradlew :app:s0EnvironmentSmoke
```

`local.properties`、`.gradle/`、`.kotlin/`、所有 module `build/` 和备用 `.gradle-home/` 均被忽略。若指定的用户缓存不可写，可将 `GRADLE_USER_HOME` 改为当前目录的 `.gradle-home/`。不要写全局 `~/.gradle/gradle.properties`。首次依赖准备上限 30 分钟，之后每次调用上限 12 分钟；macOS 没有 GNU `timeout`，上面用 `perl -e 'alarm N; exec @ARGV'` 限时：超时进程收到 SIGALRM 退出，退出码非零。

Gradle 和 Robolectric 测试在宿主机运行，不在 agent 沙箱内运行：沙箱内 Maven 依赖下载会 TLS 握手失败，Robolectric 也无法写 `~/.robolectric-download-lock`。若之前在沙箱里跑过 Gradle，先 `./gradlew --stop`，否则宿主命令会复用沙箱 daemon 并继承它的限制。

`app/build.gradle.kts` 给所有 `Test` task 加 `--add-exports=java.base/jdk.internal.access=ALL-UNNAMED`：Robolectric 4.17 在 JDK 21 上需要读取 `FileDescriptor` 内部字段，缺这一行时 Robolectric 测试全部以 `IllegalAccessException` 失败。

`InfrastructureConfigurationTests` 用 AGP `SingleArtifact.MERGED_MANIFEST` 产物检查 SDK 下限/目标、无 `INTERNET`、`allowBackup=false` 和唯一 launcher Activity；compileSdk 从实际 Gradle DSL 传入测试，独立断言批准值。Robolectric 固定 API36，在 JVM 启动 `MainActivity`；这不是设备启动或系统隐私行为证据。JUnit XML 位于 `app/build/test-results/testDebugUnitTest/`，必须实际执行数 >0、0 failures、0 errors、0 skipped。

预置标准 main/debug/release/test/androidTest source sets；JVM test resources 指向同一产品根的 `shared/test-vectors/`，synthetic schema assets 预留 `app/src/test/assets/`。JUnit、Robolectric、Compose UI test 与 Android instrumentation runner/core/ext.junit 已配置；Room/KSP 仍仅 pin 到 catalog。T003 在 app 应用 Roborazzi 1.77.0 插件与已有 catalog 的 core 测试依赖，不加其他直接坐标；不代表兼容性 smoke 已通过。

预留 `s0G1`、`s0G2`、`s0G3`、`s0G4`、`s0G5`、`s0G6`、`s0G8`、`s0Room`、`s0SeedIsolation`、`s0InstallSeededDebug`、`generateDesignTokens`、`checkDesignTokens`，每个执行时仍抛出「未实现」错误，不能 PASS。后续按 plan §4 接入独立 Test task、专属 filter/结果目录及非空报告验证；G5 只接 verify。不注册 G7。`s0EnvironmentSmoke` 在 T003 实现，见下文。

T002 Manifest 仅落地无 `INTERNET` 和 `allowBackup=false`。三段九域 dataExtractionRules、debug/release 完整隐私检查及 QPR2 系统解析留 T004～T006；API31/32 onPause 遮盖、API33+ 最近任务截图策略及系统验证留 T009～T010；不使用 `FLAG_SECURE`。KDF 双端证明、环境截图 spike 及完整 resolved allowlist 分别由 T032、T003、T005 承担。

**T002 验证结果（2026-11-03，宿主机，Temurin 21.0.13+9 arm64）**

- `./gradlew assembleDebug lint`：退出 0。lint 无 error，1 条 warning `OldTargetApi`（targetSdk 36 为负责人批准值）。
- `./gradlew :app:testDebugUnitTest --tests '*InfrastructureConfigurationTests'`：退出 0；JUnit XML 实际执行 4，0 failures、0 errors、0 skipped。
- `./gradlew :app:s0G1`：退出 1，输出「s0G1 未实现」；其余预留 gate 用同一实现。
- Wrapper：Gradle 9.7.0 分发 SHA-256 与批准值一致；Wrapper JAR SHA-256 `7a9ce74cff467ca1bf60a4fcd9f05185acceda4d0f382434d393e17864262c5d` 与官方 checksum 一致。
- 沙箱内首轮（Codex）因依赖下载 TLS 握手失败未能完成，以上为宿主复跑结果。
- debug merged manifest 中 AndroidX Core 传递引入 `com.ignacioli.finecoach.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`（signature）。未新增源码权限声明，未静默移除库声明；该项纳入 T005 权限/传递依赖白名单审查，当前不宣称空权限集合或完整 G8 PASS。
- 已知 warning：source set 旧式 `srcDir` API deprecation、native library 无法 strip；不影响本轮结果。

## T003 Environment smoke 与最小截图 spike

本轮只实现 T003，不运行 Gradle、模拟器或 xcodebuild，不生成 PNG，不 commit。开工 tracked/staged 为空，untracked 仅用户已有 `.vscode/`，保留不动。规格从指定 canonical specs worktree 只读读取；产品 `ig-worktree-gate` PASS（`feat/android-s0-infrastructure`，missing links 为空）。本节是当前 Environment 状态，上文 T001/T002 的结果保留为历史证据。

`EnvironmentSmokeTests` 在 Robolectric API36 / NATIVE 下检查 JDK21、zh-CN locale、UTF-8 与数值格式，并实际组合/测量 96×64 dp Compose 节点。`EnvironmentScreenshotSpikeTests` 捕获固定几何色块/边框，无文字或图标；字面颜色非 DS token，仅环境 smoke。固定 `@Config(sdk = [36], qualifiers = "zh-rCN-w320dp-h480dp-notnight-mdpi")`，mdpi、fontScale=1、无动画，测试时钟手动推进一帧。此 fixture 无产品交互，entry/layout map 无新增条目，不是正式 DS 或 G5 验收。

`s0EnvironmentSmoke` 是独立 `Test` task，复用 AGP Debug 的 classpath、测试 classes 和 JVM 配置，不依赖 `testDebugUnitTest` 执行，也不复制其 Roborazzi 缓存恢复 actions。专属 filter 仅含 `EnvironmentSmokeTests`（2）、`PlatformCryptoAvailabilityTests`（1）、`PlatformCryptoParityTests`（3）、`EnvironmentScreenshotSpikeTests`（1），当前共预期 **7 tests**。每次调用强制实际执行、不接受 up-to-date/build-cache；不靠修改测试源码重跑。record=true 在配置/执行前拒绝，verify 固定开启；缺 `screenshot-baselines/environment/fixed-geometry.png` 直接失败。finalizer 拒绝 NO-SOURCE/skip/执行失败，再读取专属 JUnit XML：四个 suite 均须出现且各自非零，统计 testcase 实际数并交叉核对 `tests`，任何 failure/error/skipped 均失败。其他预留 gate 仍「未实现即失败」。

专属 XML：`app/build/test-results/s0EnvironmentSmoke/TEST-*.xml`；HTML：`app/build/reports/tests/s0EnvironmentSmoke/`；Roborazzi 文字 JSON：`app/build/reports/s0/environment/results/`；差异图：`app/build/reports/s0/environment/images/`。agent 只读文字，不查看 PNG。baseline 是显式文件路径，插件缓存/恢复目录只在 `app/build/outputs/roborazzi/environment/`，不能补回缺失 baseline。

**编排方宿主机命令**（cwd=`android/`，沿用上文已批准环境；本轮未执行）：

```sh
perl -e 'alarm shift; exec @ARGV' 720 ./gradlew assembleDebug lint
perl -e 'alarm shift; exec @ARGV' 300 ./gradlew :app:testDebugUnitTest --tests '*EnvironmentSmokeTests' --tests '*PlatformCryptoAvailabilityTests' --tests '*PlatformCryptoParityTests'
perl -e 'alarm shift; exec @ARGV' 300 ./gradlew :app:s0EnvironmentSmoke
```

前两条预期成功（定向 JVM 6 tests）；第三条首次缺基线应非零失败，状态 BLOCKED，不能自动录制。负责人录制/批准后第三条预期 7 tests、0 failures/errors/skips。编排方分别记录首次依赖解析与冷/暖执行耗时、退出码、测试数、报告路径、resolved graph/缓存来源及 baseline diff；warm 重跑用同一命令，task 自身禁用缓存复用。额外负例 `./gradlew :app:s0EnvironmentSmoke -Proborazzi.test.record=true` 必须失败且不写基线。设备沿用下一节 `am instrument` 流程，不使用 UTP。

**负责人专用 record（只能由负责人运行，agent 禁止）**：本轮任务明确要求在此交付命令，仅限 environment fixture。先查看 fixture/配置，亲自执行以下一条，再登记批准文件与 SHA-256；不作为普通 gate 或 agent 运行清单：

```sh
./gradlew :app:testDebugUnitTest --tests 'com.ignacioli.finecoach.EnvironmentScreenshotSpikeTests' -Proborazzi.test.record=true -Proborazzi.test.verify=false --rerun-tasks
```

命令只选择 environment screenshot suite，写 `android/screenshot-baselines/environment/fixed-geometry.png`。没有 task 默认 record。基线目录本轮仅有 README；禁止 agent 录制或更新文件。

接口核对依据：[Roborazzi 1.77.0 README](https://github.com/takahirom/roborazzi/blob/1.77.0/README.md) 的插件/core 依赖与 record/verify 属性；[core 捕获源码](https://github.com/takahirom/roborazzi/blob/1.77.0/roborazzi/src/main/java/com/github/takahirom/roborazzi/Roborazzi.kt) 提供 `SemanticsNodeInteraction.captureRoboImage(file: File)`，无需 `roborazzi-compose` 或 rule 的额外直接坐标；[plugin 源码](https://github.com/takahirom/roborazzi/blob/1.77.0/include-build/roborazzi-gradle-plugin/src/main/java/io/github/takahirom/roborazzi/RoborazziPlugin.kt) 核对 `roborazzi.compare.output.dir` / `roborazzi.result.dir` / `roborazzi.project.path`。catalog 无改动。AGP9.3.1 本地 JAR 的 classpath 构造包含 UNIT_TEST_CONFIG_DIRECTORY；复制保留其 FileCollection build dependencies。尚未编译或执行，精确 Gradle9.7.0/AGP9.3.1/Roborazzi1.77.0 组合、NATIVE 渲染与完整传递坐标仍需宿主核实，不能报告 PASS；若出现 catalog 外新增直接坐标需求，停止并上报。

## KDF 一致性证明

T032 / D13 仅证明 NFC → UTF-8 → PBKDF2-HMAC-SHA256 的密钥字节，不实现容器或 AES-GCM。唯一虚构 fixture 为 `shared/test-vectors/s0/crypto/m1a-fr-044__kdf-nfc-equivalence.json`（相对产品根）；NFC/NFD 两种输入共用固定 32 字节 salt、600000 次、32 字节期望 key 及 NFC UTF-8 SHA-256。`when.op = backup-kdf.derive-equivalent` 在本定向测试中映射到 Android `BackupKDF.deriveKey` 和 iOS `BackupPassword(importing:)` + `BackupKDF.deriveKey`；不接入后续 Domain runner。JVM 使用受限的 fixture 字段读取器（ASCII JSON，仅支持 Unicode 字符串转义，重复/缺失字段报错），无新依赖；设备使用 `JSONObject`，iOS 使用 `JSONDecoder`。JVM resources 与 androidTest assets 指向同一共享目录，不复制数据。

沿用上文 JDK/缓存环境。前两条 cwd=`android/`，第三条 cwd=产品根；编排方须设置有效的 iOS destination 和独立 derived-data 路径，Android 仅连接一个指定设备。

```sh
perl -e 'alarm shift; exec @ARGV' 720 ./gradlew --offline :app:testDebugUnitTest --tests '*PlatformCryptoAvailabilityTests' --tests '*PlatformCryptoParityTests'

export S0_KDF_TEST_CLASS=com.ignacioli.finecoach.PlatformCryptoParityInstrumentedTests
perl -e 'alarm shift; exec @ARGV' 600 ./gradlew assembleDebug assembleDebugAndroidTest
adb install -r -t app/build/outputs/apk/debug/app-debug.apk
adb install -r -t app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
perl -e 'alarm shift; exec @ARGV' 300 adb shell am instrument -w -r -e class "$S0_KDF_TEST_CLASS" com.ignacioli.finecoach.test/androidx.test.runner.AndroidJUnitRunner

xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachTests -destination "id=${S0_IOS_DESTINATION_ID:?required}" -derivedDataPath "${S0_IOS_DERIVED_DATA:?required}" -only-testing:FineCoachTests/PlatformCryptoParityTests test
```

`S0_KDF_TEST_CLASS` 的实际全名为 `com.ignacioli.finecoach.PlatformCryptoParityInstrumentedTests`。JVM 预期 4 tests（`PlatformCryptoAvailabilityTests` 1 + `PlatformCryptoParityTests` 3，含参数拒绝），设备与 iOS 各 2 tests；要求非空、0 failures/errors/skips。测试输出平台/provider、输入名称、digest/key hex；设备 serial 由编排方另外记录。JVM 结果仅算 host smoke，Android instrumentation 与 iOS 均通过且对照一致后才满足 T032 完成线。T003 将这两个 JVM suite 接入 `s0EnvironmentSmoke`。

设备测试一律用 `adb shell am instrument`，不用 `connectedDebugAndroidTest`（负责人 2026-11-04 裁决）。后者经 AGP 的 UTP 解析 `com.google.testing.platform:android-device-provider-local:0.0.9-alpha04` 等额外依赖，不在已批准的 beta 例外内。直接运行同一测试 APK，检查 `OK (N tests)`、0 failures/errors/skips 和 provider/key 文字，不能只看 adb 退出码。

**T032 验证结果（2026-11-04，宿主机）**

| 平台 | 结果 | provider | NFC/NFD key |
|---|---|---|---|
| JVM，Temurin 21.0.13 | 4 tests，0 failures/errors/skipped | PBKDF2 SunJCE；AES-GCM Conscrypt | `02171f9cb0decb1812ab132a927109f42dfff580ff96bacb0acc3b25adab2fdb` |
| Android 模拟器 `emulator-5554`，API 36，`google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.D1/13818094` | `OK (2 tests)` | BC | 同上 |
| iOS 模拟器 iPhone 17，iOS 26.5（23F77） | `Executed 2 tests, with 0 failures`，`TEST SUCCEEDED` | CommonCrypto | 同上 |
| 独立计算：Python `hashlib.pbkdf2_hmac` | NFC、NFD 均一致 | — | 同上 |

三端 NFC UTF-8 SHA-256 均为 `54a7a451447f7eb29db39828e92309c98034dd167261c476c396634f50473b95`。`PBEKeySpec` 在 Android BC 与 JVM SunJCE 下对非 ASCII 口令都按 UTF-8 编码，未启用 `Mac` 自实现备选。


**T003 验证结果（2026-11-04，宿主机，Temurin 21.0.13+9 arm64）**

- 依赖解析 `:app:dependencies --configuration debugUnitTestRuntimeClasspath`：退出 0，无 alpha/beta/rc/snapshot 坐标。
- 定向 `EnvironmentSmokeTests` + `PlatformCryptoAvailabilityTests` + `PlatformCryptoParityTests`：6 tests，0 failures/errors/skipped；环境 API36、JDK21、zh-CN、160 dpi、fontScale 1。
- 负责人 2026-11-04 亲自运行 record 命令并批准基线 `screenshot-baselines/environment/fixed-geometry.png`（PNG 96×64 RGBA，SHA-256 `255e06205d4180ab6037b8944ce4a029b2256b7f6e6d465b5312ada316e4ba7a`）。
- 录制前 `s0EnvironmentSmoke`：按预期失败（缺负责人基线，不自动录制）。
- 录制后 `s0EnvironmentSmoke`：冷启动（`--stop` 后）12 秒、热启动 5 秒，均为 7 tests、0 failures/errors/skips；verify 前后基线 SHA-256 不变，无差异图。
- `s0EnvironmentSmoke -Proborazzi.test.record=true`：配置阶段拒绝，退出 1，不写基线。
- G0 `assembleDebug lint`：退出 0。
- 未验证：基线像素被改动时 verify 能否失败（受控失败样例属于后续 G5 任务）；本 smoke 不是 DS 组件或 G5 验收。

## G8 聚合门

在 `android/` 运行 `./gradlew :app:s0G8`。按 S0 spec §5 的 G8 映射固定以下 8 个 suite（当前合计 **78 tests**）；不使用此前 targeted 替代集合缩小覆盖。

| Suite（package 均为 `com.ignacioli.finecoach`） | executions |
|---|---:|
| InfrastructureConfigurationTests | 4 |
| CapabilityManifestTests | 9 |
| BackupRulesTests | 5 |
| PrivacySourceScanTests | 11 |
| StoragePrivacyTests | 3 |
| PrivacyCoverTests | 11 |
| FictionalDataPolicyTests | 16 |
| ScopeBoundaryTests | 19 |

条数按当前测试源码的 `@Test` 与 Robolectric SDK 展开声明；`PrivacyCoverTests` 为 8 方法、11 executions（3 方法分别运行 API31/32）。历史 targeted 记录中的条数保留，不作为当前聚合数量。`StoragePrivacyTests` 按 spec 同时归属 G8 与 `s0Room`，此重复归属交 dispatcher 确认，不自行移除；其余 suite 与 G1/G2/G6/Room 无重复。

独立 `Test` task 复用 AGP debug JVM runtime，每次强制执行且不使用结果缓存。保留 debug/release merged manifests、merged resources、APKs 与完整 resolved dependency graph 的现有 provider/input/任务依赖，不回退源 XML。`validateS0G8Results` finalizer 拒绝 task skip/失败、空报告、缺失/重复/意外 suite、条数偏差以及任何 failure/error/skip。JUnit XML：`app/build/test-results/s0G8/`；HTML：`app/build/reports/tests/s0G8/`。

plan §4 warm 建议上限为 5min。此门不替代 T006/T010 系统证据、T028 或 CP1 验收。

## S0-03 T004 targeted 实施记录（2026-11-04，待宿主验证）

基点 `93c3fe1`，branch `feat/android-s0-infrastructure`；初始 tracked/staged 为空，仅用户已有 untracked `.vscode/`，保留。只读 specs canonical 路径为 `/Users/liyongqiang/gitrepo/ignacioli/.worktree/specs-android-s0/FineCoach/007-android-port/s0-infrastructure/`。本轮禁止 Gradle/模拟器/xcodebuild，不 commit、不改任务勾选；无新 UI 或 entry/layout map 条目。

差异：Manifest 原来只有 allowBackup=false → 绑定现代三段规则；新增 cloud-backup、device-transfer、cross-platform-transfer(platform=ios) 的全部九域 path="." exclude，无 include/params。FR-030/ADR §6.1 原为 minSdk31 不要求 fullBackupContent → 按编排方要求（非负责人决定）新增旧版 full-backup-content 九域排除，作为冗余防护；spec 正文尚未更新；minSdk31 保持。未移除原配置；QPR2 系统接受性由 T006 验证。

`BackupRulesTests` 共 5 tests：debug/release 合并规则正例，受控 fixture 缺段/缺域/include 三负例，无效资源引用拒绝。fixture 位于 test/resources，不打包进 main。Manifest 由 `SingleArtifact.MERGED_MANIFEST` provider 接入；规则 XML 由 AGP9.3.1 `MergeResources.mergedNotCompiledResourcesOutputDirectory` 输出接入，Test inputs/dependsOn 保证合并后读取，按 manifest @xml 引用唯一解析，不回退源文件。该 MergeResources 接口通过本地 9.3.1 JAR 的 javap 核对；属 AGP 实现类型，宿主仍须验证 Kotlin DSL 接线与 XML 输出形状。静态 xmllint/diff 检查不等于测试 PASS。

## S0-03 T005 targeted 实施记录（2026-11-04，待宿主验证）

T004 文件实现及 XML 静态检查完成后开始 T005，共享文件串行修改。未运行 Gradle、模拟器或 xcodebuild；不宣称 T004/T005 验收通过，不运行 T006，不修改完整 `s0G8` 的「未实现即失败」逻辑。执行者 Codex；宿主复跑/系统验证交编排方；cursor-agent 独立复核尚未取得。

（历史记录，现行入口集合见下文修复轮 1 一节）权限集合只允许 AndroidX Core 的 `com.ignacioli.finecoach.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`，声明必须为 signature，无其他 uses-permission。debug/release 两套 merged manifest 都检查。原 debug 合并产物有测试宿主 `androidx.activity.ComponentActivity` 与 `androidx.profileinstaller.ProfileInstallReceiver` exported=true → main manifest 用 mergeOnlyAttributes/replace 将二者降为 false；保留库组件供内部使用，唯一 exported 入口为 MainActivity 的 MAIN/LAUNCHER。没有给库入口静默加例外。该合并行为及 Compose smoke 回归仍需宿主验证。

`PrivacySourceScanTests` 扫描非空 main Kotlin/Java 原文（包括 import alias/注释，不能用 suppression 绕过）：java.net/javax.net/android.net、URLConnection/HttpURLConnection、Socket/WebView、OkHttp/Retrofit/Ktor/Apache HTTP/Cronet/Volley、Firebase/Crashlytics/Sentry/Amplitude/Mixpanel、SQLCipher、FLAG_SECURE、android.util.Log/Log 调用、print/println/printf、System.out/err、printStackTrace、java.util.logging/Timber。test/resources 有网络、窗口、日志、遥测受控负例，逐行验证拒绝；权限/入口/signature、未知依赖/版本另有负例。扫描是保守静态守卫，不证明动态代码或第三方 SDK 无网络行为；依赖与 manifest 为另两道边界。

依赖白名单 `dependency-allowlist/resolved.txt` 来自本轮指定宿主机八份文本，保留每个 scope 的最终 selected 坐标、BOM/传递项，忽略图中的本地 project :app 引用；**702 行 scoped 坐标，306 个唯一 group:artifact:version**。scope 行数：debugCompile=85、debugRuntime=100、releaseCompile=84、releaseRuntime=99、debugUnitTestRuntime=164、debugAndroidTestRuntime=34、root build classpath=136、app build classpath=0。`writePrivacyDependencyGraph` 使用 Gradle ResolutionResult 重新解析相同八个 scope，任何 unresolved 失败；测试要求全 scope 出现、坐标/版本/范围集合精确相等，未知或缺失均失败，禁止遥测与 SQLCipher。此白名单是宿主图的库存基线，不代表待确认项获批。

特殊项单独注释「AGP 内部预发布，负责人已接受（2026-11-04）」：jetifier-core/jetifier-processor 1.0.0-beta10 确实 selected；aapt2-proto 7.3.0-alpha07-8248216 仅 requested，selected 是 9.3.1-15703166，未把 alpha 加入 selected 白名单。负责人确认仍 PENDING，库存一致测试不能代替依赖批准。

**日志范围缺口**：FR-034 没有给固定事件词表、输出目的地或 debug logger 行为；当前壳没有日志需求/实现。本轮不发明事件或新增无调用方的 logger，静态守卫禁止所有直接日志；Release APK 通过 artifact provider 构建后读取 DEX，确认不存在约定的 app DebugEventLogger descriptor 与虚构敏感 sentinel，并检查 debug/release 源集没有日志。此检查仅证明当前无 debug logging implementation 的状态；**固定事件封装实现尚未提供，FR-034 的完整实现保持 PENDING**。未来若需要日志，应先定义固定事件契约，再替换本轮“无日志”检查为该契约与实际 logger 隔离检查；不能把目前的占位名称扫描当任意 logger 的完整字节码证明。没有改 main Java/Kotlin 产品代码或源集，无敏感数据。

新增 Test 输入只接 AGP 的 testDebugUnitTest/testReleaseUnitTest，不接独立 s0EnvironmentSmoke；Release APK 通过 SingleArtifact.APK provider 输入依赖构建。源码/白名单/合并产物均登记 inputs；debug/release 可选源集以 fileTree 追踪未来新增 Kotlin/Java 文件，当前不存在这些产品源集。

**宿主复跑**（cwd=`android/`，沿用已批准 JDK21/SDK/cache；本轮未执行）：

```sh
./gradlew assembleDebug assembleRelease lint
./gradlew :app:testDebugUnitTest --tests '*BackupRulesTests' --tests '*CapabilityManifestTests' --rerun-tasks
./gradlew :app:testDebugUnitTest --tests '*CapabilityManifestTests' --tests '*PrivacySourceScanTests' --rerun-tasks
./gradlew :app:s0EnvironmentSmoke
```

第一条 G0/build；第二条 targeted 预期 9 tests（Backup 5 + Capability 4）；第三条 targeted 预期 13 tests（Capability 4 + Privacy 9）；最后一条既有环境回归 7 tests。每条测试要求非空、0 failures/errors/skips；两次 targeted 共用 `app/build/test-results/testDebugUnitTest/TEST-*.xml` 与 `app/build/reports/tests/testDebugUnitTest/`，编排方必须每次立即另存报告并标记命令/HEAD/退出码/实际数量，不能用第二次覆盖后的目录证明第一次。依赖报告 `app/build/reports/s0/privacy/resolved.txt`，合并 XML `app/build/privacyMergedResources/{debug,release}/`，manifest 路径由 artifact provider 提供。库存依赖测试即使通过，待确认预发布项/日志契约/独立复核/QPR2 仍未完成；不报告完整 G8 或 CP1 PASS。

本轮静态验证：XML 经 `xmllint --noout`，`git diff --check` 通过。新建四个 Kotlin 测试/辅助文件用本地 Kotlin 2.4.21 compiler + JUnit4.13.2 + 已发现的 SDK `platforms/android-37.0/android.jar`（`-no-jdk`）独立编译，exit 0；不运行测试、不验证 Gradle DSL。首次独立编译误用不存在的 android-37 路径而失败，改为实存 android-37.0 后成功；不涉及产品代码修复。编译提示的 parentFile nullable 访问已改为 safe call。Gradle DSL 的任务接线、完整合并与 APK 构建仍需宿主验证。

## S0-03 修复轮 1（2026-11-04）

本节覆盖上轮 T005 关于入口集合、白名单数量与预期测试数的记录；上文保留为历史。编排方宿主反馈：原 T004 targeted 9/9、s0EnvironmentSmoke 7/7 通过；G0 lint 报 ProfileInstallReceiver MissingClass，PrivacySourceScanTests 报库存白名单多出误解析的 `{strictly` 坐标。此次未运行 Gradle、lint、模拟器或 xcodebuild，不 commit；现有修改及用户 `.vscode/` 均保留。

逐项修订：

- `src/main/AndroidManifest.xml`：删除 ProfileInstallReceiver exported=false 覆盖；按本轮编排方裁决保留库默认 exported=true/DUMP 保护，以恢复 baseline profile 安装入口。未新增 receiver 源声明。
- `src/main/AndroidManifest.xml` → `src/debug/AndroidManifest.xml`：将 ComponentActivity exported=false 覆盖移至 debug；release 不再因 main 覆盖凭空声明测试 Activity。其余备份规则保持。
- `CapabilityManifestTests`：原来只允许 MainActivity exported → debug/release 都允许 MainActivity 与库 ProfileInstallReceiver，后者必须 exported=true 且 permission 精确等于 android.permission.DUMP；缺失/错误权限均由负例拒绝。全部组件集合分别锁定 debug 四项（MainActivity、ComponentActivity、InitializationProvider、ProfileInstallReceiver）与 release 三项（不含 ComponentActivity）；两个非 exported 组件必须显式 false。新增 release 混入 debug Activity 的拒绝负例。权限申请白名单未变。
- `dependency-allowlist/`：新增可复跑生成器 `generate-resolved.mjs`，先分离最终 ` -> selected` 再解析 requested 坐标；处理 `{strictly x}`、无 requested version、`(c)`、`(*)`、重复树节点及本地 project :app，拒绝未解析/动态版本/FAILED。八份宿主报告完整重生成，未手工删条目。
- `PrivacySourceScanTests`：白名单行格式从任意无空白版本收紧为精确版本语法，新增拒绝残留 `{strictly` 的负例，防止再次将报告语法写成允许坐标。

新库存：**686 条 scope 记录，292 个唯一坐标**，较上轮 702/306 分别减少16/14；其中 debugAndroidTestRuntimeClasspath 34→21、root build classpath 136→133，其余 scope 不变。减少的是 rich constraint 被错误截成 `{strictly` 的伪条目，解析回 selected 后与既有坐标去重。两个 Jetifier beta10 的“AGP 内部预发布，负责人已接受（2026-11-04）”及 aapt2-proto requested/selected 区分注释保持不变。

生成器从产品根运行（只读指定宿主报告，输出写当前脚本同目录 resolved.txt）：

```sh
node android/dependency-allowlist/generate-resolved.mjs "$HOME/.cache/finecoach-android/deps-2026-11-04"
```

本轮实际结果：生成器8个正向/本地 project 样例、4个拒绝样例全部通过；与宿主已经留存的 `app/build/reports/s0/privacy/resolved.txt` 集合比对，双方均686条，unknown=[]、missing=[]（旧报告静态比对，不等于本轮 Gradle 测试通过）。XML syntax 与 git diff --check 通过；四个 Kotlin 测试/辅助文件以本地 Kotlin2.4.21/JUnit4.13.2/android-37.0 android.jar（-no-jdk）独立编译 exit0、无诊断，未执行 JUnit。真实 merge/lint/Gradle targeted 仍待编排方宿主复跑。

更新后的宿主命令（cwd=`android/`）：

```sh
./gradlew assembleDebug assembleRelease lint
./gradlew :app:testDebugUnitTest --tests '*BackupRulesTests' --tests '*CapabilityManifestTests' --rerun-tasks
./gradlew :app:testDebugUnitTest --tests '*CapabilityManifestTests' --tests '*PrivacySourceScanTests' --rerun-tasks
./gradlew :app:s0EnvironmentSmoke
```

新预期：Backup5 + Capability7 = **12 tests**；Capability7 + Privacy10 = **17 tests**；s0EnvironmentSmoke 仍 **7 tests**。两次 targeted 仍须分别保存 XML/HTML、实际计数、退出码，全部要求非空且0 failures/errors/skips。固定事件日志契约、预发布依赖确认与T006系统验证的原有 PENDING 边界保持；本轮不声称完整 G8 PASS。

## S0-03 T006 QPR2 系统验证记录（2026-11-04，Claude 宿主机）

证据文件（gitignored，只在本机）：`.handoff/logs/2026-11-04-host-s0-03-t006-r3-{env,e2,e1,product}.txt`，由一个脚本生成，每条命令都记下原文输出和 `exit=`。早先的 r1/r2 日志没有保存 sentinel 查询输出，**不作为判定依据**。

环境（`r3-env.txt`）：serial `emulator-5554`；`ro.build.fingerprint`=`google/sdk_gphone64_arm64/emu64a:16/BE4B.251210.005/14574095:userdebug/dev-keys`；`ro.build.version.sdk`=36，`sdk_full`=36.1；transport `* com.android.localtransport/.LocalTransport`；adb 1.0.41（37.0.1）。APK SHA-256：产品 `b92af793…6039`、E1 `9f82deb2…2c9a`、E2 `5e8d9920…780d`；资源 digest 和 E1/E2 相对产品的 manifest/规则 diff 也记在这个文件里。

对照 APK 只在 scratch 副本中修改，产品 worktree 未改：
- 产品：`allowBackup=false` + 三段九域 exclude。
- E1：只把 `allowBackup` 改成 `true`，三段九域 exclude 不变。
- E2：`allowBackup=true`，三段规则清空，作为正向对照。

方法：每个 APK 安装后，用 `run-as` 写入 9 个虚构 sentinel，并 grep 确认 9 个都存在。CE 域写 `S0SENTINEL-{root,file,db,pref}`，DE 域写 `{droot,dfile,ddb,dpref}`，external 写 `ext`。之后每种模式依次执行：
1. `am start` 后按 HOME。
2. `settings put secure backup_local_transport_parameters`：cloud 为空，D2D 为 `is_device_transfer=true`，cross-platform 为 `is_cross_platform_transfer_ios=true`。
3. `bmgr backupnow --monitor-verbose --non-incremental`。
4. 对 `/data/data/com.android.localtransport/files/*/_full/<pkg>` 执行 `ls` 和 sentinel grep。

| 模式 | 产品 | E1（exclude） | E2（正向对照） |
|---|---|---|---|
| cloud | `Backup is not allowed`；传输库无该包文件 | `Transport rejected`（`ERROR_PREFLIGHT`）；传输库无该包文件 | `Success`；grep 出 8 个 sentinel（root、file、db、pref、droot、dfile、ddb、dpref） |
| device-transfer | `Transport rejected`（`ERROR_PREFLIGHT`）；传输库无该包文件 | 同产品 | `Success`；同样 8 个 |
| cross-platform(ios，无 params) | `Backup is not allowed`，无解析日志 | `Backup is not allowed`；logcat `Loaded cross-platform configuration … found 0 configured platforms.` | 同 E1 |

逐域对照（r4，`.handoff/logs/2026-11-04-host-s0-03-t006-r4-x-<domain>.txt`，用 bash 脚本生成，所有命令 `exit=0`）：给 8 个域各建一个对照 APK，`allowBackup=true`。各证据文件中 `aapt2 dump xmltree` 回读到的规则正文显示：cloud-backup 与 device-transfer 段各只有一个 `exclude domain="<domain>" path="."`，cross-platform-transfer 段为空；这一行的写法与产品资源中的对应行相同。8 个 APK 的 SHA-256 各不相同。每个 APK 都先补种 sentinel 并 grep 确认 8 个都在，然后按 cloud（`settings get` 回读为空）和 D2D（回读为 `is_device_transfer=true`）各跑一次：

| 排除的域 | cloud 结果 | D2D 结果 | 传输库中缺少的 sentinel |
|---|---|---|---|
| root | Success | Success | 只缺 `root` |
| file | Success | Success | 只缺 `file` |
| database | Success | Success | 只缺 `db` |
| sharedpref | Success | Success | 只缺 `pref` |
| device_root | Success | Success | 只缺 `droot` |
| device_file | Success | Success | 只缺 `dfile` |
| device_database | Success | Success | 只缺 `ddb` |
| device_sharedpref | Success | Success | 只缺 `dpref` |

每次都只少了被排除的那个域，其余 7 个仍在。

判定（plan §5.1）：
- **cloud-backup 与 device-transfer 段的 8 个可观察域：PASS（规则级，证据来自对照 APK）**。
  - r4 逐域对照：在两种模式下，系统都按单行 `exclude` 去掉了对应的那个域。
  - r3 E2：不带规则时，这 8 个域都会被带出。
  - 判断“确实按 device-transfer 执行”的依据：传输参数的回读值（r3、r4）；以及产品 APK（`allowBackup=false`）在 cloud 模式下被 `Backup is not allowed` 拒绝，同一 APK 在 D2D 模式下却会进入预检。这和 Android 12+ 的行为一致：`allowBackup=false` 只拦 cloud，不拦 D2D。logcat 里没有直接打印 destination 的值。
- **产品 APK 本身：只观察到“整包无数据”**。cloud 被 `allowBackup=false` 拒绝；D2D 为 `ERROR_PREFLIGHT`，传输库中没有该包的文件。产品 APK 上没有逐域观察；它与对照 APK 的差别只在于各行合在同一个文件里，以及 `allowBackup` 的取值。
- **external 域：不可观察（BLOCKED）**。sentinel 已写入并 grep 确认，但 E2 不带任何规则时，系统同样没有带出它，所以本路径上无法证明 exclude 生效。目前只有 `BackupRulesTests` 的结构断言覆盖。
- **cross-platform-transfer(platform=ios) 无 params 分支：FAIL**。系统解析了该段，但因缺少 params 计为 0 个已配置平台，规则未被实际接受；结果上没有传输任何数据。
- **第二分支：BLOCKED（等待 D10）**。需要负责人提供并批准 bundleId、teamId、contentVersion。
- **资源处理**：按 §5.1，不删段，也不放宽备份；产品资源本轮不改。

## S0-04 T007：Room 私有库骨架（待宿主验证）

修复轮 2（编排方 2026-11-04 裁决）：`room-runtime 2.8.5` 库 manifest 为 debug/release 合并产物加入 `androidx.room.MultiInstanceInvalidationService`；`CapabilityManifestTests` 将其纳入预期组件集合，保留除启动 Activity 与 DUMP receiver 外全部 `exported=false` 的约束，并显式要求该 service `exported="false"` 且无 `intent-filter`，沿用 fixture 机制新增其 `exported=true` 拒绝负例（覆盖两种 variant）。不修改 manifest 或备份规则；预期该测试类 **8 tests**、全部单元测试 **52 tests**（宿主原 51 + 新增 1），本轮未运行 Gradle，待宿主验证。

负责人 2026-11-04 批准唯一真实实体 `store_metadata`：`key TEXT PRIMARY KEY NOT NULL`、`value TEXT NOT NULL`，无业务列。`FineCoachDatabase` 从 **version 1** 开始，`exportSchema=true`。Room schema version 与 Core Data V1～V6、FCBK/FCPA container/payload version **独立**，互相不映射。依据：ADR-001 §3、§5；S0 spec FR-040～042、FR-121。

`FineCoachDatabaseFactory.create(context)` 通过 application context 的 `getDatabasePath("finecoach.db")` 建 CE 私有磁盘库，拒绝 device-protected context。首次实际打开时，Room `onCreate` 在建库事务中插入 `created_at`，值为 `Instant.now().toString()` canonical UTC 字符串；关闭重开不重写。工厂不自动接入 app shell；调用者负责 off-main 执行同步 DAO 与关闭库。DAO 只有按 key 查询和冲突 ABORT 的插入，不用 replace 覆盖。version 1 尚无升级路径，保留 Room 默认缺迁移拒绝；不注册破坏性回退、预装库、自定义 open helper 或主线程查询豁免。

### 字段策略与延期边界

下列章节均指 [`contracts/payload-schema.md`](../../specs/007-android-port/contracts/payload-schema.md)。`StorageValueConverters` 仅独立测试，**不**注册在数据库或实体上；真实实体两列均为 String。私有表示不是 wire codec，后续实体和 codec 按所属切片实施。

| 类型 / 关系 | 本轮私有值策略 | 契约依据与后续边界 |
|---|---|---|
| 稳定 UUID / 关系 | `UUID` 输出小写 canonical；读取只接受完整分组形式，接受大小写。关系按稳定 ID 显式表达，不依赖行号；本轮没有关系表 | §1、§4 Scalar wrappers、§5 JSON 通用差异、§6 引用完整性、§7；FCBK/FCPA wire 大小写分别对齐 golden，不把私有小写写法当 wire 决定 |
| Decimal | `BigDecimal` + plain canonical 字符串；无 Double/Float。去前导/尾随零，负零为 `0`，按数值比较无精度损失，scale 不保留；拒绝指数、加号、逗号、NaN、内部空白，canonical 上限 64 KiB | §5 DecimalValue。接受首尾空白、`.5`、`1.`、前导零；Android 私有 BigDecimal 不冒充 Foundation Decimal 的完整数值范围兼容证明 |
| UTC instant | `Instant.toString()` / canonical `Z` 字符串，私有往返保留全部纳秒，包含毫秒和 epoch 前值；非 canonical 输入拒绝 | §5～§7：FCBK writer 无小数秒；FCPA golden 是毫秒样本，更广精度/截断规则未确认。因此本轮不实现 wire 截断或 decoder 接受范围，不能以私有纳秒往返声称互通通过 |
| LocalDate / LocalTime | 与 Instant 独立；私有日期为有效 Gregorian `yyyy-MM-dd`（year 1～9999）；时间为 `HH:mm`，拒绝非零秒/纳秒，避免静默截断，不作时区换算 | §3 LocalDate / LocalTime、§5～§7；FCBK wire 是整数字段对象，FCPA local date 是 canonical 字符串；更宽日历范围与 wire 验证留后续 codec |
| null / 缺失 | 当前两列 NOT NULL；转换器非 nullable。未来实体按字段 Optional 映射，不把缺失、null、默认值统一改写 | §1、§5 JSON 通用差异、§7；nil 写出省略，manifest 部分 count 历史缺省与版本拒绝分别处理 |
| enum / Set | 暂无实体列或集合转换器；后续按明确 raw value/associated-value 表达 enum，Set 按集合相等比较，不依赖枚举序号或遍历次序 | §4、§5、§7；未知值和引用校验按各 wire/Domain 的实际规则，不额外猜测接受或拒绝 |

后续实体延期清单（按 §1 section roster；此表不预建表或列）：

| 切片 | 延期记录 / 关系 |
|---|---|
| S1 起 | Student、ExerciseCatalogItem、ExercisePreference、ExerciseNameClaim、Session（BackupSessionRecord）、SessionExercise、TrainingSet、SessionSection、CoursePackage、CreditAdjustment；按 §3 精确字段/稳定 ID/关联约束落表 |
| S2 | Appointment、RecurrenceSeries；日历值独立于 UTC instant |
| S3 | BodyMetricDefinition、BodyMeasurement 及趋势所需派生行为；不预留统计列 |
| 所属业务切片（S1 起） | TrainingTemplate（BackupTemplateRecord）、TemplateExercise、TemplatePlannedSet、BackupSettingRecord；具体归属待对应 spec，不在 S0 扩展 |
| S4 | ShareReport（BackupShareReportRecord）、ShareReportModuleSelection；BackupManifest 与全部 FCPA Archive DTO/内嵌记录按 §1～§3 实现 codec/映射，不假定每个 DTO 都需独立 Room 表 |

FR-121 种子仅可使用上述批准骨架；本轮未做 seed、组件展示或业务流程，未新增用户交互，entry/layout map 无新增行。没有新增或移除既有 UI/备份规则。新增存储骨架、值边界与测试，原有 `s0Room` 未实现状态保留：plan §4 的 Room 成功条件含 FR-041，tasks T007 明确完整 gate 在 T008 就绪后执行；MigrationTestHelper、synthetic V1/V2 schema 与缺迁移证明留 T008。

### Gradle / schema 与宿主机验证

使用已批准 catalog 的 KSP **2.3.13**、Room runtime/compiler/testing **2.8.5**；只在 app 应用 `com.google.devtools.ksp`，compiler 走 `ksp`，testing 走 `testImplementation`。未应用 `androidx.room` plugin，未增加其他直接依赖。按 [Room 2.8.5 官方 compiler options](https://developer.android.com/jetpack/androidx/releases/room#compiler-options) 使用 `room.schemaLocation`、`room.incremental=true`、`room.generateKotlin=true`；schema 路径经 `CommandLineArgumentProvider` 声明相对路径输入。

schema export 目录为 `android/app/schemas/`，宿主已生成真实产物 `com.ignacioli.finecoach.storage.FineCoachDatabase/1.json`（version 1、唯一实体 `store_metadata`），**没有手写 JSON/identityHash**；保留待审查提交。AGP 9.3.1 不将 `test` 源集 assets 合并给本地单元测试，宿主确认没有 `mergeDebugUnitTestAssets` task。本轮移除 `test.assets.srcDir("schemas")` 与不存在的 merge task 依赖；测试仅通过 `finecoach.roomSchemaDirectory` 读取磁盘 export，缺失即失败，仍检查 version、非空 identityHash、唯一实体、字段类型/非空约束/主键，以及空 views/foreignKeys/indices。没有放宽 schema 内容断言；只移除无效的 assets 传递机制与副本相等断言。

沿用本文获批 JDK21/SDK/缓存设置，cwd=`android/`：

```sh
./gradlew assembleDebug lint
./gradlew :app:testDebugUnitTest --tests '*RoomSkeletonTests' --tests '*StorageValueTests' --tests '*StoragePrivacyTests' --rerun-tasks
./gradlew :app:writePrivacyDependencyGraph
```

定向预期 **18 tests**：RoomSkeletonTests **5**（磁盘写入/重开/创建时间稳定、事务失败回滚并重开、重复 key 拒绝、实际表列约束、磁盘 export 内容）；StorageValueTests **10**（UUID 正/负例、Decimal 精度/规范化/边界/非法输入、Instant 纳秒往返/非法输入、日历值往返/非法日期/非法时间）；StoragePrivacyTests **3**（生产源码及构建配置无存储放宽/二进制浮点、CE 私有 databases 文件且排除 cache/external/DE、拒绝 DE context）。要求 JUnit XML 非空且实际 **18**、0 failures/errors/skips；结果在 `app/build/test-results/testDebugUnitTest/`、HTML 在 `app/build/reports/tests/testDebugUnitTest/`。修复前编排方宿主反馈 `assembleDebug lint` 通过（3m20s），定向 17/18 通过，唯一失败是 schema assets 缺失。本修复轮按要求未运行 Gradle、模拟器或 xcodebuild，修复后测试待宿主验证，不记录 PASS，不勾选 T007。

### 修复轮 1：完整依赖图与 T008 API 预核实

磁盘产物另显示 Room 省略空 `views`、`foreignKeys`、`indices`；缓存 `room-migration-jvm-2.8.5.jar` 的 `DatabaseBundle` / `EntityBundle` 默认构造函数字节码确认这些字段默认 `emptyList()`。断言按该格式接受字段省略或显式空数组，仍拒绝非空数组、null 和非数组值；version、identityHash、实体、字段与主键断言不变。这修复了原 assets 异常遮住的 JSON 字段读取问题。

`writePrivacyDependencyGraph`、生成器与 `DependencyPolicy.scopes` 从 8 扩为 11 个 scope，新增 `kspDebugKotlinProcessorClasspath`、`kspReleaseKotlinProcessorClasspath`、`kspDebugUnitTestKotlinProcessorClasspath`，将构建时执行的 Room processor 与传递项纳入精确集合相等检查。生成器支持 `--resolved-report` 读取宿主现有 ResolutionResult 库存（8 scopes，744 行含 8 条 scope header），另外解析本轮 3 份 KSP 树报告；树坐标解析规则不变。unit-test KSP 报告明确 `No dependencies`，允许此 scope 为 0，但仍要求 Gradle 报告出现该 scope；没有手工删条目。

复跑生成（不运行 Gradle），从产品根执行：

```sh
node android/dependency-allowlist/generate-resolved.mjs "$HOME/.cache/finecoach-android/deps-2026-11-04-t007" --resolved-report android/app/build/reports/s0/privacy/resolved.txt
```

生成器在写入前拒绝新的 alpha/beta/rc/SNAPSHOT selected 坐标，只有负责人此前接受的两个 jetifier beta 坐标可通过。原 3 条负责人接受注释完整保留（第三条说明 aapt2-proto alpha 仅 requested、selected 为稳定版本）。本轮没有新增未批准预发布 selected 坐标。相对当前 HEAD，白名单 **686 → 806 条 scoped 坐标（+120）、292 → 330 个唯一坐标（+38）**；各 scope：app classpath 6、debugAndroidTestRuntime 21、debugCompile 93、debugRuntime 108、debugUnitTestRuntime 176、releaseCompile 92、releaseRuntime 107、kspDebug 35、kspRelease 35、kspDebugUnitTest 0、root classpath 133。新增 Room/SQLite/KSP/serialization/annotation-experimental 稳定版本由编排方宿主核实；本轮不改版本。PrivacySourceScanTests 仍 **10 tests**，上述 Room/storage 定向仍 **18 tests**，合跑两组预期 **28 tests**。

在宿主缓存 `gradle-home/caches/modules-2/files-2.1/androidx.room/room-testing-android/2.8.5/` 仅发现 POM/module/AAR，无 sources JAR。通过 JDK21 `javap -p -c` 核实对应 Gradle transform 的 `b467ce895d42c5756fe14ff54cc740bb/transformed/room-testing/jars/classes.jar`（位于同一缓存 `caches/9.7.0/transforms/`）：

- Android `MigrationTestHelper` **没有直接读 schema 文件目录、绕开 assets 的构造函数**。现有重载使用 `Instrumentation + assetsFolder: String (+ SupportSQLiteOpenHelper.Factory)`，或 `Instrumentation + databaseClass: Class<out RoomDatabase> (+ specs: List<AutoMigrationSpec> + openFactory)`。
- 带 `File` 的重载参数为 `Instrumentation, file: File, driver: SQLiteDriver, databaseClass: KClass<out RoomDatabase>, databaseFactory: () -> RoomDatabase, autoMigrationSpecs: List<AutoMigrationSpec>`。前四项必需；后两项的 Kotlin 默认值分别为生成的 DB implementation factory 和空列表。这里 `file` 是**数据库文件**，不是 schema 目录。
- 字节码显示该重载按 databaseClass qualified name 设置 assetsFolder；`SQLiteDriverMigrationTestHelper.createDatabase/runMigrationsAndValidate` 仍调用父类 `loadSchema`，后者依次尝试 instrumentation context 与 target context 的 `assets.open("<assetsFolder>/<version>.json")`。此 API 不能解决本轮本地 test assets 缺失。

以上仅为缓存 API/字节码核实，未证明 Robolectric helper 运行兼容性。T008 仍需解决 synthetic schema assets 的有效接入；本轮不实现 T008、不改依赖、不引入替代 harness。完整 `s0Room` 与真实 schema 提交仍待后续。

## S0-04 T008：synthetic migration instrumentation

### 1. Robolectric 探测失败，批准改为 instrumentation（2026-11-05）

宿主机运行原 `RoomTestAssetProbeTests`：**1 test、1 failure**。对 `com.ignacioli.finecoach.SyntheticMigrationDatabase/1.json`，`instrumentation.context` 与 `targetContext` 都抛 `FileNotFoundException`，未取得 Robolectric 下 test assets 可读证据。按 plan §3.2 停止后，负责人于 **2026-11-05 批准**将同一迁移框架的两个用例改在宿主机模拟器上用 instrumentation 运行；使用 `adb shell am instrument`，不用 `connectedDebugAndroidTest`。

删除 JVM probe、`src/test/assets/` 的两份手写 synthetic JSON，将 `RoomMigrationHarnessTests` / `SyntheticMigrationDatabase` 移至 `src/androidTest/java/com/ignacioli/finecoach/`。不改 app 数据库、app schema 或 UI；entry/layout map 无新增行。

### 2. serialization AbstractMethodError，批准统一到 1.8.1（2026-11-05）

首轮宿主 `assembleDebug assembleDebugAndroidTest` 通过并生成 synthetic schema，但 QPR2 `am instrument` 为 **Tests run: 2, Failures: 2**，两例均抛 `AbstractMethodError: kotlinx.serialization.internal.GeneratedSerializer.typeParametersSerializers()`。宿主 `dependencyInsight` 确认：navigation 2.10.2、lifecycle 2.11.0 使应用 runtime 经 BOM 选到 serialization core 1.7.3；Room 2.8.5 的 room-migration 带入 json 1.8.1，androidTest consistent resolution 将 core 限在 1.7.3，导致二进制不兼容。

负责人于 **2026-11-05 批准**应用统一升到 kotlinx-serialization **1.8.1**。catalog 显式声明 1.8.1，app 使用 `implementation(platform(libs.kotlinx.serialization.bom))`；只对齐版本，不新增 core/json 功能依赖，不改测试语义、schema 或 UI。后续宿主确认应用 `debugRuntimeClasspath` 的 serialization core 已选到 1.8.1，QPR2 两例通过。

### 3. lint/merge implicit dependency 与修复轮 4（2026-11-05）

随后 lint model 报读取 synthetic schema 缺少 KSP producer 依赖。修复轮 3 尝试通过 `files(schemaDirectory).builtBy(androidTestKspTasks)` 传递依赖；宿主 clean 构建仍失败：`mergeDebugAndroidTestAssets` 读取被 `kspDebugAndroidTestKotlin` 声明为输出的 `app/schemas-synthetic/`，但 AGP 的 `assets.srcDir` 未保留该 producer 依赖。

修复轮 4 按编排方裁决，将 `schemas-synthetic` 改为普通入库源目录：删除 synthetic KSP task 的 `outputs.dir(schemaDirectory)`、`androidTestKspTasks` 集合和 `builtBy` 接线，在 `androidTest` 源集直接使用 `assets.srcDir("schemas-synthetic")`。KSP 仍通过任务级 `commandLineArgumentProviders` 分别写入 `schemas-synthetic/`（`*AndroidTestKotlin`）和 `schemas/`（其余 task）；不添加 merge/lint 的手写 `dependsOn`，不关闭 Gradle 校验。

`room-testing` 使用 `androidTestImplementation`，`kspAndroidTest` 使用现有批准版本的 `room-compiler`。`writePrivacyDependencyGraph`、`generate-resolved.mjs` 与 `DependencyPolicy.scopes` 已同步增加 `app:kspDebugAndroidTestKotlinProcessorClasspath`（共 **12 scopes**），新 processor scope 不允许空图。白名单已从宿主 ResolutionResult 报告全量生成，覆盖 **860 条 scoped 坐标**（报告另含 12 条 scope header，共 872 行）、327 个唯一坐标；serialization selected 版本同步为 1.8.1。保留原来源注释和 3 条已接受预发布注释，没有手工删坐标或新增预发布例外。

生成命令从产品根执行：

```sh
node android/dependency-allowlist/generate-resolved.mjs android/app/build/reports/s0/privacy --resolved-report android/app/build/reports/s0/privacy/resolved.txt
```

### 4. 修复轮 4 宿主机 clean 验证结果（2026-11-05）

以下为编排方提供的宿主机及 QPR2 模拟器结果，本次 README 收尾未复跑：

- clean 后 `assembleDebug`、`assembleRelease`、`assembleDebugAndroidTest`、`lint` 全部通过。
- 应用 APK 中 synthetic schema **0 条**，测试 APK 中 **2 条**。
- 卸载重装后，QPR2 `am instrument` 为 **`OK (2 tests)`**。
- `s0Room` **18/18**；全部单元测试 **52 tests，0 failure/skip**；`s0EnvironmentSmoke` 通过。
- 依赖白名单覆盖 **12 scopes、860 条 scoped 坐标**，精确集合检查通过。

原始日志位于 `.handoff/logs/2026-11-05-host-s0-04-t008-fix4-*`，仅存本机，不入仓。上述结果证明本轮构建、打包隔离和迁移框架验证通过；设备部分是 CP1 的宿主机系统证据，不代表 app 业务库经历过升级。

### Synthetic schema 来源、隔离与已知限制

synthetic schema 由 **Room 2.8.5 compiler 经 KSP 2.3.13 生成**，不沿用手写 bundle 或人工 identityHash。源码只有虚构 `synthetic_probe`：V1 为 `id`、`label`；V2 增加 `fictional_rank INTEGER NOT NULL DEFAULT 7`，与 app 的 `store_metadata` 无关。已生成并作为入库文件保留：

- `app/schemas-synthetic/com.ignacioli.finecoach.SyntheticMigrationDatabaseV1/1.json`
- `app/schemas-synthetic/com.ignacioli.finecoach.SyntheticMigrationDatabase/2.json`

V1/V2 是同一测试编译内的两个数据库类，Room 按各自 qualified class name 建目录；`v1Helper` 用 V1 assetsFolder 建旧库，`helper` 用 V2 assetsFolder 迁移并校验目标 schema，操作同一个测试数据库文件。不手工复制、改名或合并 compiler export。synthetic Kotlin 与 schema 仅在 androidTest；应用 schema 仍只有 `app/schemas/com.ignacioli.finecoach.storage.FineCoachDatabase/1.json`。

测试使用 `InstrumentationRegistry.getInstrumentation()` 和 `MigrationTestHelper`；每个用例先显式打开 **instrumentation.context（测试 APK）** 内的两份 schema，要求非空，再由 helper 解析 bundle、建库与校验，避免 target APK fallback 掩盖 assets 错误。

**已知限制：**`schemas-synthetic` 没有声明为 KSP 输出，增量构建可能把过期的 JSON 打进测试 APK。schema 有变化时，先 **clean 构建一次**，再审查并提交 JSON 差异，不能只改数据库定义而保留旧 JSON。JSON 过期时，`MigrationTestHelper` 校验会失败，不会悄悄通过。

### 宿主命令与预期

沿用本文批准的 JDK21、SDK、缓存配置，cwd=`android/`。JVM 部分：

```sh
./gradlew :app:s0Room
```

预期 **18 tests**：RoomSkeletonTests **5**、StorageValueTests **10**、StoragePrivacyTests **3**。`s0Room` 仍是独立 `Test` task，复用 AGP debug test 的 classpath、编译产物、JDK/JVM 参数、system properties 与 working directory；固定三类，每次执行且不用结果缓存。finalizer 保留拒绝 skip/失败、空 XML/suite、缺失/重复/意外 suite、failure/error/skip 与不一致 testcase 节点的检查。XML：`app/build/test-results/s0Room/`；HTML：`app/build/reports/tests/s0Room/`。

设备部分不建 Gradle gate task。**仅连接一个指定模拟器**，先记录 serial、API、build 与 SQLite provider 信息；按顺序运行：

```sh
adb devices -l
adb shell getprop ro.build.version.sdk
adb shell getprop ro.build.fingerprint
./gradlew assembleDebug assembleDebugAndroidTest
shasum -a 256 app/build/outputs/apk/debug/app-debug.apk app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
unzip -l app/build/outputs/apk/debug/app-debug.apk
unzip -l app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb install -r -t app/build/outputs/apk/debug/app-debug.apk
adb install -r -t app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w -r -e class com.ignacioli.finecoach.RoomMigrationHarnessTests com.ignacioli.finecoach.test/androidx.test.runner.AndroidJUnitRunner
```

预期文字结果 **`OK (2 tests)`**、0 failures/errors/skips，输出必须非空；不能只看 adb 退出码。核对测试 APK 内有上述两份 JSON，应用 APK 内无 synthetic schema。helper 使用 Android framework SQLite（`FrameworkSQLiteOpenHelperFactory`）；执行记录保留 APK digest、serial/API/build、provider 与完整 instrumentation 文字结果。

两个用例语义保持：

- helper 创建 V1 并写虚构行 `(41, fictional-comet)`；提供 `Migration(1,2)` 后 `runMigrationsAndValidate(..., 2, true, migration)`，校验 V2 schema 与无额外表，原行保留且 `fictional_rank=7`。
- 独立 V1 不提供 migration 打开 V2，必须抛明确缺迁移异常；原文件仍在，只读确认 version 1、原行和原两列保留。不启用 destructive fallback。

Room helper 的 assetsFolder 构造函数（deprecated）、`createDatabase`、`runMigrationsAndValidate` 及其优先读取 instrumentation assets 的实现已由缓存 Room 2.8.5 字节码核实；实际编译、KSP 输出、打包与设备执行结果见上文修复轮 4 宿主记录。

## S0-07 T009：后台遮挡与范围边界（待宿主验证）

### 实现与边界

基点 `c7ba2a0`，分支 `feat/android-s0-infrastructure`。本轮仅 T009，不执行 T010，不改规格复选框、不 commit。新增 `PrivacyCoverPolicy`，由 `MainActivity` 的 `onCreate/onPause/onResume/onDestroy` 驱动：

- API 33+：`onCreate` 调用 `Activity.setRecentsScreenshotEnabled(false)`。不添加应用内遮罩；该接口只限制最近任务表现，不禁止普通截屏，见 [Activity API](https://developer.android.com/reference/android/app/Activity#setRecentsScreenshotEnabled(boolean))。
- API 31/32：`onPause` 在每个已登记窗口的 `decorView` 最上层同步添加不透明、可拦截触摸的全窗口 `FrameLayout`；尺寸 `MATCH_PARENT`，当下按 decor 尺寸 measure/layout，随后正常布局继续维护尺寸。背景取现有 `android.R.attr.colorBackground`，无新 token。`onResume` 移除；`onDestroy` 解除登记并清理。重复登记/暂停不叠加，暂停期间新登记的窗口立即遮挡。
- 弹层是独立窗口，Activity 遮罩不能跨窗口覆盖。debug Compose `Dialog` 从 `LocalView.current.parent as DialogWindowProvider` 获取公开 `window`，在 `DisposableEffect` 登记/解除；窗口本身各有遮罩，Activity 同时遮挡。依据 [DialogWindowProvider](https://developer.android.com/reference/kotlin/androidx/compose/ui/window/package-summary)。**后续任何独立窗口 Dialog/BottomSheet 都必须在显示前接入同一 registerWindow/unregisterWindow 协议**；同窗口 sheet 由 Activity decor 遮罩覆盖。本轮没有 BottomSheet 依赖或实现，不声称已验证未来弹层，也不使用隐藏 WindowManager API 遍历窗口。系统文件选择器不属于本轮壳。
- 不设置 `FLAG_SECURE`。JVM 检查源码、两种 merged manifest 和实际 Activity flags；它们不证明系统缩略图、普通截屏或 OEM 时序。同步 View 添加是否赶在系统 snapshot 前，必须由 T010 分 API 验证；暴露即 FAIL，不以 JVM green 抵消。

main manifest 未改；debug manifest 仅新增 `.S0DebugApplication`，它实现 main 的 `ShellContentProvider`，通过现有 MainActivity 内容入口显示样例。release 使用默认 Application，保留原空壳，无新 Activity/intent-filter/权限，不改备份规则。release APK DEX 与 manifest 有样例隔离断言。app Gradle 仅新增 debug APK artifact 输入，以及 shared/fixture/schema 扫描输入，不新增依赖、版本、测试 gate 或白名单例外。

### 样例 anatomy、testTag 与 entry/layout map

这是 T009 明确授权的临时基础设施样例，非正式 Feature UI / catalog。沿用已有全屏壳，补登记测试 anatomy（C：批准测试样例的文字化记录）；不改变正式设计系统。结构：壳 Column → 固定虚构 sentinel → 打开弹层 → probe → 计数；独立 Dialog Column → sentinel → probe → 计数 → 关闭。初始弹层关闭、共享内存计数 **0**；probe 每点一次 +1，恢复后第一次为 **1**；不读写数据库、文件、SavedState 或业务数据。返回/关闭弹层不重置计数，重新创建 Activity 归零。普通壳和弹层的 probe 共享同一计数。

| testTag | 元素 / 初始值 |
|---|---|
| `s0-privacy-shell` | 全屏壳容器 |
| `s0-shell-sentinel` | `S0SENTINEL-recents` |
| `s0-open-dialog` | 可见按钮「打开虚构弹层」；弹层初始关闭 |
| `s0-probe` | 可见按钮「交互探针 +1」 |
| `s0-probe-count` | `计数：0` |
| `s0-privacy-dialog` | 弹层容器；初始不存在 |
| `s0-dialog-sentinel` | `S0SENTINEL-recents-dialog` |
| `s0-dialog-probe` | 弹层可见按钮「交互探针 +1」 |
| `s0-dialog-probe-count` | 打开时 `计数：0`（未点 probe 的情况下） |
| `s0-close-dialog` | 可见按钮「关闭弹层」 |
| 各按钮 tag + `-label` | 按钮内文字，非额外交互入口 |

Native 遮罩使用 View tag `s0-privacy-cover`，不是 Compose testTag，不是前台控制。所有样例交互来自 `src/debug/java/com/ignacioli/finecoach/S0DebugApplication.kt` 的 `PrivacySample/SampleButton`。root semantics 开启 `testTagsAsResourceId`，便于宿主在 UI hierarchy 文字中定位；不使用坐标猜测或长按入口。

| 屏幕 → 可见控件 → testTag | 是否改数据 | 宽度由谁撑满 |
|---|---|---|
| debug 壳 → 打开虚构弹层 → `s0-open-dialog` | 仅内存弹层状态 | 壳 Column 撑满屏幕安全区；SampleButton `fillMaxWidth` 撑满其 padding 后内容区 |
| debug 壳 → 交互探针 +1 → `s0-probe` | 仅内存计数；无持久化 | 同上 |
| debug 弹层 → 交互探针 +1 → `s0-dialog-probe` | 同一内存计数；无持久化 | Dialog 默认平台宽度；Column `fillMaxWidth`，SampleButton 撑满 padding 后内容区 |
| debug 弹层 → 关闭弹层 → `s0-close-dialog` | 仅内存弹层状态 | 同上 |

样例触控高度至少 48dp，文字采用 Compose BasicText 默认排版和主题文字色，不引入 DS token。各按钮的宽度与同容器 sentinel 内容宽度相等，有 Compose 断言。

五行执行记录：

1. 分类与依据：C，补齐 T009 已批准测试壳的 anatomy 与 map；正式设计不变，来源 tasks T009、plan §5.1；不是 S0-08 组件设计审批。
2. 范围：PrivacyCoverPolicy（main 私有策略）、debug 专用样例，复用壳与平台背景；没有新增正式 DS 组件或 Feature 页面。
3. 设计决定：沿用本任务批准的默认背景、固定虚构 sentinel、可见 probe；正式 token/catalog 仍留 S0-05/S0-08，不回写 design/Penpot。
4. 实现与检查：生命周期/原生层级、真实 API 调用 shadow、弹层恢复与交互/宽度断言、数据/范围负例；map 见上。无截图查看或 baseline 修改。
5. 结果：2026-11-05 宿主机 `assembleDebug`、`assembleRelease`、`assembleDebugAndroidTest`、`lint` 通过；`:app:testDebugUnitTest --rerun-tasks` 共 **85 例，0 failure/error/skip**，其中 PrivacyCoverTests 11、FictionalDataPolicyTests 10、ScopeBoundaryTests 12；`s0Room` **18/18**；`s0EnvironmentSmoke` 通过，日志 `.handoff/logs/2026-11-05-host-s0-07-t009-unit.log`。Robolectric 4.17 运行时所需 SDK jar（android-all-instrumented `12-robolectric-7732740-i7`、`12.1-robolectric-8229987-i7`、`13-robolectric-9030017-i7`）在宿主机按 Maven Central 的 sha512 与 sha1 核对后放入 `~/.m2`；首次失败是 Maven Central 对宿主 IP 限流（HTTP 429），不是代码问题。此前缓存 Kotlin 2.4.21 + 对应 Compose compiler、JDK21、SDK37 `android.jar` 的定向源码编译退出 0（缓存 classpath，非 Gradle resolved classpath 验证），保留 Compose v1 test rule 与 Drawable opacity 两个 deprecated 警告。T010（API 31/32/33+ 系统缩略图）仍 **PENDING**；JVM 测试不证明系统缩略图；未视觉验证，未完成 CP1。

### 已知残留

- API 31/32 分屏失焦也走 `onPause`，会遮住仍可见的窗口，属于按规格行为。
- 未调用 `registerWindow` 的独立窗口不会被遮。
- pause 期间关闭 Dialog 的路径没有专门测试。

### 三个测试类与宿主命令

沿用本文批准 JDK21/SDK/cache，cwd=`android/`，由编排方在宿主机运行：

```sh
./gradlew assembleDebug assembleRelease lint
./gradlew :app:testDebugUnitTest --tests '*PrivacyCoverTests' --tests '*FictionalDataPolicyTests' --tests '*ScopeBoundaryTests' --rerun-tasks
```

预期 **33 tests，0 failures/errors/skips**，JUnit XML 必须非空，核对实际 testcase 数；报告 `app/build/test-results/testDebugUnitTest/`，HTML `app/build/reports/tests/testDebugUnitTest/`。这只是 targeted，不是完整 G8 或 T010 PASS。使用现有 merged-manifest/resource/APK artifact 接线；缺产物/缺目录必须失败，不能 fallback 跳过。单元测试源码按 compileSdk **android.jar** 编译，Robolectric android-all 只用于执行，不作为编译 API 替身。

- `PrivacyCoverTests`：**8 方法 / 11 executions**。33+ 真实 Activity API 被调用一次且参数 false；31/32 均不调用（2）；31/32 pause 壳顶层全尺寸不透明 cover、resume 移除并 probe 0→1（2）；31/32 独立 Dialog 与壳同时覆盖、恢复后弹层 probe 可点且关闭可达（2）；31 暂停后新登记窗口立即覆盖、重复登记不叠加、注销/销毁清理；可见入口和宽度；生产源码与 debug/release merged manifest 无 secure 标志及窗口 flag 检查；release APK/manifest 无 debug 壳与 sentinel。API call 用 `ShadowActivity` 子类观察，未用测试替身替代策略。
- `FictionalDataPolicyTests`：**10 方法**。当前/未来 fixture 与 inline seed 发现及声明；shared 全部向量与其余 fixture；debug 固定 sentinel；打包 debug DEX sentinel 与 assets/raw 数据；synthetic schema 仅结构；拒绝无声明/变更旧 fixture；拒绝向量缺 tag；拒绝 sentinel/敏感形状文件名与非保留域联系信息；拒绝 sentinel 漂移/声明缺失；临时新增 seed 目录自动纳入。现有 5 个 policy API 片段 fixture 用完整 SHA-256 登记为无人物数据的虚构负例，变更后必须重新声明。新数据文件内含 `fictional-data` 声明，二进制 fixture 用同目录 `fictional-data.txt`；向量要求 `meta.tags` 含 `fictional-data`。扫描是机械声明/命名/固定内容检查，不能证明现实来源，负责人仍须声明来源，独立复核仍待执行。
- `ScopeBoundaryTests`：**12 方法**。生产 source set 与 merged resources；两种 merged manifest；拒绝静态 shortcut XML；拒绝空 shortcuts.xml；拒绝动态（含 Compat/alias）注册；拒绝 pinned 注册；拒绝 shortcut metadata；拒绝专属 intent-filter；拒绝 Assistant/App Actions source/metadata；拒绝 S1～S5 literal/间接/typed 路由；拒绝通知/小组件/容器 codec/分享/业务入口；允许通用 DS 演示文字。产品 route 当前只允许 `placeholder`；未来获批 S0 catalog 路由须在对应任务明确登记，不凭名称推断业务获批。系统 filter 仅 launcher 与已存在 ProfileInstaller 操作；component/权限仍复用 CapabilityPolicy 精确集合。所有禁止项均有受控负例。

源码策略覆盖当前 Kotlin/Java/XML 注册方式，不能推断任意混淆、反射或语义等价实现；后续新增实现必须扩展相应受控负例，不能把扫描当作完整安全证明。当前未实现 seed 数据清单；未来 assets/resources/fixture/seed 目录会自动发现，inline seed 代码必须带虚构声明，不代表批准新增 S1 业务种子。

### T010：宿主 API 31 / 32 / 33+ 操作与文字证据（已自动执行）

每个 API 单独执行，普通壳/弹层都做。宿主先核实唯一指定设备及准确输入，未填即 BLOCKED；以下变量由宿主设置，不是已有环境事实：`S0_ANDROID_SERIAL`、`S0_ANDROID_APK`、`S0_ANDROID_PACKAGE`（核实为 `com.ignacioli.finecoach`）、`S0_ANDROID_COMPONENT`（核实为 `com.ignacioli.finecoach/.MainActivity`）、`S0_HOST_EVIDENCE`（独立且已存在的本机证据目录）。只对虚构 debug 包操作。

```sh
adb version
adb devices -l
adb -s "$S0_ANDROID_SERIAL" shell getprop ro.build.version.sdk
adb -s "$S0_ANDROID_SERIAL" shell getprop ro.build.fingerprint
shasum -a 256 "$S0_ANDROID_APK"
adb -s "$S0_ANDROID_SERIAL" install -r "$S0_ANDROID_APK"
adb -s "$S0_ANDROID_SERIAL" shell am start -W -n "$S0_ANDROID_COMPONENT"
```

记录 HEAD 与本轮 diff（未 commit，HEAD 本身不足以标识 APK）、APK 路径/SHA-256、serial/API/build、applicationId、component、工具版本、证据目录、完整命令、每条退出码和操作顺序。安装须 `Success`、启动须 `Status: ok`。图像仅负责人查看，agent 只读取文字判定。

1. **普通壳**：新 Activity 会话确认 `s0-probe-count=计数：0`、普通 sentinel 可见。执行下面 HOME→最近任务序列，由负责人查看实际卡片；不能只凭截图文件存在判断遮挡。
2. **恢复**：负责人点击该最近任务卡片。确认遮罩移除，点击 `s0-probe` 一次，文字结果 0→1；记录 `coverRemoved=true`、`probeBefore=0/probeAfter=1`。再做一次 HOME→最近任务→卡片恢复，确认仍无 sentinel 暴露。
3. **弹层**：先结束并重新启动这个仅虚构样例的 Activity 会话（不 clear 数据），确认计数 0；点击可见 `s0-open-dialog`，确认弹层 sentinel 可见。执行同一 HOME→最近任务→卡片恢复；确认两层均无 sentinel 暴露、恢复后弹层仍在，点击 `s0-dialog-probe` 一次见 0→1，再点 `s0-close-dialog` 关闭并确认壳显示 1。重复一次最近任务序列。需要独立新会话时用下面 force-stop，仅限本轮 debug 样例，记录实际执行。

```sh
adb -s "$S0_ANDROID_SERIAL" shell input keyevent KEYCODE_HOME
adb -s "$S0_ANDROID_SERIAL" shell input keyevent KEYCODE_APP_SWITCH
# Owner opens the actual card to resume; no guessed tap coordinates.
# Optional isolated sample restart before the dialog sequence:
adb -s "$S0_ANDROID_SERIAL" shell am force-stop "$S0_ANDROID_PACKAGE"
adb -s "$S0_ANDROID_SERIAL" shell am start -W -n "$S0_ANDROID_COMPONENT"
```

可用以下命令留可交互文字证据（每步保留各自输出，probe 前后不能只记最终值）：

```sh
adb -s "$S0_ANDROID_SERIAL" shell uiautomator dump /data/local/tmp/s0-privacy-window.xml
adb -s "$S0_ANDROID_SERIAL" shell cat /data/local/tmp/s0-privacy-window.xml
```

4. **前台截屏**：每个 API 在前台普通壳和弹层状态分别保存一张 PNG（下面 `foreground.png` 替换为各状态独立文件名，不以 sentinel/人员名命名）。保留退出码、非空文件、PNG 签名及负责人正常内容判定。可以另存最近任务图片作为负责人证据，但 agent 不打开图片。

```sh
adb -s "$S0_ANDROID_SERIAL" exec-out screencap -p > "$S0_HOST_EVIDENCE/foreground.png"
test -s "$S0_HOST_EVIDENCE/foreground.png"
od -An -tx1 -N8 "$S0_HOST_EVIDENCE/foreground.png"
```

预期签名 `89 50 4e 47 0d 0a 1a 0a`。每个 API/状态记录：FR-070（33+）或 FR-071（31/32）的 `sentinelVisible=false`、恢复的 `coverRemoved=true`/probe 前后值，FR-072 的 `foregroundCaptureNormal=true`，证据文件名、负责人/时间。sentinel 暴露、遮罩残留/点击无效或前台截屏遮黑/失败记 FAIL；设备/卡片/有效图片缺失记 BLOCKED。以上为原人工操作流程；负责人 2026-11-05 批准的自动化方法及实际结果见下文，以自动恢复和像素统计取代人工点卡片及逐图判定。JVM 测试不替代系统快照验证；同一问题两次失败停止并保留失败证据。

#### T010 宿主自动验证结果（2026-11-05）

负责人 2026-11-05 决定：不涉及真实功能/视觉的验证全部自动化。本记录由编排方提供宿主结果，当前 T013 agent 未重跑设备验证、未读取图片，不将这些结果外推为真实功能、视觉验收或 T013 修改后 APK 的运行证明。

- 方法：root 模拟器读取系统任务快照 `/data/system_ce/0/snapshots/**/<taskId>.jpg`，确定性统计每行相邻像素 `|ΔRGB|>40` 的变化次数，次数 ≥6 记为文字行。对照组为同界面前台截图缩放至快照尺寸，必须检出文字行。恢复使用 `am start` 切回已有任务，替代点击最近任务卡片。
- 结果：API 36.1（QPR2）、31、32 的普通壳与弹层快照文字行均为 **0**；31/32 弹层快照每行最多 **2** 次变化，对应被遮挡后的纯色弹层框。对照组检出 **23～279** 文字行。
- 恢复：普通壳与弹层 probe 均 **0→1**，关闭弹层后壳显示 **1**。FR-072 前台截屏 PNG 签名正确且有内容。QPR2 普通壳另有负责人文字判定「QPR2 最近任务卡片看不到 sentinel」。
- 初版检测以「偏离众数色的行」判断，曾将纯色弹层框误判为 **FAIL**；已改为上述变化次数法，并用阳性对照核实，原始记录保留。
- 证据与脚本：`.handoff/evidence/2026-11-05-t010/`（本地，不入库）。本段更新此前 T009 执行记录中 T010 的 PENDING 状态，保留此前记录作为历史，不改只读规格复选框。

## S0-05 T012：Android 映射文档

2026-11-05，执行 Codex；branch=`feat/android-s0-infrastructure`，基点 HEAD=`c381853`。只读规格来自 canonical root `~/gitrepo/ignacioli/.worktree/specs-android-s0/FineCoach/007-android-port/` 的 `s0-infrastructure/{tasks,spec,plan}.md` 与 ADR-001 §7.2，不经产品 `specs` symlink 选择来源。开工状态：tracked modification 0、staged 0、untracked 仅 `.vscode/`（用户既存，保留）；`git diff --stat` 为空。白名单只新增 DS README Android 映射节和本节，不 stage/commit、不切分支、不 stash、不改任务复选框。

规则位于 [DS README §15「Android 映射规则」](../design/design-system/README.md#15-android-映射规则)：字号 pt→sp；几何/描边 pt→dp；fontScale；行高倍率与 iOS 实际 lineSpacing；零字距；单文件 variable font 四档轴值；capsule shape；来源与待核实边界。D02/D05/D14 按负责人 2026-11-03 批准执行：直接 README→Kotlin、不出 `tokens.json`，复用现有随包 Noto Sans SC 与 OFL，正文及 `‹ › ✓` 不采用系统字体。

### T013 生成器输入约定

数值唯一输入为 `design/design-system/README.md`，按节标题和表头定位，不依赖行号；iOS 源码/测试是独立比对来源，不是生成输入。本约定沿用 plan §3.3、S0-FR-050～052 和 T013，不在本轮创建生成器、字体副本或 Kotlin 产物。

| DS 来源表 / 文字约束 | 读取列与解释 | T013 用途 |
|---|---|---|
| §2.1 原子色 | `Token`、`值`；`备注`只作来源说明 | `FcColors.kt` 的原子值；不读取插图色或历史裁决表作为当前色表 |
| §2.2 语义色 | `语义 Token`、`引用`、`值`；用途列保留来源语境 | 语义别名及解析值；overlay 的 `#… @ …%` 分别解析 RGB 与 alpha，不能丢 alpha；`—` 引用允许直接值，不臆造原子 token |
| §3.2 阶梯、§3.3 具名例外 | `样式`、`字号 / 字重`、`行高`、`缩放基准`；§3.2 另读 `允许的字重变体（画稿实测）`；§3.3 的 `画稿用途`含 compact 选中/今天 600 的显式约束 | `FcTypography.kt`，保留 14 个样式名；解析字号与字重为两个数、行高为倍率；按 §15 应用 sp、零字距、随包字体及变体，不把用途文本中的其他数字当新 token |
| §3.1 字体与 §15 映射 | 家族、资产/OFL、字距、缩放约束；§15 的公式与轴值映射 | 排版生成策略；§15 不是第二份字号表，待核实项不得静默变成默认实现 |
| §4 间距 | `Token`、`值`，另遵循表后零间距例外 | `FcSpacing.kt`，六档 dp；合法 `0` 不新增刻度，也不豁免其他设计值 |
| §5 圆角 | `Token`、`值`；用途列保留来源语境 | `FcShapes.kt`，五个固定 dp 圆角及 `radius.capsule` 特殊 shape；「高度 / 2」不是数值解析失败后的默认 0 |

§6 尺寸/描边文字、§7.2 字形表、§8 组件表仅供相应组件后续映射，不扩充 T013 四份 token 文件的数值输入表。G1 的独立期望与对比度检查另以 §11 全 17 行的 `前景`、`背景`、`对比度`、`结论`及 iOS harness 为依据；保留两项豁免分类、阈值与误差，不从待测 Kotlin 反推 expected。对应 iOS 来源：`VisionHarnessTests.swift`（色/alpha/六间距/五固定圆角）、`TypographyHarnessTests.swift`（14 样式与四档轴值）、`ContrastHarnessTests.swift`（阈值/误差）；均在 `ios/FineCoachTests/DesignSystem/`。capsule 与实际 fontScale/行盒需 Android 自己证明，不能声称 iOS 已有相应渲染测试。

生成器按 T013/plan §3.3 将四个 Kotlin 文件写到 build/generated；缺表、重复 token/样式、格式异常必须失败，不能漏行、猜值或沿用旧产物；源章节位置和输入 digest 随产物记录。§3.2 显式指向 §3.3 的具名变体引用需解析为同一样式，不能误判为第二份定义或额外样式。G1 的实现和运行属于 T013，本轮不运行 Gradle。

### 待核实与执行记录

待核实的权威清单在 [DS README §15.5](../design/design-system/README.md#155-待核实)：精确行盒及 Alignment/Trim/includeFontPadding 组合、iOS 注册失败 fallback 差异、组件局部缩放适配、来源历史措辞和 cursor-agent 独立复核。字体方案与 README 直接生成路线已经批准，不列为待选方案。

1. 分类与依据：C，补齐 S0-FR-052/T012 已批准映射的文字；新增 §15 和本节，既有 token/色值/样式/anatomy 保留；无删除项，不触发新的设计审批。
2. 影响范围：仅两份 README；复用 DS-BASE 排版约束及 DS-SYMBOL 的随包字形来源，不扩展/新增组件，不改 iOS、components、Penpot 或截图基线。
3. 设计决定：沿用 2026-11-03 的 D02/D05/D14；规则内逐项列 iOS 路径/行号和规格来源。尚无证据的行盒策略不自行定案。
4. 实施与验证：文档 readback、来源/表头核对与 diff 范围检查；无新交互，entry/layout map 无新增行；不运行 Gradle、模拟器或 xcodebuild，不查看截图，不声称视觉验证；无新 A/B 设计或页面实现，未触发 L3。
5. 结果：完成两份文档回填与静态检查；待 cursor-agent 独立复核及 §15.5 后续核实。未执行 T013、G1/G5 或 CP2 验收，未改 tasks 状态。

## S0-05 T013：token 生成器与 G1（2026-11-05）

本轮在 T012 未提交文档上继续实现，保留既存 `design/design-system/README.md`、本 README 和 `.vscode/`；不 stage/commit、切分支或 stash，不改只读规格、iOS、shared、截图基线。本节是 T013 实现记录，前节「本轮不创建生成器」属于 T012 的历史范围。

### 输入、输出与失败行为

`scripts/android/generate-tokens.mjs` 使用 Node 标准库，直接读取 DS README §2.1、§2.2、§3.2、§3.3、§4、§5 六表及 §3.1/§15 的字体、字距和映射约束。按章节和完整表头定位，缺章节/表、重复定义、未知/缺失/重排列、坏色值/数值/行结构、引用不一致、具名变体不一致和 capsule 异常均退出非 0；先完整解析再写文件，不拿旧输出冒充成功。

输出仅在 `android/app/build/generated/designtokens/com/ignacioli/finecoach/designsystem/`：`FcColors.kt`、`FcTypography.kt`、`FcSpacing.kt`、`FcShapes.kt`。每份带 README SHA-256 和源表章节/行范围，生成物被现有 build ignore 排除，不入库。颜色含 15 原子色、19 语义色及 40% overlay；`light`/`dark` 均沿用唯一批准色表，没有新增暗色调色盘。排版 14 样式，字号 sp、名义行高为字号×倍率 sp、零字距、禁止合成字重；`title`/`caption` 的箭头引用解析为已有具名样式。间距六档 dp、固定圆角五档 dp、capsule 为按实际短边 50% 的 shape。

从产品根可执行（不需要 Gradle）：

```sh
node scripts/android/generate-tokens.mjs
node scripts/android/generate-tokens.mjs --check
node --test scripts/android/generate-tokens.test.mjs
```

支持 `--input <README> --output <directory>`，供临时 fixture 使用；`--check` 在系统临时目录重新生成，严格比较文件清单和字节，缺文件、多文件、手改均失败，不修复被检查的文件。Node 自检实测 **16/16 PASS、0 failures/skips**：1 个合法确定性生成/check；12 个输入负例（缺章节、缺表、重复 token、重复样式、未知列、坏数值、坏色值、列数异常、缺 pipe、alias 冲突、具名变体冲突、capsule 固定值）；3 个输出负例（手改、缺文件、多文件）。

Gradle `generateDesignTokens` 声明 README/脚本输入及输出目录，通过 AGP 9 Variant API `variant.sources.kotlin.addGeneratedSourceDirectory(generateDesignTokens, GenerateDesignTokensTask::outputDir)` 注册类型化生成目录，由该 API 传递生成与编译依赖，不再使用 `preBuild.dependsOn`。`checkDesignTokens` 只在整个输出目录尚不存在时 bootstrap；已有目录必须先通过临时重生比对。`s0G1` 同图运行时，generate 排在 check 后，避免自动重生掩盖手改。README 合法修改后先明确运行 generate，再 check；已有过期产物不会在 check 中静默更新。

### G1 测试与宿主命令

| suite | 预期 tests | 独立来源与覆盖 |
|---|---:|---|
| `TokenParityTests` | 6 | 从 iOS `Tokens.swift` / `VisionHarnessTests` 逐值写 expected：15 原子色、19 语义色含 overlay、六间距、五固定圆角；另证明 capsule 随短边变化及 dp 不随 fontScale 变化 |
| `TypographyTests` | 7 | 从 iOS `Typography.swift` / `TypographyHarnessTests` 逐值写 14 样式 size/weight/名义 lineHeight；允许变体及非法请求、字体引用；Android resource 四轴与 `‹ › ✓`/中文字形；Compose fontScale 1/1.5/2 与单/多行 metrics |
| `ContrastTests` | 17 | §11 全 17 行，用生成颜色自行算 WCAG luminance/ratio；同 iOS 0.005 误差，12 文本行阈值 4.5、3 控件边界行阈值 3.0；装饰分割线/禁用态只锁记录比值，不设阈值、不 skip |
| `TokenGeneratorTests` | 9 | 真 Node CLI + 临时 README：合法 generate/check、缺表、重复 token/style、坏值、坏行、未知列、alias 冲突、手改生成物；expected 不读取生成物推导 |
| 合计 | **39** | 全部必须实际执行，0 failures/errors/skips |

宿主从 `android/` 执行（2026-11-06 已通过；allowlist 已按下一节重生成）：

```sh
./gradlew :app:generateDesignTokens
./gradlew :app:checkDesignTokens
./gradlew :app:s0G1
./gradlew assembleDebug assembleRelease assembleDebugAndroidTest lint
```

`s0G1` 是独立 resource-aware JVM/Robolectric Test task，精确选择上述四个 suite，拒绝空发现、NO-SOURCE/skip、缺 suite、测试数变化和 JUnit failure/error/skip；每次执行、不复用旧测试结果。JUnit XML 在 `app/build/test-results/s0G1/`，HTML 在 `app/build/reports/tests/s0G1/`。单/多行 metrics 为文字输出；不读取截图、不 record baseline。**2026-11-06 宿主 `generateDesignTokens`、`checkDesignTokens` 通过，`s0G1` 实际执行 39 tests、0 failure。**

### 字体与主题

D05 原资产 `ios/FineCoachApp/Resources/Fonts/NotoSansSC-VF.otf` → `android/app/src/main/res/font/noto_sans_sc_variable.otf`；原 `OFL.txt` → `android/app/src/main/assets/fonts/OFL.txt`。两份复制品均已逐字节比对相同。字体 **15,054,748 bytes**；编排方于 2026-11-06 在宿主重算确认，iOS 原件与 Android 副本的 SHA-256 均为 `d13ed01ec8aa45d6178999b648e96fb92150683e9f8e2a581f2acf208dcbe44b`，两份哈希相同；OpenType CFF2，单 `wght` 轴范围 100～900、默认 100。没有转换、下载或裁剪。

`FcFont.kt` 用同一 `R.font.noto_sans_sc_variable` 建四个 blocking Font 实例，显式 `FontVariation.Settings(FontVariation.weight(400/500/600/700))`，匹配相同 FontWeight；生成 TextStyle 使用该 FontFamily 与 `FontSynthesis.None`。资源方式及 variation API 见 [Android 官方字体文档](https://developer.android.com/develop/ui/compose/text/fonts)。2026-11-06 宿主 G1 已通过其中的 native resource/轴值/glyph 测试；该证据限于所测 Robolectric 环境，不等于独立检查了 Compose resolver 的实际轴值或真机字体表现。

`FineCoachTheme` 用生成颜色和排版包装 MaterialTheme，壳与 debug 样例共用。Material typography 15 个常规槽位均显式映射到既有 DS 样式；`bodyLarge=body`，`bodyMedium=callout(400)`，其余映射见 `FineCoachTheme.kt`，不继承 Material 非零字距。未实现的产品组件仍应显式选择其批准的 DS 样式，不以此包装代替 T015 roster。debug 样例间距改用 space4/space2，保留原 48dp 探针点击高度、所有 testTag、计数/弹层控制和隐私生命周期路径。

### Material3 与 resolved allowlist

负责人 2026-11-05 明确批准 T013 接入已列于 T001 表的 `androidx.compose.material3:material3`（表中 1.4.0）；catalog 新增 `compose-material3`，不写单独 version，由既有 Compose BOM `2026.09.00` 管理，app `implementation(libs.compose.material3)`。仅新增这一条直接依赖坐标，没有声明 `material-icons-*` 或其它新依赖。2026-11-06 宿主 resolved graph 与重生成的 `resolved.txt` 已记录新增坐标：`androidx.compose.material3:material3:1.4.0`、`androidx.compose.material3:material3-android:1.4.0`、`androidx.compose.material:material-ripple:1.12.1`、`androidx.compose.material:material-ripple-android:1.12.1`、`androidx.lifecycle:lifecycle-common-java8:2.11.0`。

现有 `writePrivacyDependencyGraph` 与 `android/dependency-allowlist/generate-resolved.mjs` 已覆盖全部 12 scopes（含 implementation 的 compile/runtime）；不需为 Material3 增补 scope 或修改生成器。现有生成器自检 **8 正/项目例 + 4 拒绝例通过**。2026-11-06 宿主已通过 `writePrivacyDependencyGraph` 并按既有流程重生成 `resolved.txt`；本次文档更新不再修改 allowlist。

以下为宿主已执行的解析与生成命令，保留供后续依赖变更复用：

```sh
# android/
./gradlew :app:writePrivacyDependencyGraph
# product root
node android/dependency-allowlist/generate-resolved.mjs android/app/build/reports/s0/privacy --resolved-report android/app/build/reports/s0/privacy/resolved.txt
```

新增坐标见上文，scopes 以宿主重生成的 `resolved.txt` 为准；后续依赖变更仍须按现有流程审核，不放行未批准依赖或 `material-icons-*`。

### 待核实与执行记录

2026-11-06 宿主实际结果（编排方提供）：`writePrivacyDependencyGraph` 与 allowlist 重生成、`generateDesignTokens`/`checkDesignTokens`、`s0G1` **39 tests、0 failure**、`assembleDebug`/`assembleRelease`/`assembleDebugAndroidTest` 与 `lint` 全部通过；`testDebugUnitTest` **127 tests、0 failure/skip**（含 `FictionalDataPolicyTests` **13**）；`s0Room` **18/18**；`s0EnvironmentSmoke` 通过。日志：`.handoff/logs/2026-11-06-host-s0-05-t013*.log`。cursor-agent 对 T012/T013/T010 的复核于 **2026-11-06 通过**；本次仅回填文档，不重跑 Gradle。

仍开放 DS §15.5 的精确自然行高下限、首尾留白与 Alignment/Trim/includeFontPadding parity、字体失败路径差异、局部缩放适配及来源旧措辞；Compose resolver 实际轴值仍待独立核实。fontScale runtime 测试只证明所测环境响应，不代表 Android 14+ 非线性缩放与 UIKit 逐档等价。独立复核项已通过，不再列为待执行。未进行人工视觉验证，不将 G1 通过等同于 CP2 验收，不改 tasks 状态。

1. 分类与依据：D，DS-BASE 既有值的 Android 实现对齐；目标值/anatomy 不变，来源 DS README §2～§5/§15 与批准 D02/D05；T010 为负责人提供的宿主结果回填。
2. 范围：复用 DS-BASE token/字体；消费者仅空壳和既有虚构 debug 样例；无新增组件、业务入口或持久化，design 与 Penpot 无设计变更可同步。
3. 设计决定：复用已批准映射、随包字体与本轮 Material3 授权；精确行盒 parity 保持待核实，不以默认值宣称完成。
4. 实现与检查：Node 16/16、自检字体/OFL 同字节、allowlist parser 自检通过；宿主 G1 39 例及 build/lint 已于 2026-11-06 通过，完整 JVM 127 例、Room 18/18、smoke 通过，证据见上述日志。entry/layout map 无新增行；原 `s0-open-dialog`/`s0-probe`/`s0-dialog-probe`/`s0-close-dialog` 可见按钮仍分别修改弹层状态/内存计数，原 Column.fillMaxWidth 撑满宽度，testTag 未变。未触发新设计 L3；现有 T010 运行结果不代替本轮 APK 验证。
5. 结果：Node 检查、宿主 G1/build/lint/JVM/Room/smoke、allowlist 重生成及 cursor-agent 复核均 PASS；字体哈希一致。§15.5 上述 parity 等待核实项继续开放；不宣称 CP2 完成，不做截图基线、G3/G4、gate.sh。

## S0-08 T015/T016：Android 基础组件与 G2

2026-11-05 本轮依据负责人「全速推进到 S1」决定实施，不等 Penpot AD-01～03，不执行 T014/T031、截图基线、G3/G4。规格目录 `/Users/liyongqiang/gitrepo/ignacioli/.worktree/specs-android-s0/FineCoach/007-android-port/` 只读，未改 tasks 状态。设计权威和完整 roster 见 [components.md §8](../design/design-system/components.md#8-android-s0-rostert015t0162026-11-05)。一般组件沿用 iOS anatomy；AD-01/02/03 保留 B 类，系统栏/全面屏/返回按 ADR A/B，未宣称负责人已审设计或已验收。

开工审计：`git status --short` 仅 `?? .vscode/`，tracked modifications/staged 均 0，`git diff --stat` 空；`.vscode/` 属既有用户文件，原样保留。计划仅写本轮白名单，未 commit、stash、切分支；GATE PASS，分支 `feat/android-s0-infrastructure`。独立 agent 未启动：CLAUDE 的批准 run-list 仅列 Codex，且禁止两个并发 agent 写同一 worktree。本轮由 primary 完成，cursor-agent 独立复核待编排。

### roster 摘要

当前 roster 24 个 ID 全部登记 Kotlin 入口、iOS 来源、代表状态、G2 method 与 L3 项；debug catalog 共 66 个代表状态。S0 登记 22 个，S1 T010 按 S1-D15 补上 `DS-HINT-BAR`（`FcHintBar.kt`）和单行 `DS-HERO-CARD`（`FcHeroCard.kt`）。`FcControls.kt` 负责按钮、标题操作、segmented、chips、toggle、Stepper/FIELD、输入和符号；`FcRows.kt` 负责列表、区段、两栏、页头、入口、操作、撤销；`FcFeedback.kt` 负责状态、头像、结果、sheet、确认和日期选择。`FineCoachTheme.kt` 继续作为 DS-BASE，不修改生成器或 token 权威。

- Material 对应物：DS-BOTTOM-SHEET → M3 ModalBottomSheet；日期选择 → M3 DatePickerDialog/DatePicker（LABEL-VALUE-ROW 示例）；toggle 使用 Compose toggleable 的 Role.Switch，保留已有轨道外观。其余按 iOS anatomy 自绘，消费生成 token，不引图标依赖。
- 组件既有几何在 `FcComponentMetrics` 用生成 spacing 组合表达，出处是 components §4/README §6/§8；没有新增 token 值。`‹ › ✓` 仍用随包 Noto Sans SC，不使用系统图标或临时字体替代。
- 延期 9 ID：AMBIENT-SCENE、SET-ROW、EQUIPMENT-ICON、PAGE-PRIMARY、PAGE-SECONDARY、EMPTY-STATE、LAUNCH（S1）；CALENDAR-DAY（S2）；BODY-DIAGRAM（S4）。`DS-HINT-BAR` 与 `DS-HERO-CARD` 已进入 roster。完整逐 ID 表含 D07 批准来源，见 components §8.2。
- 行和按钮传入 callback，不在 DS 层持久化、删除对象或决定课包生命周期；Undo 的业务窗口、原位置恢复留给调用方，S0 无业务实体不伪造这类证明。

### 宿主命令与预期数量

按本 README 前文配置已批准 JDK21、SDK 与缓存，从 `android/` 执行：

```sh
./gradlew assembleDebug lint
./gradlew :app:s0G1 :app:s0G2
```

本轮按指令没有运行以上命令、Gradle、模拟器或 xcodebuild。下表是代码声明的预期值，**不是运行结果**。

| gate / suite | 预期 tests | 证明范围 |
|---|---:|---|
| s0G1 | 39 | 现有 token/字体/contrast/generator 合同，未改 |
| ComponentCatalogTests | 6 | 24 项精确 roster、类型/真实文件/iOS 来源、状态与测试方法、9 项延期和 authority 并集、debug/privacy 入口保留、图标需求/无依赖 |
| ComponentCatalogStateTests | 66 | 参数化逐个状态真正 compose 并检查组件 testTag，不以文字清单代替渲染 |
| ComponentContractTests | 27 | roster 每 ID 一个合同方法（含 S1-D13 BottomSheet 完全展开）；touch/满宽、disabled callback、单选/三态、Stepper/FIELD、输入/secure、heading/semantics、确认/重试/撤销、提示条/单行 hero、训练组行、多行 hero、token source 检查等 |
| PlatformShellTests | 5 | header 与系统 back dispatcher 同 callback、Insets 只消费一次、内容宽度、catalog 可见入口/返回、独立 overlay window 隐私注册/释放 |
| s0G2 合计 | 101 | 上述四个 suite 全部非空，0 failures/errors/skips；与 G1 联跑总计 140 |

`s0G2` 替换原占位任务，report：`app/build/test-results/s0G2/TEST-*.xml`，HTML：`app/build/reports/tests/s0G2/`。禁用 up-to-date/cache；finalizer 拒绝失败、skip、NO-SOURCE、缺 suite、重复 suite、0 tests、非预期数量，以及 XML 中任一 failure/error/skipped。不创建或更新 screenshot baseline，不依赖 G3/G4/G5。ParameterizedRobolectricTestRunner 使用其自己的 `Parameters` 注解（已对照本机 4.17 JAR）；最终 Gradle XML 归组/计数仍待宿主执行确认，失败不能改数量或删断言求通过。

### entry / layout map

所有操作仅修改 debug 内存或样例导航，不改业务数据。下列 `tag` 都是实际代码的 `testTag`，`{id}/{state}` 是下面明确列举的 catalog 元数据展开，不是任意产品路由。文件缩写：

- Shell = `app/src/debug/java/com/ignacioli/finecoach/S0DebugApplication.kt` 的 `Content` / `PrivacySample`。
- Catalog = `app/src/debug/java/com/ignacioli/finecoach/S0ComponentCatalog.kt` 的 `S0ComponentCatalog` / `S0ComponentState`。
- Controls / Rows / Feedback = `app/src/main/java/com/ignacioli/finecoach/designsystem/FcControls.kt` / `FcRows.kt` / `FcFeedback.kt`。

格式为 §1.4 要求的「screen → visible control → identifier → mutates data? → width owner」，末列指向真实实现。满宽指父内容列，图标/链接/segmented/chip/开关/步进符号只要求 44 点击区，明确不要求满宽。

| screen | visible control | identifier | mutates data? | width owner / code |
|---|---|---|---|---|
| debug shell | 打开虚构弹层 | s0-open-dialog | 否，开弹层 | Shell SampleButton fillMaxWidth |
| debug shell | 交互探针 +1 | s0-probe | 仅内存计数 | Shell SampleButton fillMaxWidth |
| debug privacy dialog | 交互探针 +1 | s0-dialog-probe | 仅内存计数 | Shell SampleButton fillMaxWidth |
| debug privacy dialog | 关闭弹层 | s0-close-dialog | 否，关弹层 | Shell SampleButton fillMaxWidth |
| debug shell | 基础组件样例 | s0-open-catalog | 否，样例导航 | Shell SampleButton fillMaxWidth |
| catalog 任一级 | 返回 ‹ | catalog-back | 否，样例导航；同系统 back callback | Rows FcPageHeader；44 点击区，布局占 space.4 |
| catalog 索引 | DS-BASE 分组入口 | catalog-DS-BASE | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-BUTTON 分组入口 | catalog-DS-BUTTON | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-TITLE-ACTION 分组入口 | catalog-DS-TITLE-ACTION | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-SEGMENTED 分组入口 | catalog-DS-SEGMENTED | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-CHIP 分组入口 | catalog-DS-CHIP | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-TOGGLE 分组入口 | catalog-DS-TOGGLE | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-STEPPER 分组入口 | catalog-DS-STEPPER | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-TEXT-FIELD 分组入口 | catalog-DS-TEXT-FIELD | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-LIST-ROW 分组入口 | catalog-DS-LIST-ROW | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-SECTION 分组入口 | catalog-DS-SECTION | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-LABEL-VALUE-ROW 分组入口 | catalog-DS-LABEL-VALUE-ROW | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-PAGE-HEADER 分组入口 | catalog-DS-PAGE-HEADER | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-HUB-ROW 分组入口 | catalog-DS-HUB-ROW | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-INLINE-RESULT 分组入口 | catalog-DS-INLINE-RESULT | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-ACTION-ROW 分组入口 | catalog-DS-ACTION-ROW | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-UNDO-ROW 分组入口 | catalog-DS-UNDO-ROW | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-BOTTOM-SHEET 分组入口 | catalog-DS-BOTTOM-SHEET | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-CONFIRM-DIALOG 分组入口 | catalog-DS-CONFIRM-DIALOG | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-STATUS 分组入口 | catalog-DS-STATUS | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-SAVE-STATUS 分组入口 | catalog-DS-SAVE-STATUS | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-AVATAR 分组入口 | catalog-DS-AVATAR | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-SYMBOL 分组入口 | catalog-DS-SYMBOL | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-HINT-BAR 分组入口 | catalog-DS-HINT-BAR | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| catalog 索引 | DS-HERO-CARD 分组入口 | catalog-DS-HERO-CARD | 否，样例导航 | Catalog → Rows FcGroupEntryRow fillMaxWidth |
| DS-BUTTON/default | 主按钮样例 / 次按钮样例 / 链接样例 | DS-BUTTON-default | 仅内存计数 | Catalog → Controls；primary/secondary 满宽，link ≥44 |
| DS-BUTTON/secondary | 主按钮样例 / 次按钮样例 / 链接样例 | DS-BUTTON-secondary | 仅内存计数 | Catalog → Controls；primary/secondary 满宽，link ≥44 |
| DS-BUTTON/link | 主按钮样例 / 次按钮样例 / 链接样例 | DS-BUTTON-link | 仅内存计数 | Catalog → Controls；primary/secondary 满宽，link ≥44 |
| DS-TITLE-ACTION/icon | Material 图标按钮 | DS-TITLE-ACTION-icon | 仅内存计数 | Catalog → Controls title button ≥44 |
| DS-TITLE-ACTION/add | Material 图标按钮 | DS-TITLE-ACTION-add | 仅内存计数 | Catalog → Controls title button ≥44 |
| DS-SEGMENTED/first | 选项甲 | DS-SEGMENTED-first-0 | 仅内存选择 | Catalog → Controls selectable ≥44 |
| DS-SEGMENTED/first | 选项乙 | DS-SEGMENTED-first-1 | 仅内存选择 | Catalog → Controls selectable ≥44 |
| DS-SEGMENTED/last | 选项甲 | DS-SEGMENTED-last-0 | 仅内存选择 | Catalog → Controls selectable ≥44 |
| DS-SEGMENTED/last | 选项乙 | DS-SEGMENTED-last-1 | 仅内存选择 | Catalog → Controls selectable ≥44 |
| DS-CHIP/off | 虚构筛选 | DS-CHIP-off | 仅内存选择 | Catalog → Controls chip ≥44 |
| DS-CHIP/on | 虚构筛选 | DS-CHIP-on | 仅内存选择 | Catalog → Controls chip ≥44 |
| DS-CHIP/body | 胸 | DS-CHIP-body-0 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 肩 | DS-CHIP-body-1 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 背 | DS-CHIP-body-2 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 大腿 | DS-CHIP-body-3 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 小腿 | DS-CHIP-body-4 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 臂 | DS-CHIP-body-5 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 臀 | DS-CHIP-body-6 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-CHIP/body | 核心 | DS-CHIP-body-7 | 仅内存选择 | Catalog → Controls BodyPartPicker FlowRow / chip ≥44 |
| DS-TOGGLE/off | 样例开关 | DS-TOGGLE-off | 仅内存开关 | Catalog → Controls toggle ≥44 |
| DS-TOGGLE/on | 样例开关 | DS-TOGGLE-on | 仅内存开关 | Catalog → Controls toggle ≥44 |
| DS-STEPPER/lower | 左侧减少 / 右侧增加 | DS-STEPPER-lower-minus | 仅内存数值，边界禁用 | Catalog → Controls StepButton ≥44 |
| DS-STEPPER/lower | 左侧减少 / 右侧增加 | DS-STEPPER-lower-plus | 仅内存数值，边界禁用 | Catalog → Controls StepButton ≥44 |
| DS-STEPPER/upper | 左侧减少 / 右侧增加 | DS-STEPPER-upper-minus | 仅内存数值，边界禁用 | Catalog → Controls StepButton ≥44 |
| DS-STEPPER/upper | 左侧减少 / 右侧增加 | DS-STEPPER-upper-plus | 仅内存数值，边界禁用 | Catalog → Controls StepButton ≥44 |
| DS-STEPPER/field | 左侧减少 / 右侧增加 | DS-STEPPER-field-minus | 仅内存数值，边界禁用 | Catalog → Controls StepButton ≥44 |
| DS-STEPPER/field | 左侧减少 / 右侧增加 | DS-STEPPER-field-plus | 仅内存数值，边界禁用 | Catalog → Controls StepButton ≥44 |
| DS-STEPPER/field | 样例数值输入 | DS-STEPPER-field-input | 仅内存文本 | Catalog → Controls FIELD weight(1f)，整胶囊满宽 |
| DS-TEXT-FIELD/empty | 虚构输入 | DS-TEXT-FIELD-empty | 仅内存文本 | Catalog → Controls TextField fillMaxWidth |
| DS-TEXT-FIELD/secure | 虚构输入 | DS-TEXT-FIELD-secure | 仅内存文本 | Catalog → Controls TextField fillMaxWidth |
| DS-TEXT-FIELD/search | 搜索虚构内容 | DS-TEXT-FIELD-search | 仅内存文本 | Catalog → Controls TextField fillMaxWidth |
| DS-LIST-ROW/action | 虚构项目 | DS-LIST-ROW-action | 仅内存计数或选择 | Catalog → Rows ListRow fillMaxWidth |
| DS-LIST-ROW/selected | 虚构项目 | DS-LIST-ROW-selected | 仅内存计数或选择 | Catalog → Rows ListRow fillMaxWidth |
| DS-LIST-ROW/group | 虚构分组展开 / 选择 | DS-LIST-ROW-group-expand | 仅内存展开或选择 | Catalog → Rows GroupRow 满宽；expand weight(1f)，toggle ≥44 |
| DS-LIST-ROW/group | 虚构分组展开 / 选择 | DS-LIST-ROW-group-toggle | 仅内存展开或选择 | Catalog → Rows GroupRow 满宽；expand weight(1f)，toggle ≥44 |
| DS-SECTION/entry | 虚构分组 | DS-SECTION-entry | 仅内存计数 | Catalog → Rows GroupEntryRow fillMaxWidth |
| DS-LABEL-VALUE-ROW/slot | 值开关 | DS-LABEL-VALUE-ROW-slot-toggle | 仅内存开关 | Catalog → Rows 值 slot → Controls toggle ≥44 |
| DS-LABEL-VALUE-ROW/action | 选择日期 | DS-LABEL-VALUE-ROW-action | 仅内存开弹层 | Catalog → Rows LabelValueRow fillMaxWidth |
| DS-PAGE-HEADER/back | 返回 ‹（样例探针） | DS-PAGE-HEADER-back-back | 仅内存计数 | Catalog → Rows PageHeader ≥44 |
| DS-PAGE-HEADER/trailing | 返回 ‹（样例探针） | DS-PAGE-HEADER-trailing-back | 仅内存计数 | Catalog → Rows PageHeader ≥44 |
| DS-PAGE-HEADER/trailing | 编辑样例 | DS-PAGE-HEADER-trailing-trailing | 仅内存计数 | Catalog → Rows PageHeader → Controls LinkButton ≥44 |
| DS-HUB-ROW/action | 虚构入口 | DS-HUB-ROW-action | 仅内存计数 | Catalog → Rows HubRow fillMaxWidth |
| DS-INLINE-RESULT/failure | 重试 | DS-INLINE-RESULT-failure-retry | 仅内存计数 | Catalog → Feedback InlineResult → Controls LinkButton ≥44 |
| DS-INLINE-RESULT/success | 重试 | DS-INLINE-RESULT-success-retry | 仅内存计数 | Catalog → Feedback InlineResult → Controls LinkButton ≥44 |
| DS-INLINE-RESULT/info | 重试 | DS-INLINE-RESULT-info-retry | 仅内存计数 | Catalog → Feedback InlineResult → Controls LinkButton ≥44 |
| DS-ACTION-ROW/normal | 普通操作样例 | DS-ACTION-ROW-normal | 仅内存计数 | Catalog → Rows ActionRow fillMaxWidth |
| DS-ACTION-ROW/destructive | 删除虚构样例 | DS-ACTION-ROW-destructive | 否，先打开确认 | Catalog → Rows ActionRow fillMaxWidth |
| DS-ACTION-ROW/destructive | 删除样例 / 取消 | DS-ACTION-ROW-destructive-accept | 确认仅增内存计数；取消只关闭 | Catalog → Feedback ConfirmationDialog 按钮行 weight(1f)；大字纵排满宽 |
| DS-ACTION-ROW/destructive | 删除样例 / 取消 | DS-ACTION-ROW-destructive-cancel | 确认仅增内存计数；取消只关闭 | Catalog → Feedback ConfirmationDialog 按钮行 weight(1f)；大字纵排满宽 |
| DS-UNDO-ROW/visible | 撤销 | DS-UNDO-ROW-visible-action | 仅内存计数 | Catalog → Rows UndoRow 满宽；LinkButton ≥44 |
| DS-BOTTOM-SHEET/open | 打开样例面板 | DS-BOTTOM-SHEET-open | 否，开弹层 | Catalog → Controls Button fillMaxWidth |
| DS-BOTTOM-SHEET/open | 关闭样例面板 | DS-BOTTOM-SHEET-open-close | 否，关弹层 | Catalog → Feedback Sheet → Rows ActionRow fillMaxWidth |
| DS-CONFIRM-DIALOG/open | 打开样例确认 | DS-CONFIRM-DIALOG-open | 否，开弹层 | Catalog → Controls Button fillMaxWidth |
| DS-CONFIRM-DIALOG/open | 确认样例 / 取消 | DS-CONFIRM-DIALOG-open-accept | 确认仅增内存计数；取消只关闭 | Catalog → Feedback ConfirmationDialog 按钮行 weight(1f)；大字纵排满宽 |
| DS-CONFIRM-DIALOG/open | 确认样例 / 取消 | DS-CONFIRM-DIALOG-open-cancel | 确认仅增内存计数；取消只关闭 | Catalog → Feedback ConfirmationDialog 按钮行 weight(1f)；大字纵排满宽 |
| DS-CONFIRM-DIALOG/long | 打开样例确认 | DS-CONFIRM-DIALOG-long | 否，开弹层 | Catalog → Controls Button fillMaxWidth |
| DS-CONFIRM-DIALOG/long | 确认样例 / 取消 | DS-CONFIRM-DIALOG-long-accept | 确认仅增内存计数；取消只关闭 | Catalog → Feedback ConfirmationDialog 按钮行 weight(1f)；大字纵排满宽 |
| DS-CONFIRM-DIALOG/long | 确认样例 / 取消 | DS-CONFIRM-DIALOG-long-cancel | 确认仅增内存计数；取消只关闭 | Catalog → Feedback ConfirmationDialog 按钮行 weight(1f)；大字纵排满宽 |
| DS-HINT-BAR/continue | 继续 | DS-HINT-BAR-continue | 仅内存计数 | Catalog → FcHintBar 满宽，最小触控高 |
| DS-HERO-CARD/single | 继续样例 | DS-HERO-CARD-single | 仅内存计数 | Catalog → FcHeroCard 满宽，最小高 100；标题 heading |
| 日期样例 | Material 日期选择器 | date-picker | 仅 picker 暂存选择 | Feedback M3 DatePicker；内部日期格由 Material semantics 定位 |
| 日期样例 | 确定 | date-accept | 仅内存选择日期并关闭 | Feedback Controls LinkButton ≥44 |
| 日期样例 | 取消 | date-cancel | 否，关闭 | Feedback Controls LinkButton ≥44 |

只读、disabled、装饰性样例没有数据操作：BUTTON/disabled、TOGGLE/disabled、ACTION-ROW/disabled 不触发 callback；LIST-ROW/plain/unavailable、HUB-ROW/info/unavailable、HINT-BAR/info 不提供 click action。DatePicker 的应用入口、整体、确定/取消由应用赋 tag；Material 内部日期格/年导航和 sheet 内部手势使用平台 semantics，库没有逐格 tag 注入 API，本轮不侵入库或虚构 API。宿主应核实其可访问性和触控行为；这不是 app 自绘控件漏入口的豁免。

### L3 与图标接入

统一负责人模拟器走查仍待执行：header 内联返回与大字标题/尾部操作不重叠、中文字体行盒、chip 换行与间隔、Stepper 数值和键盘、确认框大字纵排/长说明滚动、危险操作语义、sheet 拖拽/遮罩/返回、DatePicker 本地化与颜色、系统栏明暗/全面屏/系统返回动画。JVM back dispatcher/Insets 测试不能替代真实系统手势或 OEM runtime 证据。API31/32 新独立窗口的后台遮罩与 API33+ recents 行为仍需宿主设备证据，不把 G2 注册测试称为系统缩略图证明。

13 个 Material Symbols 已接入，见 [manifest](design-assets/material-symbols-manifest.txt) 和 [逐项 provenance](design-assets/material-symbols-provenance.json)：add、remove、expand_more、calendar_month、settings、grid_view、filter_list、delete、sync、check_circle、warning、priority_high、info。SVG/权重按宿主清单，上游 commit 为 10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7；已比对原 SHA256SUMS，保留 pathData，viewport 960×960 和 translateY=960。catalog 使用 painterResource 注入，已去掉空 Painter 与占位文字；没有新增依赖。

Material Symbols by Google，Apache License 2.0；完整 LICENSE、NOTICE 和原始 SVG 归档在 design-assets，许可也随 APK assets/licenses 打包。现无应用内许可页面约定，本轮不新增产品页面。FictionalDataPolicy 按精确路径与固定 SHA-256 接受这两份文件，新增篡改/邻居/错误路径拒绝测试；无宽泛目录豁免。

### 本轮验证记录与剩余项

静态 readback：22 roster 项/11 延期项与 §3/§4.6 authority 并集一致，Kotlin 类型文件/iOS 来源/22 合同方法引用存在；63 状态元数据；raw Color/非零 dp/sp 扫描通过；`git diff --check` 通过。Material3 1.4.0、Compose Test 1.12.1、Robolectric 4.17 的关键 API/注解已对照本机批准缓存 JAR，未联网。

未验证：Kotlin/Compose 编译、Gradle DSL 执行、96 tests 的真实执行与 XML 归组、lint、G1 回归、Material 日期内部控件、真实返回手势/Insets/弹层隐私、L3、cursor-agent 独立复核。图标 XML 与许可已静态核验，实际资源加载仍待宿主验证。T015/T016 当前是可审查实现，不能据此报告 gate PASS、checkpoint 完成或负责人验收；未修改只读规格复选框。


### 宿主编译失败修复与 D12 资源接入（2026-11-06）

宿主日志 .handoff/logs/2026-11-06-host-s0-08.log 的 compileDebugKotlin 因 toggleable 第四位置参数类型不符失败；其他门禁没有形成本轮 PASS。现改为 value/enabled/role/onValueChange 全具名参数；clickable/selectable 的布尔位置参数、DatePicker state 也改为具名。已对照本机 foundation 1.12.1、M3 1.4.0 AAR 中的签名/参数名核对，ModalBottomSheet/DatePickerDialog 仍使用正确的默认参数与具名参数，未新增依赖。未运行 Gradle，不据静态检查宣布编译已通过。

新增 entry/layout map（原 tags 保留）：

| screen | visible control | identifier | mutates data? | width owner / code |
|---|---|---|---|---|
| DS-TITLE-ACTION/icon | 日历图标 | DS-TITLE-ACTION-icon-calendar | 仅内存计数 | S0ComponentCatalog.kt → FcTitleIconButton，≥44 |
| DS-TITLE-ACTION/icon | 资料库图标 | DS-TITLE-ACTION-icon-library | 仅内存计数 | S0ComponentCatalog.kt → FcTitleIconButton，≥44 |
| DS-TITLE-ACTION/icon | 筛选图标 | DS-TITLE-ACTION-icon-filter | 仅内存计数 | S0ComponentCatalog.kt → FcTitleIconButton，≥44 |

宿主需从 android/ 执行（本轮未执行）：

```sh
./gradlew assembleDebug lint
./gradlew :app:s0G1 :app:s0G2
./gradlew :app:testDebugUnitTest --tests '*FictionalDataPolicyTests' --tests '*PrivacySourceScanTests'
```

G1 预期 39；G2 仍 96（6+63+22+5），联合 135。图标来源/转换/许可/assertions 扩充在既有 ComponentCatalogTests 用例内，未改代表状态数或减弱断言。隐私定向用例数见下方静态统计记录，真正执行与 APK 打包证据仍由宿主提供。

静态方法统计：FictionalDataPolicyTests 16、PrivacySourceScanTests 10，定向命令预期 26 tests；新增 3 个精确许可路径/篡改/邻居拒绝用例。此数量仍不是运行结果。

## S0-06 T022～T024：双端共享向量 runner（2026-11-05，待宿主验证）

D06/D11 已由负责人于 2026-11-03 批准：S0 正常样例只做最小纯 Kotlin
`credit-ledger.balance`，完整业务留 S1；只有日历规则必填 IANA `timeZone`。
格式权威仍是 `specs/007-android-port/contracts/test-vector-format.md` §1～§2；
本轮不修改契约、iOS 产品代码、scheme 或 `s0/crypto`。

### 清单与证明边界

- `shared/test-vectors/runner-conformance/`：72 个单向量 JSON，15 正例、57 负例
  （44 格式拒绝、13 比较失败）。`meta.tags` 均含 `fictional-data`。
- `shared/test-vectors/s1/course-packages/`：5 个正常行为样例。
  `s1-package-ledger-balance` 对齐 S1 plan §5.1 的稳定 ID；其余 `s0-ledger-*`
  是 S0 算术/构造边界，不能算作 S1 13 个用例已完成。
- Conformance 仅证明基础设施；test-only `fixture.*` 不进入正常样例 registry，
  不读取 `then` 生成结果。负例通过 `meta.conformance.outcome/path` 声明预期拒绝。
  `filename`、`duplicate`、`mutation` 是外层测试驱动选项：分别替换传入文件名、
  对同一 runner 重复装载、注入坏 JSON/坏 UTF-8/非 object meta。
  原始 fixture 保持合法 JSON 和既有虚构标记，FictionalDataPolicy 不放宽。
- 每端按相对路径排序，逐文件输出 `VECTOR id=… path=… sha256=…`，另输出
  `VECTOR-SUMMARY conformance=72 positive=15 negative=57` 与 `normal=5`。
  SHA-256 针对仓库原始 UTF-8 字节，mutations 不改变源文件或清单摘要。
  Android Parameterized 的数量是 discovery inventory；执行是否通过以 JUnit XML 为准。

### 双端 op 映射

| 向量 op | iOS 测试 adapter / 产品入口 | Android Kotlin 运算 | 投影与默认值 |
|---|---|---|---|
| `credit-ledger.balance` | `ios/FineCoachTests/SharedVectors/SharedVectorRunner.swift` 的 `balance` → `CreditAdjustment.init`（`ios/FineCoachApp/Core/Domain/CreditLedger.swift:49`）→ `CreditLedger.balance(totalCredits:adjustments:)`（同文件 `:95`）；已有测试 `ios/FineCoachTests/CoursePackages/CreditLedgerIdempotencyTests.swift:10`、`:35` | `SharedVectorRunner.balance` 验证并投影 adjustment → `android/app/src/main/java/com/ignacioli/finecoach/domain/CreditLedger.kt` 的 `CreditLedger.balance` | `args.totalCredits`、`args.adjustments` 全部显式给出；结果 `{balance: Int64}`。不 clamp、不去重、不筛选 package，不声称完成/重开业务或持久化幂等 |
| `fixture.value` | test-only runner 从解析后的 `args.value` 产生结果 | 同名 test-only 分支 | 无默认值；返回输入数据，不读取 then；供投影/引用/比较验证 |
| `fixture.fail` | test-only `FixtureDomainFailure`（非产品错误） | test-only `DomainFailure` | `args.error` 必填，必须为契约稳定 token；首错停止，保留前一步 state |
| `fixture.calendar` | test-only value 分支 + IANA zone 验证 | 同名分支 + `ZoneId` 验证 | `given.timeZone` 必填；LocalDate/LocalTime 原始 wire 投影比较；不冒充日历业务实现 |

余额 adapter 的每笔 adjustment 必填字段为 `id`、`packageID`、`direction`、
`amount`、`reasonKind`、`sourceEventKey`、`createdAtUTC`。UUID 与时间全部来自向量，
`amount` 是有符号 64 位整数且构造时须为正，`direction` 只接受 `debit/credit`。
S0 受控子集的 `reasonKind` 只接受 `sessionComplete/sessionReopen/appointmentAbsent/adhocSession`；
不接入需要额外 reasonText 的 `manualCorrection`。Swift 使用 initializer 明示的
`reasonText=nil`、`linkedSessionID=nil`、`linkedAppointmentID=nil` 默认（产品 `CreditLedger.swift:55-57`），
Kotlin 算术投影不包含这三个字段。其余字段没有默认值，不补当前时间、不生成 UUID。
样例 adjustment 的 packageID 显式一致；余额函数本身不校验关联，也不按 event key 去重。
无 adjustment 时仍须显式提供空数组。`given.clock.now` 必填，算术不消费时钟；
`createdAtUTC` 独立显式提供，不能由本机时间补齐。

Android 运算逐行对应 Swift `CreditLedger.swift:96-105`：初始 totalCredits →
按数组顺序 debit 减 amount / credit 加 amount → 返回余额。Swift Int 在支持设备上是
64 位，Kotlin 使用 Long；溢出不转换为成功值或 DomainError（Kotlin exact arithmetic
会失败，Swift 产品算术会 trap），本批没有溢出样例。非法 amount 样例先由 Swift
真实 `CreditAdjustment` 构造器抛 `invalidNumber`（`:61-62`）；Kotlin adapter 用相同
前置约束映射 token，不声称 Kotlin 已实现完整 CreditAdjustment Domain。

### 格式、引用与比较

Android 的 test-only `VectorJSON` 严格解析 JSON，拒绝尾随内容、无效 escape 与
重复 object key；UTF-8 decoder 使用 REPORT。iOS 用 Foundation JSONSerialization，
先检查 UTF-8；两端都把解析失败报告为 `vector=<id或文件名回退> path=/ kind=format`。
映射不覆盖通用 JSON 的所有 parser 扩展差异；新增输入边界须先补共同 conformance。

必需五键、可选 object meta、ID/文件名、真实 rule registry、then 至少 state/error、
已登记 op/args 都验证。rule registry 对照当前 M1A spec 的 FR-001～045 与 M1B 的
FR-001～034，静态自检已核对连续编号确实存在；未知编号不会仅因匹配正则而接受。
未知 meta 成员忽略。只有 `args` 内的精确单键 `$ref` object 会被解释；
JSON Pointer 解 `~1/~0`，从文件根或运行时 `/results/N` 查找，缺目标/前向引用/
非法数组索引均为格式错误，不能计入 DomainError。

有序调度先验证 action registry，再依索引执行，结果按原索引暂存；首 DomainError
停止。error 比较稳定 token；同时给 state/error 时比较失败前最后成功结果。
object 是 subset projection、键序无关；数组顺序和长度精确，只有明确的
`trainingFocus` 使用 Set<String> 语义（自然去重）。Decimal 保持 schema canonical
string 精确比较，不转浮点；`*AtUTC` 按 instant；LocalDate/LocalTime 投影精确比较。
整数、布尔、enum、字符串、null 和缺失分别比较。错误带 vector id 和字段路径。
正常样例与 conformance 独立发现，缺目录/空集失败，不 XCTSkip/ignore。

### FR-018 / FR-012 登记

- FR-018：**已有断言于 `ios/FineCoachTests/ActiveSession/SessionActivityHookTests.swift:18`，
  非纯 Domain 单测**。测试 `testStartReopenAndTwoFictitiousStudentsKeepOneActivityPerSession`
  在 `:15-17` 通过 fixture 的真实 `sessions.startOrOpen(studentID:)` 两次打开同学员，
  `:18` 比较稳定 Session ID。未来共享 adapter 入口为
  `ActiveSessionUseCases.startOrOpen(studentID:trainingFocus:)`
  （`ios/FineCoachApp/Core/Application/ActiveSessionUseCases.swift:94`），
  需要测试 persistence/activities fixture，不能映射到余额 runner。
  本次未注册该 op，未实现 S1 开课业务。
- FR-012：规则在契约 §4 已写明，**确认门槛的共享测试/adapter 映射仍未确认**。
  已定位 `CoursePackageEditorView.swift:63-76` 的 `save()`：未过期且余额非零时等待确认，
  `:81-83` 的 `confirmEndActiveAndSave()` 才调用保存。它是 editor 行为，不能以
  `CoursePackage.ending(now:)`（产品 `Core/Domain/CoursePackage.swift:77`）替代。
  已有 `CreditLedgerIdempotencyTests.swift:138` 只证明 ending 转换和重复结束拒绝。
  UI/用例层门槛的等价双端向量入口及自动化断言仍待 S1 核实；不改产品来消除此缺口。

### 宿主机运行与预期（本轮未运行）

从 `android/` 运行：

```sh
./gradlew :app:s0G6
```

预期 `VectorFormatTests` 72 tests、`SharedVectorTests` 5 tests，合计 77，
0 failures/errors/skips。G6 复用现有 AGP test runtime，锁定两类精确数量；
finalizer 同时检查 task 实际执行、非空 XML、suite 集、testcase 节点与失败/skip 节点，
拒绝 NO-SOURCE、被跳过或旧 cache 结果。报告在 `app/build/test-results/s0G6/`，
清单 stdout 同时进入 XML。不修改其他 gate。

从产品根由 Claude 宿主设置并记录可用 destination 和独立 DerivedData，再运行：

```sh
xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachTests \
  -destination "id=$S0_IOS_DESTINATION_ID" -derivedDataPath "$S0_IOS_DERIVED_DATA" \
  -only-testing:FineCoachTests/VectorFormatTests \
  -only-testing:FineCoachTests/SharedVectorTests test
```

这两个变量是 plan §5 的宿主输入，本轮未设置或核实；未设置即 BLOCKED。
XCTest 预期 2 个测试方法，内部逐文件执行 72 conformance + 5 正常向量，
0 failures/errors/skips；数量与 Android Parameterized 的 testcase 数不能混为一谈。
双端同一清单的 id/path/SHA-256/count 全部一致才满足 G6，Android 独绿不代表双端通过。
既有 iOS build/unit/integration 门禁仍交宿主执行，定向 runner 不替代这些门禁。

定位方式：XCTest 从 `SharedVectors/SharedVectorRunner.swift` 的 `#filePath` 向上四层
到产品根；Gradle 为 G6 设置 `finecoach.sharedVectorRoot` 指向同一产品根下目录，
将整个共享目录声明为 task input。文件不复制进 iOS bundle，既有 crypto 向量不改。
新增三份 Swift 文件仅加入 FineCoachTests 的 PBXFileReference/PBXBuildFile/Sources；
挂在已有 Backup group，用 `../SharedVectors/…` 指向测试目录，无产品 target membership。

本轮状态：实现已写入；只做静态 JSON、清单/SHA-256、rule registry、membership 与 diff
自检。未运行 Gradle、xcodebuild、模拟器或设备，编译/运行通过、双端实际执行清单一致性、
cursor-agent 独立复核及 T023/T024 完成门禁均 **未确认**。不修改只读 tasks 的 checkbox，
不 commit。本轮没有新增用户交互，entry/layout map 不适用，未宣称视觉验证。

静态源清单摘要（按相对路径排序，每行 `path<TAB>sha256<LF>`，不是运行证明）：
`f8c47f29eb9b3d6a81e3668ebf0926b4ec7e7bd1b0c566aa14bc493054c0c639`。
正常样例文件均在 `shared/test-vectors/s1/course-packages/`，前缀为 `m1b-fr-015__`：

| vector ID（文件名末尾加 `.json`） | SHA-256 |
|---|---|
| `s1-package-ledger-balance` | `d0c2dce3738f5889fe3d9d72a3c80ab0042985b022bf1775baa601920ad61bb6` |
| `s0-ledger-empty` | `65a23d94c02ffb84a587665ee07249f43a032bceada89d64390b523d92fab74f` |
| `s0-ledger-zero` | `f401d8d49d7ebafe7df160bbb3b9c05d8b77ab3118bb614c50c242a866010abf` |
| `s0-ledger-negative` | `807c8f2aaf91ab274490fa325350f8ce0e28c0627272a011275ad3907a11dd89` |
| `s0-ledger-invalid-amount` | `70c8cdeeace790bce6a5fa3bc5cd904e0b0e7af93dc1559ed4f5531bcb9e103d` |

`finecoach.sharedVectorRoot` 同时配置到标准 Test tasks，避免新增测试只能被 G6 单独运行、
而使全量 `testDebugUnitTest` 因缺路径失败；标准任务和 G6 均声明同一共享目录 input。

## S0-12 T025：debug 种子、Release 隔离与安装（待宿主验证）

依据 S0-FR-120/121、S0-NFR-001 和 S0 plan §4。原先两个失败占位任务已替换为真实
实现；没有新增业务表、功能页面、main 源集接口、权限或依赖。所有 seed 文件位于
`app/src/debug/java/com/ignacioli/finecoach/seed/`，声明 `fictional-data`。
本节是可审查实现记录，不代表 T025/T026、checkpoint 或负责人验收已通过。

### 显式触发与权限边界

选择 debug APK 自带的 framework `DebugSeedInstrumentation`，targetPackage 为本应用；
不依赖 androidTest APK、JUnit runner 或 UTP。宿主通过 `adb shell am instrument -w -r`
启动，在 instrumentation worker thread 上阻塞执行 Room，结束时返回结果。
`Instrumentation.start/onStart/finish` 均为早期公开 API，适用于 API31～33；
[官方 Instrumentation 文档](https://developer.android.com/reference/android/app/Instrumentation)
说明其独立线程与 finish 生命周期。当前 API31/32/33 的实际运行仍待宿主确认。

它是 debug manifest 的顶层 instrumentation 声明，不是 exported Activity/receiver；
普通第三方无法经 Activity/广播调用种子。入口在写库前还要求连接 shell 提供的
`UiAutomation`（使用 `FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES`，不执行 UI 操作、
不读取屏幕、不采用 shell 权限）。普通应用直接调用 startInstrumentation 时没有该连接，
入口失败且不写库；系统/获授权 adb 的 automation 属于可信调试边界。
[framework 源码](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android12-release/core/java/android/app/Instrumentation.java)
的 getUiAutomation 无连接时返回 null。此设计不新增 exported 应用组件或权限，也不需要 root；
Release APK 不携带 instrumentation。宿主需验证普通应用触发被拒及三个 API 的 shell session
可用性，不能把静态源码依据视作设备安全验证。只对专用虚构模拟器运行安装任务。

**已停用的 S0 独立触发与输出合同（历史记录）**：S0 曾通过独立 instrumentation 验证 metadata 样例及固定数值日志。当前入口已由 T019 接管，不再使用本段旧触发/输出约定；实际命令、失败非零规则和唯一预期输出见本文「S1 T019：真实 seed 与一键安装」（rows 1149/1138/1088）。seed 日志仍只含版本/计数/固定状态，PID/时间仅用于关联本次事件，不含业务内容。

### 种子记录表与持久性

`DebugSeed.open(context)` 用当前真实 `FineCoachDatabase` schema 1，在
credential-protected 内部目录单独打开 `finecoach-debug-seed.db`，不访问
`FineCoachDatabaseFactory` 的 `finecoach.db`。没有复制或删除现有用户数据，也没有 reset 入口。
S0 壳和组件目录仍不读业务库；此独立文件不是可向产品库导入的数据包。

| schema / table | key / 内容 | seed 行数 | 可见样例入口 |
|---|---|---:|---|
| Room 1 / `store_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL)` | `debug_seed.declaration = fictional-data` | 1 | 无 metadata 编辑页面；debug 壳 →「基础组件样例」（`s0-open-catalog`）→ 既有 catalog |
| 同上 | `debug_seed.dataset_id = 00000000-0000-4000-8000-000000000025` | 1 | 同上，组件展示不依赖 metadata |
| 同上 | `debug_seed.clock = 2026-01-01T00:00:00Z`，固定 UTC Clock | 1 | 同上 |
| 同上 | `debug_seed.version = 1` | 1 | 仅种子结果，不提供功能页面 |
| 同上 | `debug_seed.rows = 5` | 1 | 仅种子结果；计数包含版本/条数两行，排除 Room/framework 内部行 |

五行均为本轮手工编造的基础设施值，不对应真实 Coach/Student。FictionalDataPolicy
继续扫描 seed 文件名/内容/声明；不新增宽泛豁免。独立库不用生产 factory 的当前时间 callback。

loader 在一个 Room transaction 内运行 contributor、验证所拥有行并写版本/条数；同版本
只验证、不重新 install，重复安装/显式触发或重开不新增行。升级只向前、保留旧数据，
contributor 失败整笔 rollback；降级、固定值冲突、同版本缺行/计数不一致拒绝，不自动修复。
入口 commit 后 close/reopen，再装载验证同一结果，之后才记录 ok。普通应用启动不自动 seed。

### 宿主命令与预期

先按本文批准的 JDK21/SDK/cache 配置，从 `android/` 运行：

```sh
./gradlew :app:testDebugUnitTest --tests '*DebugSeedTests'
./gradlew :app:s0SeedIsolation
./gradlew :app:s0InstallSeededDebug -Pandroid.device="$S0_DEVICE_SERIAL"
./gradlew :app:s0InstallSeededDebug -Pandroid.device="$S0_DEVICE_SERIAL"
```

也可明确设置 `ANDROID_SERIAL` 后运行 `./gradlew :app:s0InstallSeededDebug`；两个输入同时存在
时必须完全一致，不默认挑设备。运行期间仅连接该一台设备，不热插拔。未指定、serial 非法、
多设备（含 offline/unauthorized）、目标不匹配、输入冲突均在安装之前失败。上面的 `s0InstallSeededDebug` 不是当前验收命令；旧 installDebug / `SEED version=1 rows=5` 合同已停用，预期输出只见文末 T019。

- `DebugSeedTests`：10 tests，预期 0 failures/errors/skips。覆盖固定 UUID/UTC clock、
  schema1 五行、重复装载及磁盘重开、版本升级/保留无关 metadata、失败回滚、降级拒绝、
  计数损坏拒绝、固定值冲突、虚构标记与日志格式。标准报告 `app/build/test-results/testDebugUnitTest/`。
- `s0SeedIsolation`：依赖 assembleRelease，用 AGP `SingleArtifact.APK` 定位实际输出；
  缺 APK/多 APK、缺 dex/manifest/resources table 或发现禁止内容均失败。逐 ZIP entry
  解压检查路径，以及 UTF-8/UTF-16LE/UTF-16BE 字节中的 seed 包、类名、固定标记与
  catalog/debug Application/入口名；包含二进制 manifest、资源表和所有 dex，不能只扫文件名。
  预期 `s0SeedIsolation: status=ok apk=… sha256=… dex=… manifest=1 resources=1`。
  当前不启用 shrinking/obfuscation；以后开启时必须重新评估名字扫描的证明边界。
- **已停用的 S0 安装合同（仅历史记录）**：原 `s0InstallSeededDebug` 曾通过 AGP `installDebug` 安装 S0 metadata 样例。该流程及其旧输出约定已由 T019 替代，不再用作当前安装/验收命令。当前实际流程、serial 参数及唯一预期输出见本文「S1 T019：真实 seed 与一键安装」（multi/single/empty 的 rows 分别为1149/1138/1088）。

隐私合同跟随本轮批准的固定 seed event 更新，只有指定 debug 入口中的一条精确 call 可用，
其他 source 日志仍拒绝；Release dex 额外拒绝 seed 包/tag。宿主还需回归：

```sh
./gradlew assembleDebug lint
./gradlew :app:testDebugUnitTest --tests '*FictionalDataPolicyTests' \
  --tests '*PrivacySourceScanTests' --tests '*CapabilityManifestTests'
```

### S1 扩展（T019，2026-11-09）

上面的 S0 五行 metadata、独立 `finecoach-debug-seed.db` 和10例 `DebugSeedTests` 是历史基础设施证据，保持不变。当前 `s0InstallSeededDebug` 已切到 S1 installer，实际命令/结果以本文末尾「S1 T019」为准，不再把 S0 五行 metadata 安装当 S1 交付。

S1 数据由独立的 debug-only `S1DebugSeed` 经真实 Repository 写入一份全新、显式标记所有权的 `finecoach.db`，这正是冻结 S1Runtime 默认读取的库；不替换产品 factory，不通过 S0 contributor 的同步事务调用会切 dispatcher 的 Repository。S0 contributor 接口仍为 S0 测试保留，未改其版本/UUID/clock/inventory。这个接线取代原先“给 S0 contributor 加业务行、把业务页面改读另一个库”的预案：后者需修改已冻结的 graph/factory 且会让默认 S1 读不到 seed。

只接受全新 app 数据目录，或完全匹配 dataset/version/scenario/complete 的既有 S1 seed。任何已有非 seed 数据库（包括空库）拒绝；重复执行只验证持久标记，不修改体验中编辑、删除、完成过的数据。初始化中断保留 installing 并非零，不自动 reset/repair。需要清理/更换场景由负责人另行决定，本工具不提供清库命令。Appointment 仍属于 S2，不造假数据。

本轮 execution record：变更为非 UI debug 基础设施；复用既有 catalog，无视觉设计 delta；
新增入口为 adb instrumentation，不新增用户交互，entry/layout map 沿用本 README 的 S0-08 map；
验证仅静态源码/API 签名、XML 和 diff 检查；Gradle 编译/测试、Release APK 检查、API31～33
设备触发/拒绝、安装重跑和负责人走查均未执行，T026 留给 Claude 宿主。未改只读 specs checkbox，未 commit。

## S1 T001：S0 绑定与接口冻结（2026-11-06）

工作目录与分支（writer）：

- worktree: `/Users/liyongqiang/gitrepo/ignacioli/FineCoach/.claude/worktrees/android-s1`
- branch: `feat/android-s1-coach-core`

### 本轮冻结摘要

- 新增 `core/domain/common` 共享值类型层：
  - `CommonTypes.kt`：稳定 ID、枚举、`Revision`、`SourceEventKey`、`CreditLedgerSourceEventKeyFactory`
- 新增 `core/application` 接口层：
  - `ApplicationContracts.kt`：Clock、ID generator、error/result 合同（不再承载 domain 值类型）
  - `RepositoryPorts.kt`：Student/Package/Exercise/Session/Template/History repository ports 与命令/记录命名；新增 coach-only `SessionSettlementNotePort`（`noActivePackage`，不得进入分享/导出）
- 新增 `navigation/S1Routes.kt`：
  - 只冻结 route pattern 与稳定 ID 参数（`studentID`、`coursePackageID`、`sessionID`、`templateID`）
- `ScopeBoundaryTests` 从 S0「无业务页/路由」更新为 S1 允许范围，保留隐私与能力边界断言（shortcut/assistant/notifications/widget/share/延期业务入口）；通知能力放开交接给 T013c（S1-D08）。
  - 路由守卫：`composable`/`navigation`/`NavHost` 仅允许 `S1Routes` 常量，`navigate` 仅允许 `S1Routes` 常量或 builder，禁止 `composable<T>`、`navDeepLink`、`deepLinks=...`；并对 `S1Routes` object 顶层声明（`val`/`var`/`fun`/`object`/`class`/`typealias`，含注解与修饰符）做白名单冻结。

### S0 接口与 gate 现状登记

- 已实现：`s0G1`、`s0G2`、`s0G6`、`s0Room`、`s0SeedIsolation`、`s0InstallSeededDebug`
- 已接入独立非空 Test gate：`s0G3`（DesignValueScanTests）、`s0G4`（EntryLayoutHarnessTests）；用法与独立报告目录见本文末尾 S0 G3/G4。
- `s0G5` 已接入 verify-only 截图门禁（T019）；`s0G8` 现行契约见本文「G8 聚合门」，已按 S1-D107 接入聚合测试。
- 向量 runner 与余额运算：
  - `app/src/test/java/com/ignacioli/finecoach/SharedVectorRunner.kt`
  - `app/src/main/java/com/ignacioli/finecoach/domain/CreditLedger.kt`
- seed 扩展点：
  - `app/src/debug/java/com/ignacioli/finecoach/seed/DebugSeed.kt` 的 `SeedContributor`
  - `app/src/debug/java/com/ignacioli/finecoach/seed/DebugSeedInstrumentation.kt`

### 依赖核对（无新增坐标）

- `androidx.compose.material3:material3`（BOM 解析为 1.4.0）
- `androidx.navigation:navigation-compose:2.10.2`
- `androidx.activity:activity-compose:1.13.0`
- `androidx.room:room-runtime:2.8.5`
- `androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0`（transitive）

以上均可在 `android/dependency-allowlist/resolved.txt` 定位到；本轮未改 `libs.versions.toml` 和依赖坐标。

### 宿主复核命令（T001 约束内）

```sh
# G0
./gradlew assembleDebug assembleRelease assembleDebugAndroidTest lint

# 四个既有 suite（T001 完成线）
./gradlew :app:testDebugUnitTest \
  --tests 'com.ignacioli.finecoach.InfrastructureConfigurationTests' \
  --tests 'com.ignacioli.finecoach.CapabilityManifestTests' \
  --tests 'com.ignacioli.finecoach.PrivacySourceScanTests' \
  --tests 'com.ignacioli.finecoach.StorageValueTests'

# s0G2 背后四个组件 suite（按 FQCN 逐一可追溯）
./gradlew :app:testDebugUnitTest \
  --tests 'com.ignacioli.finecoach.ComponentCatalogTests' \
  --tests 'com.ignacioli.finecoach.ComponentCatalogStateTests' \
  --tests 'com.ignacioli.finecoach.ComponentContractTests' \
  --tests 'com.ignacioli.finecoach.PlatformShellTests'

# s0G8 实际替代套件（不调用占位 task）
./gradlew :app:testDebugUnitTest \
  --tests 'com.ignacioli.finecoach.CapabilityManifestTests' \
  --tests 'com.ignacioli.finecoach.PrivacySourceScanTests' \
  --tests 'com.ignacioli.finecoach.BackupRulesTests' \
  --tests 'com.ignacioli.finecoach.StoragePrivacyTests'
```

预期测试数（按源码静态计数）：

- `InfrastructureConfigurationTests`: 4
- `CapabilityManifestTests`: 9
- `PrivacySourceScanTests`: 10
- `StorageValueTests`: 10

### 宿主实测（r8）

证据来源：`.handoff/logs/2026-11-06-host-s1-t001-r8.log`

- `./gradlew assembleDebug assembleRelease assembleDebugAndroidTest lint`：`exit 0`
- `:app:testDebugUnitTest --rerun-tasks` + `s0G1` / `s0G2` / `s0G6` / `s0Room` / `s0SeedIsolation`：均 `exit 0`
- unit：`321 tests`，`0 failures` / `0 errors` / `0 skipped`
- `ScopeBoundaryTests`：`19`
- 报告目录：
  - `android/app/build/test-results/testDebugUnitTest/`
  - `android/app/build/reports/lint-results-debug.*`

编排方已修正 `ScopeBoundaryTests.kt:442-444` 的 `const val` 正则，本轮在该修正基础上继续收敛。

### S1 T013c 休息通知能力

批准能力新增且仅新增 `android.permission.POST_NOTIFICATIONS`（API33+ runtime）。API31/32 不申请该 runtime 权限。无 INTERNET、精确闹钟权限或网络 API。内部非 exported receiver 仅用于当前 Session 休息提醒。
通知标题「休息结束」、正文「可以继续训练了」，不含任何身份、训练值、课包或备注。每 Session 一个 inexact alarm，±15秒替换；跳过/关闭/结束/放弃取消。使用 `setAndAllowWhileIdle`，系统可延迟投递；不承诺精准120秒系统通知。权限拒绝或系统关闭不阻断前台记录/休息计时。进程退出后由已调度 alarm 处理；设备重启不承诺保留。
DEVICE `RestNotificationPermissionTests` 由宿主在专用虚构 API31/32、API33+ 环境通过 `am instrument` 执行；agent 的编译与 JVM 结果不等于设备授权、展示或系统送达证明。

### S1 启动与 S0 隐私测试壳（S1-D20）

安装后正常启动 debug 或 release 都默认进入 S1，无需启动开关：

```sh
adb shell am start -n com.ignacioli.finecoach/.MainActivity
```

仅需要 S0 隐私壳的 debug 测试使用显式 extra；该壳不作为日常启动入口：

```sh
adb shell am start -n com.ignacioli.finecoach/.MainActivity --ez finecoachS0Shell true
```

`PrivacyCoverTests` 仅启动 intent 带此 extra，既有断言不变。通知点击使用原有稳定 Session ID，始终进入 S1。release 没有 S0 provider，即使传入该 extra 也不会进入测试壳。

## S1 T019：真实 seed 与一键安装

先按本文 setup 配置 JDK21/SDK/cache。以下命令从 `android/` 运行；`S1_DEVICE_SERIAL` 必须是宿主明确指定的专用虚构模拟器 serial，且只连接这一个设备（S1-D21 默认 API31/API36 分别执行）。

```sh
./gradlew --offline :app:s0InstallSeededDebug -Pandroid.device="${S1_DEVICE_SERIAL:?required}" -Ps1.seedScenario=multi
```

这一条命令 build Debug APK → `adb -s SERIAL install -r -t` → 停止目标进程以串行初始化 → shell-only `am instrument` → 关闭重开数据库验证 complete/version/rows → 校验 instrumentation code/result 和本次 PID/时间的唯一数值日志 → `am start -W -a android.intent.action.MAIN -c android.intent.category.LAUNCHER` 启动默认 S1（S0L3-W1：让 task 根 intent 与桌面一致，避免点击桌面图标重复压栈 MainActivity）。S1-D20 已在基线实现，不需要启动开关。每条 adb 命令都携带 serial；缺设备、冲突 serial、授权失败、安装/seed/日志/启动失败均非零。没有 `pm clear`、uninstall、reset 或自动库切换。相同命令可再执行一次，仍返回初始 inventory，保留教练体验更改。

场景参数：`multi`（默认，两位学员各一进行中，初始 `SEED version=3 rows=1149 status=ok`）、`single`（一进行中，rows=1138）、`empty`（无学员/训练，rows=1088）。场景只在首次空数据目录安装时选择；已有 seed 切换参数会拒绝，不能靠参数重建。dataset=`fictional-s1-coach-core-v3`，版本3，clock=`2026-11-09T00:00:00Z`，UUID 以 `72000000-0000-4000-8000-` 为前缀，学员尾号1～7；其余生成ID使用固定顺序1000起，显式分段使用800～900，动作/组使用10000～13053（以 JSON 为准）。只含虚构内容。

`rows` 是首次成功初始化时实际查询到的业务行数加 S1 自有 metadata 行数（含 rows 本身，不计框架、generation、created_at）；不是后续体验中的当前行数。重跑不要求已经删除/编辑的 seed 内容恢复到初始值。首次 marker 之前经 Repository 读取核验初始状态；重开持久性由 JVM 文件库测试与 instrumentation 二次 open 证明。写入失败会保留 installing 并失败，人工决定如何处置。

隔离检查：

```sh
./gradlew --offline :app:s0SeedIsolation
```

实际执行 `S1DebugSeedTests` 12例与 `S1SeedIsolationTests` 4例（报告 `app/build/test-results/s1SeedChecks/`），精确非零、0 failures/errors/skips；随后检查实际 Release APK 的全部条目和 UTF-8/UTF-16 dex/manifest/resources 字节，拒绝 S0/S1 seed、fixture入口及标记。预期包含两条 `S1-SEED-CHECK suite=… tests=12/4 failures=0 errors=0 skips=0`，以及 `s0SeedIsolation: status=ok apk=… sha256=… dex=… manifest=1 resources=1`。不连接设备。

完整改动清单、实测日志、初始场景与未验证项见 [T019](docs/s1/T019.md)；共享13向量与宿主 iOS 命令见 [T017](docs/s1/T017.md)；入口总表及未确认断言见 [implementation map](docs/s1/implementation-map.md)。安装/界面 runtime、负责人走查、独立复核与 T020 仍由宿主执行，不能用 JVM/Release 扫描代替。

## S1 T020：负责人走查入口

**已准备，待负责人走查。** 最终安装命令（从 `android/` 运行，将 `<SERIAL>` 替换为明确指定的目标设备）：

```sh
./gradlew --offline :app:s0InstallSeededDebug -Pandroid.device="<SERIAL>" -Ps1.seedScenario=multi
```

[负责人走查：安装条件、核心页与交互清单](docs/s1/walkthrough.md) · [entry/layout总表](docs/s1/implementation-map.md) · [T020宿主证据与PENDING](docs/s1/T020.md)

T020 fix1：seed v2 使用周十节（同名两人）、李思远、林小禾、王小明、长名字样例与孙已归档等合成数据。session/模板引用内置杠铃平板卧推、俯卧撑、平板支撑；catalog 没有 cardio mode，跑步机使用 sessionOnly。所有场景先走与启动相同的 catalog 同步路径，新增 542 catalog + 541 name claim 行，multi/single/empty 分别为 1149/1138/1088。旧 v1 seed 由宿主决定卸载后重装，agent 不执行清库。详见 [T020-fix1](docs/s1/T020-fix1.md)。

负责人追加的明文数据入口：[seed fixture 字段与重装指南](docs/s1/seed-fixture.md)。内容统一在 `app/src/debug/assets/seed/s1-seed.json`，当前 v3 保持 rows 1149/1138/1088；loader 与 installer 从该文件读取版本、时间、业务内容与预期行数。Release 不包含 fixture，内置引用缺失直接失败。

## S0 恢复第 4 步：T019 / S0-14（2026-11-10）

基线 `c41d1d4`，worktree `android-s1-conf`，branch `feat/android-s1-conformance`。开工 tracked/staged/untracked 全空，worktree gate PASS。本轮单写者；subagent 仅只读核对工具约束。未提交、未推送、未修改任何截图基线或产品 UI。

从 `android/` 执行：

```sh
./gradlew :app:s0G5
./gradlew :app:s0Conformance
```

agent 运行上述任务一律从产品根调用共享宿主锁 wrapper：

```sh
.handoff/bin/agent-test.sh --task s0G5
.handoff/bin/agent-test.sh --task s0Conformance
```

本轮为 wrapper 添加了仅允许这两个 verify task 的 `--task` 模式，原有测试类模式保留；完整日志位于 `.handoff/logs/agent-test-android-s1-conf-*.log`，本轮输出另 tee 到 `s0-step4-*.log`。wrapper 位于共享 ignored `.handoff`，不在产品 Git diff 中。

`s0G5` 只执行 `ComponentScreenshotTests`，使用 T016 debug catalog 的主按钮样例；组件基线独立于 environment，缺 `screenshot-baselines/components/DS-BUTTON-default.png` 时明确失败，不自动创建。结果：1 test / 1 expected failure / 0 skipped，退出 1；G5 保持 BLOCKED owner baseline。`s0G5` 的前后 baseline manifest 相同；独立 baseline guard 的 staged/unstaged/untracked/committed、ignored-untracked、digest 变化与受信批准正例共 7 tests 通过。详见 [T019](docs/s0/T019.md)。

`s0Conformance` 使用真实 `ActiveSessionScreen` + test-only Room fixture；固定 API36 / NATIVE / 390×844dp / density2 / fontScale1 / zh-CN / 随包 Noto Sans SC。图层来源和坐标约定见 [conformance assets](design-assets/conformance/README.md)。产物位于 `app/build/outputs/conformance/P0-a2-training.{android.png,nodes.json,triptych.png,report.json,report.md}`。

**当前状态：VALID_FIXTURE / 设计一致性FAIL（预期非零）**。宿主已修复编辑器预填等待和暂停clock下真实触摸无法完成的问题，本轮保留逐帧等待120、再推进500ms、临时autoAdvance真实点击plus后恢复暂停的流程，122.5断言通过，无SetText/IME注入。双次fresh Room/composition渲染hash一致：`c190e2890406e8b3c89c0f247baba457aaaff4229801cbd83ad414edc9f28a64`。S1-D30规定每层top/bottom/viewport，背景不再套用top offset；capsule由测试侧LayoutInfo共同父Row定位，无产品tag改动。最终51项：通过1、UI_DEVIATION40、missing10、不可见0，故s0Conformance退出1；raw像素差异37.2325%。ComponentContractTests27 + ConformanceVisibilityTests4 + ConformanceComparisonTests10共41/0/0。剩余偏差交step6，不修产品UI、不放宽容差、不改基线；本轮未看图，负责人视觉验收PENDING。详细计数、逐轴容差、top10、观测限制及日志见 [S0-14执行说明](docs/s0/S0-14-conformance.md)。

### 负责人专用：组件基线录制（agent 禁止执行）

负责人先亲自走查并批准样例，再从 `android/` 手动执行下列命令。复用 T003 已核实的 Roborazzi 1.77.0 record/verify 属性与显式 baseline 路径；本轮未执行该命令。

```sh
./gradlew :app:testDebugUnitTest --tests 'com.ignacioli.finecoach.ComponentScreenshotTests' -Proborazzi.test.record=true -Proborazzi.test.verify=false --rerun-tasks
```

常规 `testDebugUnitTest` / `testReleaseUnitTest` 排除 `ComponentScreenshotTests` 与 `TrainingConformanceTests`（`app/build.gradle.kts`）；只有显式传入 `-Proborazzi.test.record=true` 时才保留 `ComponentScreenshotTests`，因此上面这条命令仍能选中该类。`TrainingConformanceTests` 只在 `s0Conformance` 中运行。

随后负责人登记文件清单、SHA-256 与批准 commit，再运行 `s0G5`。这不自动完成 T020，agent 不创建/批准/更新基线。宿主 S0-13 需接入 T019 baseline guard 的前后检查；本轮未修改 host gate。

### S0 G4：入口与布局工具

从 worktree 根运行 `.handoff/bin/agent-test.sh --task s0G4`，只运行 `EntryLayoutHarnessTests`。
可复用 `assertEntryClick(tag, callbackCount)` 和 `assertFullContentWidth(tag, parentContentTag)`；tag 指向真实点击节点和父内容区。
报告：`app/build/test-results/s0G4/`、`app/build/reports/tests/s0G4/`（相对 android/）；空测试、skip、失败均拒绝。样例 map 与结果见 `docs/s0/T017.md`。

### S0 G3：页面组合设计数值扫描

从 worktree 根运行 `.handoff/bin/agent-test.sh --task s0G3`，只运行 `DesignValueScanTests`。
扫描 main Kotlin（含壳、features、navigation）及 debug Kotlin；main `designsystem/` 定义处排除，测试 fixture 不进入源码扫描目录。仅间距位置允许原始零值。
通过 `finecoach.sourceRoot` 指定 `app/src`；报告位于 `app/build/test-results/s0G3/`、`app/build/reports/tests/s0G3/`，打印实际文件数、分目录违规数及文件:行。空测试、skip、失败均拒绝。

## T011 / CP1：安全骨架 checkpoint evidence（2026-11-16）

**证据已归档；CP1 BLOCKED，L3 未取 / PENDING，不称安全基础设施完全就绪。** 本节只收证据，不修改 T011 复选框。依据 canonical specs `/Users/liyongqiang/gitrepo/ignacioli/specs/FineCoach/007-android-port/s0-infrastructure/` 的 `tasks.md` T011、Phase 1 Done when / Proven by 与依赖表、`plan.md` §6、`spec.md` FR-020～042/070～072；完成口径遵循 `CLAUDE.md`「Checkpoint completion」及 `design/design-system/components.md` §1.4。

本节及下两节的定位约定（均可直接在本机读取）：

- `H=/Users/liyongqiang/gitrepo/ignacioli/FineCoach`；所有 `.handoff/...` 都相对 H，不能把已移除的测试 worktree 当日志根。
- `E=H/.handoff/logs/t028-s0-android-20261116-090232-90127/`；`D=H/.handoff/decisions/android-port.md`，使用其中具名 S1-D100～111；本轮范围裁决见 `H/.handoff/dispatcher/step7-decisions.md`。
- 产品证据基点完整 HEAD/base 均为 `48a98e4da048c55d0b3f602ae419b0ca76d41a82`，来自 `E/summary.txt` 首行及 `E/runlist.tsv`；T028 当时 branch=`test/s0-t028-host-gate`。本轮 writer 在 `docs/s0-checkpoint-evidence`、同一 HEAD，仅编辑 README；不是本轮新跑，也不是本轮设备重测。
- T028 host 执行/核验责任人为 hybrid dispatcher（S1-D101 角色迁移、S1-D108）；本轮整理责任人为 Codex。该既有 host 复跑满足 T011 的「跑」及 T021 的「Claude 复跑」角色要求，本轮不再运行。独立复核责任人为 Cursor（T029）；负责人承担参数、基线及人工批准。

**T011 必跑 host 证据。** 以下历史命令 cwd 为 T028 worktree 的 `android/`。每行在 `E/summary.txt` 有完整 command/rc/count/duration/report/log；已读取相应 log 和归档报告。共同命令前缀原文为 `./gradlew --offline --no-daemon --no-build-cache --rerun-tasks -Proborazzi.test.record=false -Proborazzi.test.verify=true`，表中任务接在此前缀之后。所有 JUnit 行的 failures/errors/skips 均为 0；G0 按构建/lint 口径，不能写成 0 tests 的测试 PASS。

| 门 / command 任务 | rc / 实际数量 / 耗时 | report 与原始 log（相对 E） | 结论 |
|---|---|---|---|
| G0：`assembleDebug assembleRelease assembleDebugAndroidTest lint` | 0；lintErrors=0、APK=3；49s | `reports/G0/lint-results-debug.xml`、`reports/G0/apk.sha256`；`G0.log` | PASS，构建证据，不是安装证据 |
| G8：`:app:s0G8` | 0；78；50s | `reports/G8/TEST-*.xml`（8 suites）；`G8.log` | PASS，不替代系统隐私验证 |
| Room：`:app:s0Room` | 0；18；22s | `reports/Room/TEST-*.xml`；`Room.log` | PASS，骨架/值/存储隐私；不外推业务库迁移 |
| environment smoke：`:app:s0EnvironmentSmoke` | 0；7；27s | `reports/smoke/TEST-*.xml`；`smoke.log` | PASS；KDF 在此仅为 JVM host smoke |

**依赖与非 host 证据逐项归档。** 未留存的字段明确记缺证据；不以 task 已勾选替代运行原文。

| 要求 / 依赖 | 来源、command / rc / count / HEAD / 责任人 | 状态与边界 |
|---|---|---|
| T001：路径、P0-07、环境及版本批准 | 本文 Environment 的「路径与基线」「当前批准状态」及版本批准表；历史基点 `b3980c8d409d791997b80b9c0718a154131cc267`。负责人 2026-11-03 批准版本，JDK Temurin 21.0.13+9 arm64；2026-11-04 接受 Jetifier beta10 例外，非 UTP alpha 例外 | 版本逐项来源保留在原表；不是本轮重新批准或安装 toolchain |
| T002/T003：工程、crypto、环境基线 | 本文「构建」「T003 验证结果（2026-11-04）」：`assembleDebug lint` rc0；smoke 冷12s/暖5s各7例，record=true拒绝rc1；负责人亲录并批准 environment 基线；当前构建/smoke 以上表同 HEAD T028 为准 | PASS（各自范围）；historical record 不在本轮执行 |
| T004/T005：merged manifest、规则/依赖/源码守卫 | 本文 S0-03 targeted 与修复轮保留过程；当前 `E/G8.log`：InfrastructureConfiguration 4、CapabilityManifest 9、BackupRules 5、PrivacySourceScan 11、StoragePrivacy 3、PrivacyCover 11、FictionalDataPolicy 16、ScopeBoundary 19，共78；对应8份XML，rc0 | 自动 PASS；历史 FR-034 固定事件实现 PENDING 的记录不改写。后续 seed 固定事件边界见本文 S0-12「显式触发与权限边界」；本节不由 G8 推定任意 logger 或系统行为已获证明 |
| T006：QPR2 三段九域系统解析 | D/S1-D100（2026-11-14），`H/.handoff/evidence/t006/2026-11-14-d2d-parser.txt` 原始系统文字。`emulator-5554`、AVD FineCoach_QPR2_API36_1、Android16/BE4B.251210.005、sdk_full36.1；`bmgr backupnow` + LocalTransport / GMS D2dTransport，D2D test mode；原文有 valid data-extraction-rules、九域 excludes、无 includes、无 backup data | device-transfer parser PASS；cloud 因 allowBackup=false 拒绝，**不是 cloud parser 证明**；cross-platform 无可观察入口且需 platform-specific-params，**BLOCKED→D10**。D100只给APK digest前缀 `f43209cfb514…`，该摘录无完整 shell 命令/逐命令rc/产品HEAD，缺证据，不补造 |
| T007/T008：Room 骨架与 synthetic migration | 本文 S0-04 字段策略、T008 修复轮；specs tasks T007/T008 的负责人批准注释：唯一 store_metadata、synthetic V1/V2；JVM s0Room18，历史设备迁移 `am instrument` 为2例 | 当前18例见上表；设备2例属2026-11-05历史，不是本次同HEAD重测。不可用JVM18例替代设备迁移 |
| T009：后台遮罩实现及实际入口 | 本文「样例 anatomy、testTag 与 entry/layout map」及下述代码 map；当前 G8 的 PrivacyCoverTests11（含API31/32展开） | 自动 PASS 仅证明调用/生命周期等测试合同，不证明系统快照 |
| T010：API31/32/33+ 系统遮挡、恢复、前台截屏 | 本文「T010：宿主 API 31 / 32 / 33+ 操作与文字证据」和「T010 宿主自动验证结果（2026-11-05）」；实际日志 `H/.handoff/evidence/2026-11-05-t010/api31/t010-api31.log`、`api32/t010-api32.log`、`api36_1/t010-api36_1.log`（后两项同一t010根）；脚本 `t010.sh`、`t010auto.sh`、`transitions.py`、`snapstat.py` 可读，执行责任人为Claude宿主 | 历史HEAD c381853，各记录安装/启动命令及exit=0、APK digest和build见下表；普通/弹层最终文字行0、阳性对照23～279；probe0→1、关闭后壳为1、前台PNG签名及内容。原partialRows误报FAIL及refined detector修正均保留（api31 与 api36_1 为 02:18:01、api32 为 02:18:04）；本轮不看图/不重算。tasks恢复状态仍将API31/32及弹层人工判定列DEFERRED，归集中L3，不能自行关闭 |
| T032 / D13：非ASCII双端KDF字节 | specs spec §7 D13：负责人2026-11-03选契约字节证明；本文「KDF 一致性证明」「T032 验证结果（2026-11-04）」；`H/.handoff/logs/2026-11-04-host-s0-02-t032-{jvm,device-am,ios}.log` | 历史 JVM4例；Android API36/BE2A.250530.026.D1、emulator-5554、BC，`am instrument -w -r -e class com.ignacioli.finecoach.PlatformCryptoParityInstrumentedTests com.ignacioli.finecoach.test/androidx.test.runner.AndroidJUnitRunner` 输出 `OK (2 tests)`；iOS iPhone17/iOS26.5(23F77)、CommonCrypto，定向 PlatformCryptoParityTests 2例/0 failures/TEST SUCCEEDED。历史日志未逐项记独立shell rc/HEAD，缺字段；不伪称48a98e4设备重测 |
| cursor-agent 复核 | 本文2026-11-06 T012/T013/T010复核通过历史记录；`H/.handoff/subagent/2026-11-16-t029-review.md` 对 `99c0cc5..48a98e4` 的独立一致性/入口/隐私复核通过；major/minor按D110/D111处置 | T029不是对所有历史系统场景的新实测；本轮README的独立review尚未取得/PENDING，由dispatcher另行收取 |

KDF 对照保留可直接核对的完整值：NFC/NFD 两端 key 均为 `02171f9cb0decb1812ab132a927109f42dfff580ff96bacb0acc3b25adab2fdb`；NFC UTF-8 输入 SHA-256 均为 `54a7a451447f7eb29db39828e92309c98034dd167261c476c396634f50473b95`。来源是上述历史结果表、iOS日志的 passwordNFC/passwordNFD 两行及共享 fixture；不把 G6 的77向量或本次JVM smoke充作这次设备/provider证明。iOS历史实跑命令见 `t032-ios.log` 开头（destination=`EFE2D5A0-4877-4682-BE79-7460C0C1E8C8`，derivedData=`/Users/liyongqiang/.cache/finecoach-android/ios-derived-t032`）。

T010三个历史环境均为指定serial `emulator-5554`，APK SHA-256均为 `c71d9e0ccb16a078f9f749af6b9c8501a9c176f9cf9596171abc36fbbe21d5be`；完整fingerprint和逐命令exit见各日志开头。它们只绑定c381853历史产物，不是48a98e4新系统验证：

| API / 日志目录 | fingerprint | 结果与人工边界 |
|---|---|---|
| 31 / api31 | `google/sdk_gphone64_arm64/emulator64_arm64:12/SE1A.220630.001.A1/9056438:userdebug/dev-keys` | refined textRows普通/弹层0；前台截屏正常；人工判定DEFERRED |
| 32 / api32 | `google/sdk_gphone64_arm64/emulator64_arm64:12/SE1B.240122.005/11418786:userdebug/dev-keys` | refined textRows普通/弹层0；前台截屏正常；人工判定DEFERRED |
| 36.1 / api36_1 | `google/sdk_gphone64_arm64/emu64a:16/BE4B.251210.005/14574095:userdebug/dev-keys` | 普通/弹层textRows0；前台截屏正常；日志02:04:16有负责人「QPR2 最近任务卡片看不到 sentinel」，不外推弹层或其他API人工批准 |

**CP1 entry/layout。** 本轮文档无新交互；历史 T009 的四个入口仍必须保留证据，不写成「CP1从未有交互」。完整逐行 map 见本文「样例 anatomy、testTag 与 entry/layout map」；实际代码为 `app/src/debug/java/com/ignacioli/finecoach/S0DebugApplication.kt` 的 `PrivacySample` / `SampleButton`：

| screen → visible control → identifier | 数据变化 | width owner / code |
|---|---|---|
| debug壳 → 打开虚构弹层 → `s0-open-dialog` | 内存dialogOpen | 壳Column安全区；SampleButton.fillMaxWidth |
| debug壳 → 交互探针+1 → `s0-probe` | 内存count，无持久化 | 同上 |
| debug弹层 → 交互探针+1 → `s0-dialog-probe` | 共享内存count，无持久化 | Dialog内Column.fillMaxWidth；SampleButton.fillMaxWidth |
| debug弹层 → 关闭弹层 → `s0-close-dialog` | 内存dialogOpen | 同上 |

**剩余与责任。** T001～T010/T032不是全部依赖关闭：T006仍未勾；T010人工判定按恢复记录仍DEFERRED。L3从未发生，明确未取/PENDING。OWNER? D10的bundleId/teamId/contentVersion与cross-platform后续验证、集中走查及系统证据最终认可；没有批准不得代负责人关闭。CP1只归档现有自动与历史证据，不宣称全量FR已满足。

D10 经负责人 2026-11-16 确认暂定 BLOCKED（Apple Developer Program 开通中），T006 跨平台段开通后补验（S1-D114）。

## T021 / CP2：设计门禁 checkpoint evidence（2026-11-16）

**自动设计门禁可运行的证据已归档；L3 未取 / PENDING，未完成人工视觉验收。** 依据 canonical S0 `tasks.md` T021（依赖T012～T020、T031）、Phase2 Done when / Proven by、`plan.md` §6 CP2。H/E/D及完整产品HEAD沿用上一节的定位约定；本节每个host结果均为2026-11-16 T028 dispatcher同HEAD复跑，非本轮运行。Codex整理，Cursor独立复核，负责人批准设计与基线；无新实现/测试。

**T021 必跑 host 证据。** cwd、共同Gradle前缀与CP1相同；`E/summary.txt`逐行给command/rc/report，原始log和归档XML均可定位。各JUnit数量后的failures/errors/skips均为0。

| 门 / command 任务 | rc / 数量 / 耗时 | report / log（相对 E） |
|---|---|---|
| G0：`assembleDebug assembleRelease assembleDebugAndroidTest lint` | 0；lintErrors0、APK3；49s | `reports/G0/{lint-results-debug.xml,apk.sha256}` / `G0.log` |
| G1：`:app:s0G1` | 0；39；24s | `reports/G1/TEST-*.xml` / `G1.log` |
| G2：`:app:s0G2` | 0；113；26s | `reports/G2/TEST-*.xml` / `G2.log` |
| G3：`:app:s0G3` | 0；42；30s | `reports/G3/TEST-*.xml` / `G3.log` |
| G4：`:app:s0G4` | 0；12；23s | `reports/G4/TEST-*.xml` / `G4.log` |
| G5：`:app:s0G5` | 0；1；22s | `reports/G5/TEST-*.xml` / `G5.log` |
| G8：`:app:s0G8` | 0；78；50s | `reports/G8/TEST-*.xml` / `G8.log` |

| T021 要求 / 依赖 | 原文来源与实际证据 | 结论 / 边界 / 责任 |
|---|---|---|
| T012/T013，D02/D05 | S0 spec §7批准表：负责人2026-11-03批准直接从README生成Kotlin、沿用Noto Sans SC/OFL；本文S0-05 T012/T013与 `design/design-system/README.md` 为映射/值源。G1实跑分解TokenParity6+Generator9+Contrast17+Typography7=39 | 自动PASS；两项对比度豁免按既有记录锁比值、不skip；本轮无字体/token决定 |
| T014/T031，AD-01～03及D07/D09 | canonical tasks T014/T031完成注释；`design/design-system/components.md` §5、§8.1～8.4；负责人2026-11-10批准并导出 `design/android-differences/screens/AD-01-icon-mapping.png`、`AD-02-date-time-picker.png`、`AD-03-action-sheet.png`，T031记录main ab44d0d（ae28a96）、35项对照18已接/17后续、Cursor PASS | 已有画板批准和文档同步记录；D09系统壳仍按ADR A/B，不能改称C。画板批准不等于本轮界面L3 |
| D12适用裁决/资产来源 | S0 spec §7 D12负责人2026-11-03决定按需SVG→vector drawable并附Apache2.0；`design-assets/material-symbols-manifest.txt`、`design-assets/material-symbols-provenance.json` 逐项源/输出digest，upstream commit `10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7`；components §8.3登记19项及随包LICENSE/NOTICE | 沿用已登记资产和许可；不新增资产、不推定后续未接入图标已批准；`‹ › ✓`仍随包字形 |
| T015/T016 roster/不变量 | components §8的逐ID代码/iOS源/状态/test method/L3列；本文S0-08 roster及map。`E/reports/G2/`：ComponentContract36、CatalogState66、Catalog6、PlatformShell5=113 | 113为当前实跑；旧96为历史预期，旧延期清单不覆盖components现行§8.2（仅CALENDAR-DAY→S2、BODY-DIAGRAM→S4）。S1新增组件合同有独立来源，不把旧22-ID数字当现行全部实现 |
| T017/T018入口/组合工具 | 本文「S0 G4」「S0 G3」、`docs/s0/T017.md`、`docs/s0/T018.md`；当前G4 XML12例、G3 XML42例。具体map见下文 | 自动PASS；G4工具不替代每一Feature入口map，alpha(0f)/不拦触摸遮罩的既有检测限制不抹去 |
| T019/T020，组件基线批准/digest | D/S1-D102：负责人2026-11-14亲录并查看DS-BUTTON-default（780×320），批准「看起来没问题」；正向1/0、临时「计数→次数」负例1failure，基线不变；T020完成注释main702f8f6。当前G5 XML记录pixelDifferences=0 | G5自动PASS；S1-D109决定保持现状、不扩展，不新增baseline。不是全组件或Feature视觉验收 |
| Claude复跑 / Cursor复核 | T028 host角色迁移与复跑见CP1、D101/D108；`H/.handoff/subagent/2026-11-16-t029-review.md`：范围99c0cc5..48a98e4，结论通过、无blocker；major由D110补归档，minor由D111处置 | 满足既有host/独立复核来源；本轮README独立review仍PENDING，不冒称已经通过 |
| L3状态与checkpoint边界 | components §1.4及本文S0-08「L3 与图标接入」；T021原文要求标明已取/未取 | **未取/PENDING**；系统手势、字体/大字、弹层等人工项未完成。是否将证据任务T021视为可勾，留dispatcher/负责人最终核验；本轮不勾、不称CP2已人工完成 |

DS-BUTTON完整SHA-256为 `0cdcc5e879daa5b2d6e0e712f9939263657059a242645fa92c536b9aa1c5ef82`，同时出现在D102、`E/baseline-before.txt`、`E/baseline-final.txt`。两份快照还包括environment PNG/README及当时产品README；它们描述T028前后不变，本轮README文档改动不冒充该快照的新批准。基线批准责任人为负责人；本轮未写任何baseline。

**CP2 entry/layout。** 本轮无新交互；历史组件交互的完整逐行map在本文S0-08「entry / layout map」及「宿主编译失败修复与 D12 资源接入」新增3行，不用本轮无新交互声明取代。代码入口为 `app/src/debug/java/com/ignacioli/finecoach/S0ComponentCatalog.kt` 的 `S0ComponentCatalog` / `S0ComponentState`：catalog内容列→`catalog-{ID}`可见分组→组件状态；后者构造`{ID}-{state}`及各子tag、内存callback。width owner实际位于 `app/src/main/java/com/ignacioli/finecoach/designsystem/{FcControls,FcRows,FcFeedback}.kt`：

| map中的实际交互示例（其余逐行沿用原map） | 数据变化 | 代码 / width owner |
|---|---|---|
| catalog索引→DS-BUTTON→`catalog-DS-BUTTON` | 内存样例导航 | Catalog→FcRows.FcGroupEntryRow.fillMaxWidth |
| DS-BUTTON/default→主按钮样例→`DS-BUTTON-default` | 内存count，无持久化 | Catalog→FcControls.FcButton.fillMaxWidth；父`$tag-parent`列 |
| DS-STEPPER/field→输入→`DS-STEPPER-field-input` | 内存text | Catalog→FcControls.FcStepperField；input.weight(1f)，胶囊满宽 |
| DS-CONFIRM-DIALOG/open→确认/取消→`DS-CONFIRM-DIALOG-open-accept` / `-cancel` | 确认仅内存count，取消关闭 | Catalog→FcFeedback.FcConfirmationDialog；横排weight/大字纵排满宽 |
| DS-TITLE-ACTION/icon→日历/资料库/筛选→`DS-TITLE-ACTION-icon-calendar` / `-library` / `-filter` | 内存count | Catalog→FcControls.FcTitleIconButton；≥44点击区，不要求满宽 |

结果限定为上述自动门与归档证据。OWNER? 集中L3及最终人工认可仍由负责人决定；无本轮新A/B设计，也无Penpot/baseline改动。

## T030 / CP3：向量与交付 checkpoint evidence（2026-11-16）

**CP3尚不可申请S0验收；L3 未取 / PENDING，S0-SC-003未满足。** 依据canonical S0 `tasks.md` T030（依赖T022～T029）、Phase3 Done when / Proven by、`plan.md` §5/§6及`spec.md` S0-SC-001～003。H/E/D及完整HEAD采用CP1定位约定；以下host归档均绑定产品基点 `48a98e4da048c55d0b3f602ae419b0ca76d41a82`。责任人：T028执行/核验为dispatcher，T029独立复核为Cursor，本轮仅Codex整理，集中L3与最终认可为负责人。

**最终host gate。** T028原始入口由D108记录为 `gate.sh --android`，完整授权输入在 `E/runlist.tsv`、`E/manifest.sha256`；各门的确切展开命令在 `E/summary.txt`。该包未独立保存带全部参数的顶层shell命令/exit行，不补造。G0/G1～G5/G8、Room、smoke的逐门command/rc/count/report见CP1/CP2。其余门如下；Gradle共同前缀及cwd同CP1，JUnit均0 failures/errors/skips：

| 门 / command 任务 | rc / 数量 / 耗时 | report / log（相对 E） |
|---|---|---|
| unit：`:app:testDebugUnitTest` | 0；1014；99s | `reports/unit/TEST-*.xml` / `unit.log` |
| G6 Android：`:app:s0G6` | 0；77；18s | `reports/G6-Android/TEST-*.xml` / `G6-Android.log` |
| seed：`:app:s0SeedIsolation` | 0；16；30s | `reports/seed/TEST-*.xml` / `seed.log` |
| training：`:app:s0Conformance` | 0；1；28s | `reports/training/TEST-*.xml` / `training.log` |
| library：`:app:p4ExerciseLibraryConformance` | 0；1；27s | `reports/library/TEST-*.xml` / `library.log` |
| today：`:app:p4TodayConformance` | 0；1；25s | `reports/today/TEST-*.xml` / `today.log` |
| detail：`:app:p4SessionDetailConformance` | 0；1；24s | `reports/detail/TEST-*.xml` / `detail.log` |
| students：`:app:p4StudentListConformance` | 0；1；27s | `reports/students/TEST-*.xml` / `students.log` |
| student：`:app:p4StudentDetailConformance` | 0；1；25s | `reports/student/TEST-*.xml` / `student.log` |
| P7：`:app:p7SideBySide` | 0；15；29s | `reports/P7/TEST-*.xml` / `P7.log` |
| add-exercise：`:app:p4AddExerciseConformance` | 0；1；27s | `reports/add-exercise/TEST-*.xml` / `add-exercise.log` |

S1-D111纠正口径：旧summary的`Android-subtotal ran=19 excludes=G8`未计G8，实际 **19+G8=20门**（含七个core、P7、unit等；不是20个互不重叠测试集合，测试数不能相加当独立覆盖）。`overall status=BLOCKED rc=2`为设计结果：G7 DEFERRED S4、L3 PENDING、安装/系统另检，且summary未接入后来G6对账；不称自动门失败，**不称FR-130「一条命令退出0」已由脚本满足**。D111接受现状及小计修正，不等于S0验收。

| T030要求 / 依赖 | 原文与可定位证据 | 结论 / 剩余 |
|---|---|---|
| T022～T024：最小真实运算/双端同集 | 本文S0-06「清单与证明边界」「双端op映射」「FR-018 / FR-012 登记」：72 conformance +5 course-packages正常样例，D06/D11批准最小credit-ledger.balance及日历timeZone；`E/G6-reconciliation.txt`、`G6-iOS.log`、`G6-Android.log`、`G6-iOS-vectors.txt`、`G6-Android-vectors.txt` | G6 **PASS，77=77**，id/path/sha256一致；iOS2个XCTest不等于2条向量，Android为72+5。S1首批13向量另属S1；历史FR-018已有iOS非纯Domain断言、未接余额runner；FR-012确认门槛共享adapter映射当时未确认，留S1核实，本节不由77项自动宣称该历史缺口已关闭 |
| G6 iOS确切历史command/环境 | `G6-iOS.log`开头：`xcodebuild -project ios/FineCoach.xcodeproj -scheme FineCoachTests -destination id=4DD81BE1-C2EA-4B71-90B0-2A7247934A60 -derivedDataPath /tmp/fc-t028-ios -resultBundlePath /tmp/fc-t028-ios.xcresult -only-testing:FineCoachTests/VectorFormatTests -only-testing:FineCoachTests/SharedVectorTests test`；对账记iPhone17/iOS27.0、已重启、09:13:59～09:15:05、rc0 | 2 tests/0 failures/TEST SUCCEEDED；以对账及双端原日志为最终G6，旧summary的BLOCKED不覆盖后续对账；未新跑 |
| T025：seed与Release隔离 | `E/seed.log`及2份XML：S1DebugSeedTests12+S1SeedIsolationTests4=16；Release APK SHA-256 `46fcd1d1086d18e55a49b8692ca640e6b7d17925d810802eff9cb54cac6927bb`，dex2/manifest1/resources1 | 同HEAD host隔离PASS，**不是设备安装PASS**；当前S1 seed由既有S0 task承载，不能外推S0历史metadata合同仍适用 |
| T026：S0历史安装/幂等 | `H/.handoff/logs/2026-11-06-host-s0-12-t026.log`：`RUN1 exit=0`/`RUN2 exit=0`，均`SEED version=1 rows=5 status=ok`；serial emulator-5554/API36/build BE2A.250530.026.D1，APK SHA-256 `68f66edc9fecf7bee22bbaed938437d594dbb93ee4531d2ceae0934047722bf6` | 历史2次安装PASS；原日志未给产品HEAD/完整命令，缺字段；对应已停用S0 metadata安装合同，不当成当前安装验收 |
| S1历史安装及当前安装缺口 | 本文「S1 T019」「S1 T020」与 `docs/s1/T019.md`、`docs/s1/T020.md`；`H/.handoff/logs/2026-11-09-s1-seed-api36-install1.log` / `install2.log` 均BUILD SUCCESSFUL、version1/rows66，同API36/BE4B.251210.005，APK SHA-256 `24465907c3e44193384d5fa15e047cbae5be9f4836ddca506dd7a062ecf7b01a`；T020记录两次rc0、tree同05a5cad | 当前合同是version3/multi rows1149（single1138/empty1088），命令见本文S1 T019；不是上述66或S0的5。**T028同HEAD当前seed的设备安装未取得**，summary的s0InstallSeededDebug为BLOCKED/separate-host-check；OWNER? 后续指定设备安装与认可 |
| 系统隐私/QPR2/API31/32/33+、KDF | CP1逐项来源：D100及t006 parser；2026-11-05 T010三份原始log/执行结果；2026-11-04 T032平台/provider及字节 | 沿用历史日期/环境，不称同HEAD设备重测；cross-platform仍BLOCKED→D10；cloud拒绝不算parser；T010人工DEFERRED如CP1保留 |
| T027/T028：host gate/基线变化/状态 | D104/D106的fixture66/0×2、bash-n/zsh-n rc0，D107接入G8，D108授权runlist；`E/status-before.txt`、`status-final.txt`为空；`baseline-before.txt`/`baseline-final.txt`相同，G0另存3个APK digest | T028当时产品干净；不是本轮README仍无diff。DS-BUTTON按D102/D109只引用digest、不加baseline；FR-130边界如上 |
| T029：独立一致性/入口布局/隐私复核 | `H/.handoff/subagent/2026-11-16-t029-review.md`（Cursor只读、未跑构建/设备），D110补六屏，D111逐条处置 | 复核通过、无blocker；T029勾选只代表复核处置，不代表L3发生；本轮README独立review PENDING |
| 集中L3、运行清单、SC-003 | `E/summary.txt`的L3 PENDING、D111、canonical spec S0-SC-003原文要求隐私系统证据和最终集中L3/运行清单负责人认可 | **L3从未发生，未取/PENDING**；D108批准T028 runlist不是最终S0集中走查/运行清单验收。OWNER? 集中走查、系统证据认可、最终S0验收；现阶段不能申请 |

**七个core hash的证据分层（S1-D110）。** 批准对照索引为 `H/.handoff/dispatcher/HANDOFF.md` 的七hash表；下列完整值均来自归档原文。训练页来自T028主跑XML；其余六屏来自同HEAD补跑 `E/core-hash-supplement/` 中各具名report.json的`sha256`（均`gatePassed=true`）及对应report.md。不能合称七屏都在T028主跑报告中留存。

| core / 归档来源（相对 E） | SHA-256 |
|---|---|
| P0-a2训练中 / `reports/training/TEST-com.ignacioli.finecoach.TrainingConformanceTests.xml`，S0_CONFORMANCE hashes | `d1caec3f70c8ef69b7d8f7f38b7bccdee1e8f0dad50549bd466566936be0978a` |
| 今日 / `core-hash-supplement/01-today-s1.report.json` | `06e5ce4d145aafff78dcac174f8fd49a57d9e459bd5bff14c026f153d0c0da1a` |
| 动作库 / `core-hash-supplement/D2b-exercise-library.report.json` | `9ded179ce418e332ae866ac07d41a61df8959a3f6899399e47839c089c915e5b` |
| 学员列表 / `core-hash-supplement/21-student-list-s1.report.json` | `9df8e951ea9883e9efe486022de4261c2467ede5c0e0b3bfc670a3c18359772c` |
| 学员详情 / `core-hash-supplement/26-student-detail-s1.report.json` | `2e48c2607cc36aa4c6fe17eb4fc2a07573ff0aa8b425ad57a01046120a1d3bd2` |
| 历史详情 / `core-hash-supplement/35-session-detail-s1.report.json` | `6ff3c85d892252e47ff3da3f594289bc4d0d63436ba03b2af61a5c4a980d1d65` |
| 添加动作 / `core-hash-supplement/C2b-B-add-exercise.report.json` | `143ba9c0445844326ca0b91c8dfe3989fd9dde365f6f56720b7d55f5a6fba786` |

补跑责任人为dispatcher；`E/core-hash-supplement.log` 保留C2b-B首次`AddExerciseConformanceTests:89`/ComposeTimeoutException失败，后在空闲主机单独重跑一次通过，见 `core-hash-supplement-c2bb-rerun.log`，按D110记为已知flake，不删除失败历史、不另起本轮重测。其余五屏一次通过；基线未改。自动几何/稳定hash证明不等于L3。

**CP3 entry/layout与本轮diff。** 本文S0-06 runner原执行记录明确「没有新增用户交互，entry/layout map不适用」；S0-12/S1 seed为debug infrastructure及adb instrumentation入口，不新增用户控件。已有catalog/弹层交互沿用本文S0-08完整map和D12三行及CP1 probe map。S1已实现的Feature入口另见 `docs/s1/implementation-map.md`（其中控件、identifier、mutation及width owner指向真实代码），作为S1范围引用，不混称S0新增交互。本轮仅文档，无新交互，无design delta；不修改Penpot/产品/测试/规格或baseline。

本轮初始tracked/staged/untracked均空，branch=`docs/s0-checkpoint-evidence`，HEAD同上；修改摘要仅README末尾三个checkpoint section及一处`s0G8`旧说明指向现行聚合门。文档验证限定readback和`git diff --check`，具体rc及最终status由writer最终报告提供；没有新host/device执行。本节不将文档完成当作T030/CP3验收，不tick tasks、不stage/commit。

剩余：T006/D10 **BLOCKED**；T010人工判定 **DEFERRED/PENDING**（历史自动文字记录已定位）；当前同HEAD seed安装 **未取得/BLOCKED separate host check**；本轮独立README review **PENDING**；集中L3/最终运行清单认可/S0-SC-003 **PENDING，OWNER?**；G7 **DEFERRED S4**。没有明确批准的事项不代owner决定。

### CP3 补充（2026-11-16）

L3 集中走查已于 2026-11-16 进行，逐项结果见 [walkthrough §0.4](docs/s1/walkthrough.md#04-走查结果2026-11-16)：API 31 的 A1/A2/A4 通过，负责人选择在 Pixel 8a（Android 16 / API 36）走查的 B1～B8 全部通过；A3 已由负责人复核通过（S1-D115）。此前本节的 L3 未取及当前 seed 安装缺口为历史状态，以本补充及 S1-D113～S1-D115 为当前记录；T030 已完成（S1-D115）。

当前 seed 的设备安装证据已取得（均为 `SEED version=3 rows=1149 status=ok`）：API 36 模拟器连跑两次 rc 0，日志 `.handoff/logs/2026-11-16-walkthrough-api36-install{1,2}.log`；API 31 模拟器首次因非 seed 库拒绝，负责人同意清空该虚构模拟器 App 数据后两次 rc 0，日志 `.handoff/logs/2026-11-16-walkthrough-api31-install{1,2,3}.log`；Pixel 8a 全新数据目录连跑两次 rc 0，日志 `.handoff/logs/2026-11-16-walkthrough-pixel8a-install{1,2}.log`，W1 修复后用修复版脚本再安装一次 rc 0，日志 `.handoff/logs/2026-11-16-w1-pixel8a-install.log`。仅引用本地日志路径，不复制含设备 serial 的内容；详情见 [walkthrough](docs/s1/walkthrough.md) §0.1（S1-D113/D114）。

S0L3-W1 修复与门禁见 S1-D114：修复已合入 local main `47f56c3`；API 31 与 Pixel 8a 机器验证重复桌面启动后均只有 1 个 MainActivity 实例；主机门禁 unit 1023/0、7 核心屏 hash 不变、P7 15/0，日志 `.handoff/logs/2026-11-16-w1-gate{A,B}.log`。机器验证不替代负责人 A3 复核，本次仅整理既有证据，未重跑构建或设备验证。

负责人 2026-11-16 认可 S0 运行清单与验收（S0-SC-003），S0 关闭，T011/T006 跨平台段带 D10 BLOCKED，G7 DEFERRED 到 S4，S0-FR-130 按 S1-D111 原样接受。

## S2：预约和提醒

需求与验收见 specs `FineCoach/007-android-port/s2-appointments/spec.md`（S2-D01）；执行记录见 [`docs/s2/`](docs/s2/README.md)。

### T015 / Phase 2 checkpoint：领域、存储与基线门禁

**续跑 1 / 2 指定范围 PASS；Phase 2 checkpoint PENDING（2026-11-17）**。seed v3 与余下 4 张核心屏的阻塞已解除，完整记录、文件清单和日志见 [T015](docs/s2/T015.md)；iOS 行号对齐表见 [T010](docs/s2/T010.md)、[T013](docs/s2/T013.md)。无新 UI，不新增 entry/layout map 行。

最终 schema 下：S1DebugSeedTests 12/0/0/0、DebugSeedTests 10/0/0/0、s0Room 21/0/0/0、s0G6 87/0/0/0（tests/failures/errors/skips），全部 exit 0。seed 只改一行，显式接受 schema 2 或 3；保留 ownership/generation/完整性和原测试断言。详见 [T012](docs/s2/T012.md)。

7 张 S1 锁定 PNG 已齐，实际完整 SHA-256 全部匹配既有批准值；补齐后 7 个 conformance task（含 Gradle manifest finalizer）各 1/0/0/0、exit 0。canonical 全 7 图正例 exit 0、临时副本改单 hash 负例 exit 1；生产 gate.sh 的 baseline-manifest 门无 stub 返回 PASS。未改 manifest hash 或新增视觉批准。哈希表与原始日志见 [T014](docs/s2/T014.md)。

S2-D06 / FR-007a 已落地：第二安排遇到已关联其他安排的 active Session，返回携带 A/session id 的 PreviousTrainingNeedsHandling，全部行不变；正常完成/放弃旧训练后 B 可新建，未关联安排的临时训练仍复用并关联。续跑 2 定向 AppointmentUseCaseTests10 + S2VectorRunnerTests10 + ActiveSessionRepositoryTests28 + SessionSettlementTests23 = 71/0/0/0，日志和差异见 [T013](docs/s2/T013.md)。Phase 5 可见入口待该 phase 实现。S2 iOS runner/双端对账、宿主全量门禁及独立复核仍 PENDING；不宣称整个 Phase 2 checkpoint 完成。未 commit、merge、push 或修改 specs。

续跑 4 修正 focus-only 编辑误脱离（移除 DAO 绕路）、补全迁移回滚及 fresh/migrated trigger 断言，定向 Domain10 + UseCase11 + Migration3 + S2Vector10 = 34/0/0/0。训练屏完整批准 digest 在 S1 README / T028 历史 XML 中找到，核对锁图一致后补为 64 位；宿主 .handoff 脚本不列入本分支文件清单。详见 T013/T014/T015。宿主已告知 gate A/B 全绿、G6 两端一致；删除学员/训练外键 blocker 在续跑 4 保留，续跑 5 已按 S2-D07 落地：删学员同事务清空安排/系列，保留课包/ledger 历史，实际删 Session 时 SET NULL；deleteFuture 引用保护保留。定向 59/0/0/0，证据与 Phase 3 撤销闹钟交接见 T012/T015；当前改动后的宿主复跑/复核仍 PENDING。

### T023 / Phase 3 checkpoint：提醒

**续跑 1 Agent 自测 PASS；续跑 2 指定 UI 回归 FAIL，整体 checkpoint PENDING（2026-11-18）**。T020/T021 的登记、调度、撤销、替换、重排与 T022 的权限/通用文案接线已实现；FR-010 拒绝后可见设置入口仍待 Phase 5（本 phase 白名单不允许新增设置 Feature）。宿主 plan §5 复跑、独立复核和 SC-004 设备部分尚未取得，不将 JVM 自测当作 milestone 验收。

续跑 1 `agent-test.sh`：AppointmentReminderTests 10、CapabilityManifestTests 9、AppointmentUseCaseTests 13、StudentRepositoryTests 12、RestNotificationTests 4、RestNotificationEntryLayoutTests 1、RestTimerTests 2、ScopeBoundaryTests 19，共 **70/0/0/0**；`s0G8` **78/0/0/0**；`s0G6` **87/0/0/0**（tests/failures/errors/skips）。日志、JUnit XML 路径、保留失败及文件清单见 [T023](docs/s2/T023.md)。所有命令经批准 wrapper，仅设独立可写 JVM home，无新依赖；`git diff --check` 通过。

续跑 2 已移除启动 recovery 前的提醒阻塞，并合并启动重复触发；登记改为 OS set 成功后写入。新增异常恢复和真实 TIME_SET receiver 测试，均通过。ExerciseTemplateEntryLayoutTests 同一节点等待连续两次 15 秒超时，按约定停止，未改 S1 断言/超时。当前逐类结果与日志见 [T023 续跑 2](docs/s2/T023.md)。下方 70/78/87 为续跑 1 历史证据。

登记表复用 Room `store_metadata`，无需 migration；S2-D07 删除学员撤销全部已删安排闹钟已有测试。精确访问可用时 setExactAndAllowWhileIdle，否则 setWindow；系统四类广播、启动/恢复与 Room invalidation 都复用 reconcile。独立通知渠道、仅 UUID extras、PUBLIC 通用锁屏文案；未改 S1 休息通知源码。iOS 对齐清单及五行执行记录见 [T020](docs/s2/T020.md)，系统重排见 [T021](docs/s2/T021.md)，权限与既有测试同步原因见 [T022](docs/s2/T022.md)。ScopeBoundaryTests 仅纳入 S2-D01 明确批准的 API/receiver，其他禁止项保留。无新 UI、无 entry/layout map 新行；未提交、切分支、push 或修改 specs。

### T034 / Phase 4 checkpoint：核心屏

**DONE（2026-11-19）。** 宿主 gate 1111/0，三屏 strict 33/0/0、64/0/0、66/0/0，人工例外 ≤1.6%，dsh 复核 PASS；合并 main `0fb16ce`。基线审批移到 Phase 6 走查。见 [T034](docs/s2/T034.md)。

### T045 / Phase 5 checkpoint：课程处理与非核心屏

**DONE（2026-11-19）。** 宿主 gate 1152/0（BUILD 0、BAD 0），dsh 复核两轮修复后 PASS，`p7SideBySide` 20/0；合并 main `b658a8f`。三条 P3 与设备证据、负责人看图带到 Phase 6。见 [T045](docs/s2/T045.md)。

### T054 / Phase 6 checkpoint：设备证据、复核与走查

（待填写）
