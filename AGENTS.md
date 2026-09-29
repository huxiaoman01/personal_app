# AGENTS.md

本文件是这个仓库的「项目约定」，任何 agent 接手前先读完。
它记录了产品决策、技术选型、视觉规范和协作方式——**这些都已经和用户确认过，不要擅自改动**。

---

## 1. 项目是什么

**万能百宝箱**：一个单人自用的安卓学习工具 app，装在自己的手机上。

- 完全离线，不联网、无账号、无云同步
- 用户是考研学生，科目：运筹学、高数、线性代数、数据库、408
- 目的：能拍公式、随手记想法、刷记忆卡、看错题、打勾大纲

### 首版范围（v0）

首页是 **六个功能入口 + 顶部全局搜索**，目前**公式手册和灵感记录能用**，
另外四个点进去是「待开发」占位页：

| 入口 | 状态 |
| --- | --- |
| 公式手册 | ✅ v0 实现 |
| 灵感记录 | ✅ v0.2 实现（时间线 + 快速写 + 标签） |
| 记忆卡片 | 占位 |
| 错题本 | 占位 |
| 问题收集箱 | 占位 |
| 考点大纲 | 占位 |

数据模型已经为后面四个留好字段，**将来加功能不需要改表**——灵感记录
就是直接复用 `type = '灵感'` 实现的，一行表结构都没动。

---

## 2. 协作方式（最重要）

**用户不写代码，代码由 agent 写。但用户想学会整条链路。**

- 用户会 Python，能读简单代码；不懂 Dart，也不懂安卓构建
- 每做一步操作，都要说清楚：**为什么跑这条命令 / 会看到什么 / 怎么判断成功**
- 不要一次甩出一堆命令；按步骤来，每步给验证方法
- 写代码时用中文注释，注释解释「**为什么**」，不要复述代码在做什么
- 代码风格要面向初学者可读，宁可多写两行也别炫技
- 用户明确说过：「对前端的使用感觉要求比较高」——视觉细节不能糊弄

---

## 3. 技术选型（已定，不要换）

| 项 | 选择 | 说明 |
| --- | --- | --- |
| 框架 | Flutter + Dart | Windows 上能直接出 APK，一套代码 |
| 存储 | 本地 SQLite（`sqflite`） | 图片存 app 私有目录 |
| 状态管理 | 不用框架，`setState` + 全局单例 | 个人 app，引 Riverpod/Bloc 是过度设计 |
| 中文字体 | 系统默认 | 不引第三方字体（省 APK 体积） |
| 主题 | Material 3，跟随系统深浅色 | |

`applicationId com.baibaoxiang.app`、`android:label 万能百宝箱`、`minSdk 24`。

依赖：`sqflite`、`path`、`path_provider`、`image_picker`、`share_plus`、
`file_picker`、`archive`、`intl`。测试用 `sqflite_common_ffi`。
**不引状态管理框架。**

---

## 4. 数据模型（核心约束）

### 只建两张表

六个功能不是六套系统，而是 **1 张卡片 + 1 棵大纲** 的不同视图。
**绝对不要为每个功能建一张表、写一套页面。**

```sql
CREATE TABLE subjects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,               -- 公式 / 灵感 / 记忆 / 错题 / 问题
  subject_id INTEGER,               -- NULL = 未分类
  title TEXT,
  content TEXT,
  images TEXT,                      -- JSON 数组，只存文件名
  tags TEXT,                        -- JSON 数组；灵感记录在用，公式暂不用
  pinned INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  reviewed_at INTEGER,              -- 预留：记忆卡
  forgot_count INTEGER NOT NULL DEFAULT 0,  -- 预留：记忆卡
  deleted_at INTEGER                -- NULL = 正常，非 NULL = 在回收站
);
```

### 几条不能破的规矩

- **图片只在数据库里存文件名**，真实路径由 `ImageStore` 运行时解析。
  存绝对路径会在重装后失效。
- **科目是数据不是常量**：用户能在 app 里增删改，别写死在代码里。
- **删科目不删卡片**：只把 `subject_id` 置为 NULL，卡片变成「未分类」。
- **删除是软删除**：进回收站保留 30 天，app 启动时清理过期记录并删图片文件。
- **搜索用 `LIKE` 匹配标题、注释、科目名、标签**，不建全文索引（个人几千张卡够用）。
- **标签不建表**：它就是卡片的 `tags` 字段，候选标签从现有卡片里聚合出来，
  某个标签没人用了就自动消失。筛选也在 Dart 里做，别往 SQL 里塞
  `json_each`——minSdk 24 的系统 SQLite 没有 JSON1 扩展。
