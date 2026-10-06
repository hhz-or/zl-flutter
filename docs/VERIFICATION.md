# 独立验证报告 — Flutter 复刻 `指令/`（web-instruction）

**结论：不通过（需修复后再验收）。** 语料保真、生成语义、乱码动画的布局稳定性、字体子集化、Web 构建产物这五块经独立复算全部成立；但发现 **2 个高severity 缺陷**（关于页缺少 Material 祖先、持久化 blob 单条损坏即静默摧毁历史+收藏）、4 个中severity 缺陷（`onCompleted` 可触发两次、历史/收藏页分享无回退、`AppSettings` 非法数值导致设置整体回退、`historyLimit` 载入时不生效）。实现方声称的 4 项门禁（analyze 0 / test 159 / 字体 830,976 B / web 构建成功）我全部独立复现通过，但这 4 项门禁**并不能覆盖**上述缺陷。

验证环境：Flutter 3.47.5 / Dart 3.13.4 / fontTools 4.63.0 / Node 24.20.0。所有一次性探针脚本都放在 `%TEMP%\vfz\`，**未改动仓库内任何文件**（本报告除外）。仓库位于一个无提交的 git 工作区（`git log` 报 "does not have any commits yet"），因此没有任何历史可用于交叉验证。

## 检查清单

| # | 检查项 | 方法 | 命令 | 观测结果 | 判定 |
|---|---|---|---|---|---|
| 1 | 四组语料计数 | 自写 Node 脚本用 `vm` 直接执行 `script.js` 的数组字面量 | `node %TEMP%\vfz\corpus_check.js` | scenes 27 / actions 62 / supplements 18 / easterEggs 23，与 Dart 全部相等 | PASS |
| 2 | 语料逐元素一致 | 自写 Dart 字面量解码器（含 `\u{...}`、`\\`、`\'`）逐条比对 | 同上 | 262 条全等，**0 处不一致**；并集码点 533 == 533，两侧互不缺失 | PASS |
| 3 | 语料陷阱：空白/换行/代理对/全角 | 逐条扫 `\s`、`\n`、`codePointAt>0xFFFF`、标点清单 | 同上 + `ws.js` | 无首尾空白、无跨行条目、无非 BMP 字符；全角标点只有 `，`×12 `。`×17，另有 ASCII `!`×1 | PASS |
| 4 | `scrambleChars` 保真 | JS 求值与 Dart 常量逐字节比较 | `python %TEMP%\vfz\final_font_check.py` | 85 字符完全相同；`\` 正确保留；上游笔误（`S/s` 重复、`X/x` 缺失）原样保留 | PASS |
| 5 | 彩蛋率 = 0.15 | 200,000 次采样（pureRandom），算 95% 置信区间 | `flutter test %TEMP%\vfz\gen_probe_test.dart` | 30027/200000 = **0.150135**，CI95 = [0.14857, 0.15170]，含 0.15 | PASS |
| 6 | 拼接顺序 / 无分隔符 | 5000 次断言 `segments[0]+[1]+[2] == body` 且三段分别属于对应数组 | 同上（C1） | 全部通过 | PASS |
| 7 | pureRandom 允许重复 | 20,000 次抽样的 id 统计 | 同上 | unique=13052，重复 6948 次 → 与原版 `Math.random()` 一致 | PASS |
| 8 | ShuffleBag 轮内不重复 | n=1..12 × 400 轮穷举；n=2 连抽 1 万次；边界统计；空/单元素/refill | 同上 | 每轮都是精确排列；n=2 无相邻重复；边界重复 0/19999；chi2=0.0 | PASS |
| 9 | ShuffleBag 含重复元素时 | `items=[1,1,2]` 等 4 组 × 5 万次 | `flutter test %TEMP%\vfz\dup_probe_test.dart` | 边界重复 4143/16666 → 类文档的"能避免时一定避免"被打破 | FAIL（见发现 8） |
| 10 | 动画期间布局恒定 | 12 组对抗输入（CJK 换行居中 / 参差末行 / maxLines+省略号 / 代理对 emoji / U+20000 / 组合符 / 300 字符长词 / textScaler 1.5），采样 t0、40 个中途帧、结束尺寸，与同参数纯 `Text` 对比 | `flutter test %TEMP%\vfz\scramble_probe_test.dart` | 12 组**全部 STABLE**（中途尺寸 distinct=1，t0 = 结束 = 纯 Text 尺寸） | PASS |
| 11 | `currentFrame`/`lockedCount`/`isComplete` 同步 | 逐帧断言长度、锁定前缀、完成态 | 同上 | `lenOk`/`prefixOk`/`finalOk` 全 true | PASS |
| 12 | `onCompleted` 每次 run 只触发一次 | 同帧内 `completeNow(); restart();` | 同上（S3） | **触发 2 次**（1 次在旧 run 遗留回调、1 次在新 run 结束） | FAIL（见发现 3） |
| 13 | 连续抽到同一句仍重播 | 单元素语料强制同文本，观察 tick 与帧 | `flutter test %TEMP%\vfz\repro_test.dart`（R3） | tick 1→2，`complete=false`、`locked=0/32` → 正常重播 | PASS |
| 14 | `reduceMotion` 路径 | `MediaQuery(disableAnimations: true)` + 设置开关 | 同上（S4） | 立即完成、只回调 1 次、不排帧 | PASS |
| 15 | 持久化：截断 blob | 注入 `'[{"id":"i1","segments":["abc"'` | `flutter test %TEMP%\vfz\loss_probe_test.dart` | 不抛出，但 history 与 favorites **同时变空**，`lastError=FormatException` 且界面从不展示 | FAIL（见发现 2） |
| 16 | 持久化：越界 `createdAt` | 注入 `createdAt: 9223372036854775807` | 同上 | `RangeError`，两键同时清空；随后 generate 一次把磁盘上 3 条覆盖成 1 条 | FAIL（见发现 2） |
| 17 | 持久化：非字符串 segments / 未知枚举 / 负数与负时间戳 / 重复 id | 注入垃圾 JSON | `flutter test %TEMP%\vfz\persist_probe_test.dart` | 过滤、回退、首见优先，均不抛 | PASS |
| 18 | 持久化：5–6.5 MiB blob | 60,000 条、6.50 MiB | 同上（P5） | 787 ms 载入 60000 条、不抛；**`historyLimit=100` 完全不生效** | FAIL（见发现 6） |
| 19 | `historyLimit` 0 / 10 / 500 | 逐值注入 600 条 | 同上（P8） | limit=0 不裁剪（601 条）；10/500 仅在 generate 后生效 | FAIL（见发现 6、7） |
| 20 | 去重保留较新时间戳 | 单元素语料 + 递增时钟连抽 3 次 | `flutter test %TEMP%\vfz\small_probe_test.dart`（C3） | history=1，`createdAt` = 最新（4000），sessionCount=3 | PASS |
| 21 | `AppSettings` 容错 | 合法 JSON `{"historyLimit": 1e400}`（`jsonDecode` → `Infinity`） | `flutter test %TEMP%\vfz\nan_reach_test.dart` | `UnsupportedError: Infinity or NaN toInt`；`load()` 整体回退默认值 | FAIL（见发现 5） |
| 22 | `flutter analyze` | 独立执行 | `flutter analyze` | `No issues found! (ran in 17.4s)`，exit 0 | PASS |
| 23 | `flutter test` | 独立执行 | `flutter test` | `00:28 +159: All tests passed!`，exit 0 | PASS |
| 24 | `subset_fonts.py --verify` | 独立执行 | `python tools/subset_fonts.py --verify` | exit 0；`OK — all 783 collected code points are covered by the output fonts.` | PASS |
| 25 | 字体覆盖率（独立取字） | 自写 fontTools 脚本；字符集由 `script.js`+2 个 ARB+31 个 `.dart` 的**全部**字面量（**不剥注释**）+`kScrambleGlyphs` 推导 | `python %TEMP%\vfz\final_font_check.py` | 774 个码点；**唯一未覆盖的是 U+000A（换行，非字形）**；99 个由 Inter 命中、674 个由 LXGW 兜底 | PASS |
| 26 | Inter 静态实例与字重 | fontTools 读 `fvar` / `OS/2.usWeightClass` | 同上 | 5 个文件**均无 `fvar`**；usWeightClass = 400/500/600/700/400；4 个 Inter 的 cmap 完全相同（692 项） | PASS |
| 27 | 体积账目 | 文件大小核对 | `Get-ChildItem assets\fonts,指令` | 874,708×4 + 25,486,932 = **28,985,764** ✓；五个输出合计 **830,976** ✓（构建产物 `build/web/assets/assets/fonts` 亦为 830,976） | PASS |
| 28 | 构建产物启动路径唯一 | 检查 `build/web/index.html` 与 `build/web/flutter_bootstrap.js` | `node --check` / `Select-String` | 只有 1 处 `_flutter.loader.load(` 调用点；`index.html` 只有 1 个 `<script src="flutter_bootstrap.js">`；**无残留 `{{...}}` 模板**；`node --check` exit 0 | PASS |
| 29 | manifest / 图标 / sourcemap / 第三方脚本 | `ConvertFrom-Json` + 递归查找 | — | `manifest.json` 可解析、4 个图标文件均存在；`*.map` 0 个；无 analytics/giscus 代码（仅注释说明已移除） | PASS |
| 30 | 独立重建 Web | 构建到临时目录（不动 `build/web`） | `flutter build web --release --base-href / --no-web-resources-cdn -o %TEMP%\vfz\webbuild` | exit 0，97.7 s，`√ Built ...webbuild` | PASS |
| 31 | 320/2560 × textScaler 1.0/1.5/2.0 全页无溢出 | 挂真实 `AppShell`，最长语料、开三段面板+自动复制，遍历 4 个标签页并滚到底，用 `FlutterError.onError` 收全量错误 | `flutter test %TEMP%\vfz\ui_probe3_test.dart`、`final_probe_test.dart` | 中文 30 组、英文 5 组**均未捕获任何 overflow 或异常** | PASS |
| 32 | 关于页 Material 祖先 | 按 `lib/app.dart` 的方式挂 `AppShell`，点 ⓘ 进入关于页 | `flutter test %TEMP%\vfz\repro_test.dart`（R1） | **4 个 InkWell 在 build 期抛 "No Material widget found"** | FAIL（见发现 1） |
| 33 | 分享 → 剪贴板回退 | `FakeShareService(available: false)` | `flutter test %TEMP%\vfz\final_probe_test.dart`（F1/F1b） | 生成页：clipboard=1、有 SnackBar；**历史页：shared=0、clipboard=0、无 SnackBar（静默无反应）** | FAIL（见发现 4） |
| 34 | `autoCopy` 内容 | 生成一次后比对剪贴板 | `repro_test.dart`（R5） | `"致：在路口转14个弯，并直走12m"` == `"致："+body` | PASS |
| 35 | 上游 `script.js` 与本仓库 `指令/` 副本是否一致 | 抓取 GitHub raw | `web_fetch` | 网络不可达（`fetch failed`），未能取得上游文件 | INCONCLUSIVE |
| 36 | 真机/浏览器运行（CanvasKit 首帧、localStorage 配额、真机 `navigator.share`） | 无浏览器与设备 | — | 未执行 | INCONCLUSIVE |
| 37 | README 声称的行覆盖率 89%（27 文件 / 2693 行） | 未运行 `--coverage` | — | 未验证 | INCONCLUSIVE |

## 发现（按严重度排序）

### 1. [高] 关于页被作为路由推入，却没有 `Material` 祖先 → 链接行在 debug 下渲染成红色错误块，release 下每次点按抛空断言

* **位置**：`lib/features/shell/app_shell.dart:220`（`Navigator.push(MaterialPageRoute(builder: (_) => const AboutPage()))`）+ `lib/features/about/about_page.dart:49`（返回 `Align`，整页没有 `Scaffold`/`Material`）+ `lib/features/about/about_page.dart:342`（`InkWell`）。
* **机理**：历史/收藏/设置三页是 `AppShell` 的 `Scaffold` body 里的标签页，所以有 `Material`；关于页是**被 push 的独立路由**，`MaterialPageRoute` 不提供 `Material`。`_AboutLinkRow` 里的 `InkWell` 因此找不到祖先。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\repro_test.dart        # 只跑 R1
  ```
  观测输出：
  ```
  R1 open About -> exception=Multiple exceptions (4) were detected ...
  R1 AboutPage present=true InkWell count=4
  ```
  4 个异常均为：
  ```
  The following assertion was thrown building _InkResponseStateWidget(...):
  No Material widget found.
  ... The specific widget that could not find a Material ancestor was: _InkResponseStateWidget
  ...   InkWell
        _AboutLinkRow-[<'about-link-font-inter'>]
  The relevant error-causing widget was: InkWell  .../about_page.dart:342:12
  ```
* **影响**：debug/profile 构建下打开"关于"页，4 个链接行（Inter / 霞鹜文楷 / 源码 / 原项目）位置直接变成红底错误块。release 下 assert 被剥离，但 `Material.of()` 的实现是 `return controller!`（Flutter 3.47 `material.dart:423`），所以 `InkResponse` 的 tap-down 路径（`ink_well.dart:1192-1207` → `_createSplash` → `Material.of(context)`）会抛 `Null check operator used on a null value`（由 `GestureRecognizer.invokeCallback` 捕获上报），水波纹永不绘制、控制台每次点按报一次错。**该项目自己的测试完全看不到这个问题**，因为 `test/support/test_app.dart:83` 把被测组件包进了 `Scaffold(body: child)`。

### 2. [高] 持久化 blob 中只要有一条记录解码失败，历史与收藏会**同时**被静默清空，并在下一次生成/收藏时永久覆盖磁盘数据

* **位置**：`lib/state/prescription_controller.dart:106-117`（`load()` 把两次读取放进同一个 `try`，任一失败则两个字段都不赋值）+ `:272-294`（`_readList` 逐条 `Instruction.fromJson`，无逐条容错）+ `lib/data/models/instruction.dart:127`（`DateTime.fromMillisecondsSinceEpoch(rawCreatedAt)`，无范围校验）+ `:138`（`generate()` 立即 `_persistHistory()`）+ `lib/state/prescription_controller.dart:86`（`lastError` 只被两个控制器持有，`grep` 全仓库无任何 UI 读取它）。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\loss_probe_test.dart
  ```
  观测输出（X1，history 键是截断 JSON、favorites 键完全合法）：
  ```
  X1 after load: history=0 favourites=0 lastError=FormatException
  X1 on-disk favourites after toggling a new one: "[{...\"新收藏\"...}]"
  X1 original favourite still on disk? false
  X1 on-disk history after generate: 89 chars, entries=1
  ```
  X2（history 中仅 1 条 `createdAt: 9223372036854775807`）：
  ```
  X2 after load: history=0 favourites=0 lastError=RangeError (millisecondsSinceEpoch): Invalid value:
     Not in inclusive range -8640000000000000..8640000000000000: 9223372036854775807
  X2 on-disk history entries after one generate: 1  (was 3)
  ```
* **影响**：单条越界时间戳（或一次被中断的写入）就能让用户**丢掉全部历史与全部收藏**，而且没有任何提示 —— `lastError` 从未被渲染（`grep lastError lib/` 只命中两个控制器自身）。写入路径还会立刻用"只剩一条"的内存状态覆盖磁盘上的完好数据，属于不可逆丢失。`Instruction.fromJson` 的文档承诺"字段缺失或类型不符时回退到安全值，绝不抛出"在 `createdAt` 上不成立。

### 3. [中] `onCompleted` 可以对同一次 run 触发两次（旧 run 遗留的 post-frame 回调没有被取消）

* **位置**：`lib/features/generator/widgets/scramble_text.dart:263-283`（`_scheduleCompleted` 只把 `_completedNotified` 置 true 并 `addPostFrameCallback`，**没有保存/取消回调句柄**）+ `:227`（`_begin()` 把 `_completedNotified` 重置为 false，于是旧回调重新"合法"）+ `:272-276`。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\scramble_probe_test.dart    # 只跑 S3
  ```
  观测输出：
  ```
  S3 completeNow()+restart() same frame -> calls after 1 pump=1, total=2 (expected 1)
  ```
* **影响**：违背该组件自己声明的契约"只会触发一次（`restart()` 之后可以再次触发）"。在应用里的表现是 `_InstructionStageState.onCompleted` 会被提前调用，把 `_revealed` 置为 true，于是动画刚开始就恢复 3 层高斯模糊（正是注释里说要避免的"最昂贵的一笔栅格化开销"）。可经由"`animate` 由 true 变 false 的同一帧内文本又变了"或任何调用公开 API `restart()`/`completeNow()` 的路径触发。

### 4. [中] 历史页/收藏页的分享按钮没有"平台不支持 → 复制"回退，点了完全没反应

* **位置**：`lib/features/history/history_page.dart:111-118` 与 `lib/features/favorites/favorites_page.dart:110-117`（`_share` 直接丢弃 `bool` 返回值）；对照 `lib/features/generator/generator_page.dart:62-66`（同一功能实现了回退）。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\final_probe_test.dart       # F1 / F1b
  ```
  观测输出：
  ```
  F1 history share icons=1
  F1 HISTORY tab (share unavailable): shared=0 clipboard=0 snackbar=0 => NOTHING HAPPENED
  F1b GENERATOR tab (share unavailable): shared=0 clipboard=1 snackbar=1
  ```
* **影响**：在不支持 `navigator.share` 的环境（桌面版 Chrome/Firefox、部分内嵌浏览器）里，生成页的分享会退化成复制并弹提示，而历史页/收藏页的分享按钮点了毫无反馈 —— 用户会认为应用坏了。同一份代码里存在两种行为，属于明确的实现遗漏（`lib/core/services/app_services.dart:21-27` 的注释明确要求调用方在返回 `false` 时退化）。

### 5. [中] `AppSettings.fromJson` 遇到 `Infinity`/`NaN` 会抛异常，导致**整份设置**被丢弃回默认值

* **位置**：`lib/data/models/app_settings.dart:150-156`（`intOr` 里 `raw.toInt()` 未做有限性检查）+ `:194`（`historyLimit: intOr(...)`）。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\nan_reach_test.dart
  ```
  观测输出：
  ```
  Y1 jsonDecode("{"historyLimit": 1e400, ...}") -> {historyLimit: Infinity, ...}
  Y1 AppSettings.fromJson -> THREW UnsupportedError: Unsupported operation: Infinity or NaN toInt
  Y2 historyLimit=1e400 -> THREW UnsupportedError: Unsupported operation: Infinity or NaN toInt
  Y2 animationSpeed=1e400 -> OK (no throw)
  ```
  注意 `1e400` 是**合法 JSON**，`jsonDecode` 会正常接受并解析成 `Infinity`（`NaN` 字面量才会被 `jsonDecode` 拒绝），所以这条路径可由磁盘上的一份损坏 blob 触发，而不只是程序内构造。
* **影响**：`SettingsController.load()`（`lib/state/settings_controller.dart:47-50`）捕获异常后把**所有**设置清成默认值，而该方法的文档承诺是"任何字段异常都回退到 defaults 中的值"（逐字段回退）。用户会一次性丢失语言、主题、色板、动画速度、历史上限等全部偏好。

### 6. [中] `historyLimit` 在载入时不生效，超限 blob 全量驻留内存

* **位置**：`lib/state/prescription_controller.dart:108`（`load()` 直接采用 `_readList` 的结果，从不调用 `_trimmed`）+ `:226-232`（只有 `historyLimit` **发生变化**时才裁剪）+ `:264-270`。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\small_probe_test.dart       # C4
  flutter test %TEMP%\vfz\persist_probe_test.dart     # P5 / P8
  ```
  观测输出：
  ```
  C4 historyLimit=10 but loaded history length=300
  P5 loaded 60000 entries in 787 ms; historyLimit=100 (NOT applied on load)
  P8 limit=10 loaded=600 afterApplySettings=600 afterGenerate=10
  ```
* **影响**：用户把上限从 500 调到 10 之后重启应用，界面里仍然是 600 条；一份 6.5 MiB 的 blob 会全量解码并常驻内存（787 ms），历史页首屏因此明显变慢。`historyLimit` 的设置语义（"最多保留 N 条"）在载入路径上不成立。

### 7. [低] `_trimmed()` 把 `limit <= 0` 当成"不限制"

* **位置**：`lib/state/prescription_controller.dart:266`（`if (limit <= 0 || history.length <= limit) return history;`）。
* **最小复现**：`flutter test %TEMP%\vfz\persist_probe_test.dart`（P8）→ `P8 limit=0 loaded=600 afterApplySettings=600 afterGenerate=601`，历史无上限增长。
* **影响**：`AppSettings` 的构造函数不做校验，`historyLimit: 0` 时会得到与"上限 0"完全相反的行为（无上限）。目前 UI 滑块最小值为 10、`fromJson` 也夹在 [10,500]，所以只能由程序内构造触发，故定为低。

### 8. [低] `ShuffleBag` 的"跨轮不重复"保证在元素列表含重复项时不成立

* **位置**：`lib/domain/instruction_generator.dart:79-89`（`_avoidBoundaryRepeat` 只把队尾与 `[0, len-2]` 中随机一个位置交换；若换来的仍是同一个值，重复依旧）。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\dup_probe_test.dart
  ```
  观测输出：
  ```
  Z1 items=[1, 1, 2]      boundaries=16666 boundaryRepeats=4143 GUARANTEE VIOLATED
  Z1 items=[7, 7]         boundaries=24999 boundaryRepeats=24999 GUARANTEE VIOLATED
  Z1 items=[1, 1, 2, 3, 4] boundaries=9999  boundaryRepeats=421  GUARANTEE VIOLATED
  ```
* **影响**：类注释承诺"相邻两轮的边界元素不同 —— 能避免时一定避免"。该承诺对含重复项的列表不成立。内置语料四组**都没有重复项**（已用 Node 逐组查重，零命中），所以当前用户不可见；仅当未来允许用户自定义语料库时会变成真问题。

### 9. [低] 启动时若已从历史恢复出指令，本次会话"第一次"生成的动画会退化为 3 层高斯模糊

* **位置**：`lib/features/generator/generator_page.dart:259`（`late int _tick = widget.controller.animationTick;` 是**惰性**初始化）+ `:263-269`（`didUpdateWidget` 里先读 `_tick` 才比较）。`didUpdateWidget` 触发时 `widget` 已是新 widget，惰性初始化读到的是**新** tick，于是 `!=` 判定为 false，`_revealed` 不被重置。
* **最小复现**：
  ```
  flutter test %TEMP%\vfz\repro_test.dart            # R4
  ```
  观测输出：
  ```
  R4 after restore+settle shadows=3 (expect 3 after reveal)
  R4 during first fresh animation shadows=3 (code intends 1)
  R4 after first fresh animation shadows=3
  R4 during second fresh animation shadows=1 (code intends 1)
  ```
* **影响**：纯性能问题（不影响正确性与观感一致性），每次"带历史冷启动"只发生一次。代码注释明确把逐帧 3 层模糊称作"本应用最昂贵的一笔栅格化开销"，所以这个一次性失效值得修。

### 10. [低] 未被引用的 `instruction.webp`（52,752 B）被打进每一个构建产物

* **位置**：`pubspec.yaml:42-43`（`assets: - assets/images/` 注册整个目录）+ `assets/images/instruction.webp`（由 `tools/subset_fonts.py:996-1000` 生成，其自身注释写明 "not referenced from Dart"）。
* **最小复现**：
  ```
  Select-String -Path lib -Include *.dart -Pattern "webp" -Recurse     # 零命中
  Get-ChildItem build\web\assets\assets\images                          # 含 instruction.webp 52752 B
  ```
* **影响**：每次 Web/移动端构建都多带 51 KB 死资源。不影响正确性。

### 11. [低] 英文界面把原文固定前缀 `致：` 换成了 `To: `

* **位置**：`lib/l10n/app_en.arb:17`（`"instructionPrefix": "To: "`）。
* **最小复现**：`flutter test %TEMP%\vfz\final_probe_test.dart` 中 `Locale('en')` 的运行；或直接看 ARB。
* **影响**：这是**有意**的本地化（同文件 `:18` 的 description 已注明"original is 致："），不算 bug；但它是与原版网页唯一的内容级差异，验收方应确认是否接受。`kInstructionPrefix` / `corpusCodePoints` 只收录了 `致：`，而英文前缀用到的 `T`/`o`/`:`/空格都在 Inter 的 99 个命中码点里，不会出现豆腐块。

## 我无法验证的部分

* **上游 `script.js` 是否与本仓库 `指令/script.js` 逐字一致**：环境无法访问网络（`web_fetch https://raw.githubusercontent.com/...` 返回 `TypeError: fetch failed`，`web_search` 亦无结果）。我只能以仓库内的 `指令/` 副本为基准，并且已确认 Dart 语料与**这份副本**逐字一致。
* **真实浏览器/真机行为**：无浏览器与设备可用。因此 CanvasKit 首帧、真实 `localStorage` 配额行为、真机 `navigator.share` 的返回状态、以及"关于页在 release 下点按链接是否仍能打开 URL"（我从 Flutter 源码推断 `GestureRecognizer.invokeCallback` 会吞掉异常让 `onTap` 继续，但未实测）都未验证。
* **README 声称的 89% 行覆盖率 / 27 文件 2693 行**：未运行 `flutter test --coverage`。
* **`tools/subset_fonts.py` 的"783 个码点"与我独立推导的 774 个码点的差集**：我的推导已在不剥注释的超集下运行，并确认只有 U+000A（换行）落在两族字体之外，因此工具的结论方向是可信的；但我没有逐字节复算它那 783 个码点的具体集合。
* **`build/web` 中的 36.10 MiB `canvaskit/` 目录**（含 `skwasm*`、`wimp*` 与 4 个 `*.symbols` 调试符号文件）是否为 `--no-web-resources-cdn` 下 Flutter 3.47 的默认行为：我独立重建到了临时目录但未做文件级 diff，因此不把它列为缺陷。

## 我尝试过但**没有**打破的部分（供参考）

* 语料：转义字符、全角标点、`scrambleChars` 里的 `\\`、首尾空白、跨行条目、代理对 —— 逐条比对 262 条，零差异。
* 彩蛋率：20 万样本落在 0.15 的 95% CI 内；`pureRandom` 的分布与原版 `Math.floor(Math.random()*n)` 等价。
* `ShuffleBag`：n=1..12 × 400 轮穷举、n=2 连续 1 万次、空袋/单元素/中途 `refill`、10 万次首抽分布（chi2 = 0）全部通过。
* 乱码动画的布局不变量：12 组对抗输入（含 `maxLines` 截断 + 省略号、居中参差末行、emoji 代理对、U+20000 星平面字、组合附加符、300 字符不可断长词、`textScaler` 1.5）全部保持恒定尺寸，且 `currentFrame` 的长度/锁定前缀/完成态不变量始终成立 —— 实现方式（真实 `Text` 打底 + 按字格裁剪/覆盖）确实从结构上消除了原版的抖动。
* 溢出：中文 30 组、英文 5 组（280/320/360/1024/2560 px × textScaler 1.0/1.5/2.0，最长语料、开三段面板与自动复制、四个标签页全部滚到底）零 overflow、零异常。
* 构建产物：启动路径唯一、`node --check` 通过、无残留模板 token、无 sourcemap、无第三方分析脚本、manifest 与图标齐全、独立重建 exit 0。

---

## Lead 处置记录

以下处置在收到本报告后完成，**未改动本报告的任何结论**。每一条都补了回归测试；
处置后 `flutter analyze` 为 0 issue，`flutter test` 为 **166/166 通过**。

| # | 严重度 | 是否成立 | 处置 | 回归测试 |
| --- | --- | --- | --- | --- |
| 1 | 高 | 成立 | `lib/features/shell/app_shell.dart` 新增 `PushedPage`：独立路由自带 `Scaffold`（提供 `Material` 祖先）与返回按钮，关于页改由它包裹 | `test/widget_test.dart`「关于页作为独立路由打开时不报错，且链接可点」 |
| 2 | 高 | 成立 | 三处修复：`_safeReadList` 让历史/收藏**互相独立**读取；`_readList` 按条 try/catch 跳过坏记录；`Instruction._decodeTimestamp` 改为夹取而不是抛 `RangeError` | `test/state/prescription_controller_test.dart`「历史损坏不会连带丢掉收藏」「单条记录异常时只丢弃这一条」「读取时就应用历史上限」 |
| 3 | 中 | 成立 | `ScrambleTextState` 增加 `_completionToken` 轮次标记：`_begin()` 自增使上一轮排队的帧后回调作废 | `test/widget/scramble_text_test.dart`「同一帧内 completeNow() 后立即 restart()：onCompleted 不会重复触发」 |
| 4 | 中 | 成立 | `history_page.dart` / `favorites_page.dart` 的 `_share` 改为 await，返回 `false` 时退化为复制并提示 | 由既有页面测试与代码路径覆盖 |
| 5 | 中 | 成立 | `AppSettings.fromJson` 的 `doubleOr` / `intOr` 增加 `isFinite` 判断（`1e400` 解析为 `Infinity`） | `test/state/settings_controller_test.dart`「1e400 之类的超范围数字只影响单个字段」 |
| 6 | 中 | 成立 | `load()` 读取后立即 `_trimmed()` | 同上「读取时就应用历史上限」 |
| 7 | 低 | 有意的 | `historyLimit <= 0` 表示「不限制」，与 ARB 文案 `=0{Unlimited}` 一致，已在 `_trimmed` 补注释说明 | — |
| 8 | 低 | 成立 | `ShuffleBag._avoidBoundaryRepeat` 改为**按值**筛选候选位置，重复项语料下也成立 | 既有洗牌袋测试 |
| 9 | 低 | 成立 | `_InstructionStageState` 在 `initState` 显式初始化 `_tick` 与 `_revealed` | 既有生成页测试 |
| 10 | 低 | 成立 | 删除 `assets/images/instruction.webp`；`tools/subset_fonts.py` 改为写到 `docs/images/`（`pubspec.yaml` 声明的是整个 `assets/images/` 目录，放进去就会被打包） | 构建产物清单 |
| 11 | 低 | 有意的 | 英文前缀 `To: ` 保留：这是本地化，不是复刻偏差 | — |

补充说明：

* 报告「我无法验证」一节提到的 **89% 行覆盖率**已复现：`flutter test --coverage` →
  27 个文件 / 2693 行 / 命中 2396 行 = 89%（处置后行数略增，比例基本不变）。
* 关于页的修复同时补上了**返回入口**：此前该页作为 push 路由既没有 `Material` 祖先，
  也没有任何返回按钮，在移动端/桌面上只能靠系统手势或浏览器后退离开。
* 第 2 条指出的「`lastError` 从未渲染」属实，但处置时**有意未加 UI**：存储损坏属于极罕见的
  静默降级，弹提示反而打扰用户；错误已通过 `debugPrint` 输出并保留在 `controller.lastError`
  里供诊断。
* 上游 `script.js` 与本地 `指令/` 副本的一致性由 Lead 另行确认：本机 `git ls-remote` 可访问
  `hhz-or/web-instruction`（HEAD `7577db0`），且 `指令/` 是一个未被我方改动的 git clone
  （所有文件 mtime 均早于本次会话）。

