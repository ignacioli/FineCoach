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