- **记忆卡不要做间隔重复算法**，只保留 `forgot_count`，按它排序即可。

---

## 5. 代码结构约定

```
lib/
  main.dart                     初始化：图片目录 → 数据库 → 清回收站 → 起界面
  app_globals.dart              全局单例（imageStore / cardRepository / subjectCache）
  theme/app_theme.dart          ★ 所有视觉参数的唯一出处
  models/                       StudyCard、Subject
  data/                         建库、读写、图片仓库、导出
  widgets/                      可复用组件
  features/<功能>/               每个功能一个目录
```

**数据流：页面（features）→ 数据层（data）→ SQLite。**

- 页面**绝不直接写 SQL**，一律通过 `CardRepository`
- 页面**绝不写死颜色/间距/字号**，一律从 `theme/app_theme.dart` 取
- 改数据层就必须同步加/改 `test/` 里的用例

---

## 6. 视觉与交互规范（数值是硬约束）

目标是**简洁、清新、久看不累**。实现时照着数值写，不要临场发挥。

### 颜色

| 用途 | 浅色 | 深色 |
| --- | --- | --- |
| 页面背景 | `#FDF8EF` 米黄 | `#0F1B2D` 深蓝 |
| 浮层/弹窗 | `#FFFFFF` | `#16253B` |
| 分隔线 | `#F0E8DA` | `#1E2E45` |
| 图标块底 | `#F5EDDD` | `#1B2C44` |
| 主色 | `#B5834A` 暖棕 | `#6E9BD1` |
| 正文 | `#3A3226` 深褐 | `#E6EDF6` |
| 次级文字 | `#8A7B68` | `#93A3B8` |
| 三级文字 | `#A89A85` | `#6B7C92` |

主色只用于选中态、FAB、关键按钮、置顶标记，**单屏覆盖面积 < 10%**。

### 尺寸

- 间距**只用** `4 / 8 / 12 / 16 / 24`（`AppSpace`），不出现别的值
- 圆角：卡片与图片 `12`，缩略图 `10`，图标块 `12`，标签 `999`
- 页面左右边距 `16`；列表行高 `64`；缩略图 `48×48`
- 分隔线左边缩进 `76`，右边到 `16`
- 功能入口图标块 `44×44`；FAB `56`

### 字体（系统默认）

| 位置 | 字号 / 字重 |
| --- | --- |
| 详情页标题 | 20 / w600 |
| 页面标题、列表标题 | 15–17 / w600 |
| 正文与注释 | 15 / w400，**行高 1.6** |
| 辅助文字 | 13 / w400 |
| 角标 | 12 / w400 |

中文行高一律 ≥ 1.5，禁止英文式的 1.2。

### 明令禁止

- ❌ **零阴影**：所有 `elevation` 为 0，靠留白和分隔线分层
- ❌ 纯黑 `#000`、纯白 `#FFF` 作为大面积底色（全屏看图页除外，用 `#0A1220`）
- ❌ Material 默认紫色；大面积主色填充
- ❌ 弹跳、缩放等装饰性动画

### 交互

- 可点区域 ≥ `44×44`；点击即刻响应，不做延迟跳转
- 长按列表项触发 `HapticFeedback.selectionClick`
- 列表增删用 150–200ms 淡入淡出；页面转场用系统默认
- 缩略图加载带 `cacheWidth`，避免滚动卡顿
- 编辑页有未保存改动时返回要弹确认

---

## 7. 明确不做

这些会把项目从两周拖成半年，用户已经明确排除：

桌面小组件、云同步、账号系统、多设备、社交分享、排行榜、
公式 OCR、手写公式识别、全文索引、自动备份、批量导入、
卡片拖拽排序、网页版/桌面版/iOS 版、复杂间隔重复算法。

搁置但记录在案的想法（本轮不做）：系统分享接收、复习热力图、随机抽卡、
D-day 倒计时、学习计时、资料保险箱、科目专用计算器、通用 OCR、白噪音。

---

## 8. 开发环境

