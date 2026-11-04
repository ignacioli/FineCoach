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