| 组件 | 位置 |
| --- | --- |
| Flutter SDK | `C:\src\flutter`（已在用户 PATH 里） |
| Android SDK | `C:\Android\sdk`（`ANDROID_HOME` 已设置） |
| JDK | `C:\Program Files\Java\jdk-17.0.19` |
| 项目 | `D:\project\phone_app` |

已设置的加速镜像（用户级环境变量）：

```
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

已安装的 SDK 组件：

```
platform-tools        37.0.1
platforms             android-36
build-tools           36.0.0
ndk                   28.2.13676358   ← Flutter 工具链要求，必须存在
cmdline-tools         latest (16111833)
```

### 网络：这台机器最大的坑

实测带宽 40 KB/s ~ 1.5 MB/s，**且会中途断流**。官方源尤其慢：
`repo.maven.apache.org` 5 KB/s、`plugins.gradle.org` 3 KB/s、
`services.gradle.org` 会挂死。

**大文件下载必须**带 `-C -` 断点续传和 `--retry`，下完校验 zip 完整性
（用 `[System.IO.Compression.ZipFile]::OpenRead`），不要假设一次能下完。

### Gradle 仓库配置（改之前务必读）

`android/settings.gradle.kts` 的 `pluginManagement.repositories` 和
`android/build.gradle.kts` 的 `allprojects.repositories` 已改成**只用国内源**：

```kotlin
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }  // 插件门户镜像
maven { url = uri("https://maven.aliyun.com/repository/google") }         // Google Maven 镜像
maven { url = uri("https://maven.aliyun.com/repository/public") }         // Maven Central 镜像
maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }  // Flutter 引擎原生库
maven { url = uri("https://storage.googleapis.com/download.flutter.io") } // 同上，备用
```

**两条铁律**：

1. **不要加回 `google()` / `mavenCentral()` / `gradlePluginPortal()`**。
   它们极慢，一被回退过去就长时间卡住。
2. **不能加会报错（超时 / 502）的仓库，尤其不能放在能用的仓库前面**。
   Gradle 遇到仓库「报错」会**中止整个解析**，而不是继续试下一个
   （404 算「没有」，可以继续；超时算「错误」，直接失败）。
   华为云 `repo.huaweicloud.com` 就是这种：对绝大多数包可用，
   但对 `io.flutter:*` 会超时，从而把整个构建搞挂。**已经因此移除了。**

### 其他两个坑

- **`sdkmanager.bat` 是坏的**：这个 cmdline-tools 版本里它已废弃，
  运行时崩溃（退出码 `0xC0000409`）。装 SDK 组件要用
  `C:\Android\sdk\cmdline-tools\latest\bin\android.exe sdk install <包名>`。
- **不要中途强杀构建进程**：会损坏 Kotlin 增量编译缓存，之后报
  `Could not close incremental caches`。项目已设 `kotlin.incremental=false`
  规避；真踩到时删掉 `build/` 和 `android/.gradle` 重建。

### Gradle 发行包

`services.gradle.org` 会挂死，所以 `gradle-9.3.1-all.zip` 是手动下载后
放进 wrapper 缓存的：

```
C:\Users\asus\.gradle\wrapper\dists\gradle-9.3.1-all\9ot9r568e8zfvvd4mn8rbu1j0\
    gradle-9.3.1-all.zip      （224 MB，已校验）
    gradle-9.3.1/             （已解压）
    gradle-9.3.1-all.zip.ok   （完成标记）
```

注意缓存目录名 `9ot9r568e8zfvvd4mn8rbu1j0` 是从 `distributionUrl` 算出来的哈希，
**改 `distributionUrl` 会导致 Gradle 认不出缓存的包而重新下载**。

---

## 9. 常用命令

```powershell
flutter doctor                              # 体检
flutter pub get                             # 拉依赖（按 pubspec.yaml）
flutter analyze                             # 静态检查，必须零警告
flutter test                                # 跑单元测试
flutter build apk --release                 # 出包
```

产物：`build\app\outputs\flutter-apk\app-release.apk`，手动传到手机安装。

---

## 10. 交付标准

改完代码，以下四条必须全过，才算完成：

1. `flutter analyze` **零警告**
2. `flutter test` 全部通过
3. `flutter build apk --release` 成功出包
4. 对照第 6 节的数值逐条自查视觉（阴影、间距、行高、主色占比、深浅两套色）

真机需要人工验收的部分（agent 做不了）：拍照、相册多选、双指放大、
导出两种交付方式、深色模式下实际观感。
