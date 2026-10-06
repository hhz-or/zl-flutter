# 独立验证：性能修复 / 英文本地化 / 新设置（VERIFICATION-PERF）

**结论（一行）**：三项改动的门禁我全部独立复现通过——乱码动画的 raster 开销确实被压到 60fps 预算内（实测 p50 5.29 ms / p90 6.90 ms，5/1251 帧超预算），未锁定真身确实没有泄漏、已完成态确实逐像素等于 `Text`、设置与本地化的容错与统计语义全部成立；**没有阻断级或高severity 缺陷**，只有 1 个中severity 的流程问题（验证期间仓库被并发改动）和 7 个低severity 的实现/文档瑕疵。

---

## 0. 验证对象与环境

| 项 | 值 |
| --- | --- |
| 工具链 | Flutter 3.47.6 stable · Dart 3.13.5 · Impeller（`OpenGLESSDF`） |
| 系统 | Windows 10 专业版 22H2（19045.4894）· VS 生成工具 2026 18.10.3 |
| 仓库 | `C:\Users\Administrator\Documents\vscode\2026\flutter-zl` |
| 关键文件指纹（SHA-256 前 12 位） | `scramble_text.dart`=F272F98877F8 · `generator_page.dart`=4285C71B5AEF · `app_settings.dart`=8ADC660CDF0C · `app_theme.dart`=BC39CC0B8B55 · `settings_dialog.dart`=47D6C94DACB3 · `widget_test.dart`=2434E7F28329 · `frame_bench.dart`=0902FB027CC6 |
| 隔离手段 | 只读仓库；所有一次性测试与改造版基准都放在 `%TEMP%\fzl-verify` 的副本里（该副本 `lib/` 与仓库逐文件哈希一致，mismatch=0） |
| 唯一写入 | 本文件 |

---

## 1. 结果表

### Check A — 性能修复是否真实、动画是否仍然正确

| # | 命令 / 手段 | 观察到的数字 | 判定 |
| --- | --- | --- | --- |
| A1a | `flutter build windows --profile -t benchmark/frame_bench.dart` → `build\windows\x64\runner\Profile\flutter_zl.exe`（最终 revision） | build n=1251 mean 0.42 **p50 0.34** p90 0.49 p99 1.28 max 11.58 ms；**raster n=1251 mean 5.55 p50 5.29 p90 6.90 p99 12.70 max 26.96 ms**；total p50 6.82 p90 8.61 ms；**raster > 16.67 ms：5 / 1251 帧** | PASS（p50、p90 均 < 16.67 ms） |
| A1b | 同上，第一次运行（窗口期快照，`lib/` 与最终一致） | raster n=1259 mean 5.92 **p50 5.84 p90 7.36** p99 9.59 max 14.69 ms；**0 / 1259 帧超预算** | PASS |
| A1c | 对照声称值（修复后 p50 6.13 ms / 5-of-1257） | 我实测 5.29–5.84 ms / 0–5-of-1251…1259 | 与声称值一致（差异在噪声范围内） |
| A1d | 对照声称的基线（p50 59.57 ms / 318-of-335） | 旧二进制已被覆盖，**无法复现** | 无法验证（见 §3） |
| A2a | `flutter test test/zz_perf_verify_test.dart`（`%TEMP%\fzl-verify`，真实中文字体 + 独立测量的字格掩码） | 动画中段：已锁定格有墨迹；**未锁定格墨迹 = 0 像素**；格外墨迹 = 0；守卫：把底座换成未裁剪整段真身时同一掩码下未锁定格墨迹 > 0（非空洞） | PASS |
| A2b | 同上：锁定前缀 vs `Text` 裁到同样字格 | **差异字节 = 0**；守卫 1：参照物有墨迹；守卫 2：参照物 ≠ 未裁剪整段真身（证明这条断言真的可能失败） | PASS（仓库里同名测试也真实执行，未被跳过——`C:\Windows\Fonts\simhei.ttf` 存在） |
| A2c | 同上：多行（`'指令'×40`，200 px 宽折成多行） | 未锁定字格中**没有落墨的格子 = 0**；所有字格之外墨迹 = 0 | PASS |
| A2d | `zz_spill_test.dart` / `zz_realfont_test.dart`：用**应用真实字体**（`Inter-SemiBold.ttf` + `LXGWWenKai-Regular.ttf` 子集）与 `generator_page.dart` 同构样式重现「锁定前缀 = 裁剪 Text」 | 乱码层画空格（隔离变量）时差异字节 **0 / 0**；纯中文真身 + 宽字形 `W` 差异 **0**；`'…说30!'` + 宽字形 `W` 差异 **23 字节（≈6 像素）** | PASS（含 1 处低severity 反例，见发现 2） |
| A2e | `zz_perf_verify_test.dart` A2-4：无 shadow / 有 shadow 两版同帧对比 | 无 shadow：未锁定区**被辉光色染色的像素 = 0**；有 shadow：未锁定区墨迹 1750 → 5500 像素、染色像素 3804 → 保存层确实是条件执行的 | PASS |
| A2f | A2-5：`blurRadius: 40` 的强辉光是否漫到已锁定字符 | 锁定区差异字节 **= 0** | PASS |
| A2g | `scramble_text.dart:1030-1034` 代码审读 + 仓库测试「完成后与同样式 Text 逐像素一致」（参照图有墨迹守卫） | 完成分支逐字为 `super.paint(context, offset)`，无 clip、无 saveLayer；像素差 = 0 | PASS |
| A3a | `zz_perf_verify_test.dart` A3：播完后 `tester.binding.hasScheduledFrame` / `renderObject.debugNeedsPaint` 连续 10 个空闲帧 | 均为 `false` → **没有空转重绘循环** | PASS |
| A3b | `%TEMP%\fzl-verify\benchmark\frame_bench_glow.dart`（同进程内先 `glowStrength=1.0` 20 s、再 `0.0` 20 s） | glow=1.0：raster n=953 mean 6.90 **p50 6.60** p90 8.75 p99 14.03 ms（4/953 超预算）；glow=0.0：n=1166 mean 2.33 **p50 2.11** p90 2.85 p99 8.97 ms（5/1166） | PASS：`glowStrength=0` 让 raster p50 **下降 68%**，辉光确实是剩余开销的主体 |

### Check B — 新设置与本地化

| # | 命令 / 手段 | 观察到的数字 | 判定 |
| --- | --- | --- | --- |
| B1a | `flutter gen-l10n`（在副本里跑，避免改仓库源码） | 三个生成文件 **SHA-256 与仓库逐字节相同**（57BF0EFF2093 / 70AF35B75F44 / 21B97BAE6DB1） | PASS |
| B1b | 脚本比对 `app_en.arb` / `app_zh.arb` / `lib/**/*.dart` 的键集合 | 两份 ARB 各 **29 键**，键集完全相同；`lib/` 用到的 29 键全部命中；**未使用键 = 0**，**缺失键 = 0** | PASS |
| B1c | 全量搜 `lib/` 中的中文字符串字面量 | 仅 `NeonPalette.labelZh`（7 条，按 `labelFor(locale)` 切到 `labelEn`）与 `kInstructionPrefix`；其余全是文档注释 / `debugPrint` / `assert` 文案（非用户可见） | PASS（含 2 处低severity 见发现 3、4） |
| B2a | `zz_settings_l10n_verify_test.dart`：`AppSettings(language: en, reduceMotion: true)` + `InstructionApp` | 按钮 = `GET INSTRUCTION`；页脚为英文；弹窗含 Settings/Appearance/Motion/Generation/Draw strategy/Close；**全页含中文的 `Text` 集合 = `{'简体中文'}`**（语言自名，预期）；没有任何 `Text` 等于 ARB 键名 | PASS |
| B2b | 同上：生成一条指令 | 显示文本 = `'To: ' + body`，不含 `致：` | PASS |
| B2c | `AppLanguage.system` + 平台语言 `en_US` / `zh_CN` / `fr_FR` | 英 / 中 / 中 | PASS |
| B2d | `neon_button.dart:133` 的 `toUpperCase()` | Dart 的大小写映射与区域无关，`'Get Instruction' → 'GET INSTRUCTION'`，中文标签不变 → 英文/中文两种语言下都与原版 `text-transform: uppercase` 等价 | PASS |
| B3a | `AppSettings` 八字段往返（含经 `jsonEncode`/`jsonDecode` 的真实 JSON 往返） | 8/8 字段一致，`toJson` 键集恰为 8 个 | PASS |
| B3b | 逐字段容错：`language:'klingon'`、`strategy:'bogus'`、类型全错、`Infinity`、`NaN`、越界 | 异常字段各自回退（`system` / `pureRandom` / 默认值 / 钳到 [0,1]），**同一条 JSON 里的正常字段全部保留**；已删除旧键（`historyLimit`/`themeMode`/`autoCopy`/`hapticsEnabled`/`glowEnabled`）被忽略且不影响其余字段 | PASS |
| B3c | `SettingsController.load()` 读入坏字段后落盘 | `lastError == null`，`paletteId`/`animationSpeed` 保留，坏字段回退 | PASS |
| B3d | 默认 `AppSettings()` | `paletteId='index_blue'`（`#00D2FF`）· `language=system` · `glowStrength=1` · `reduceMotion=false` · `animationSpeed=1` · `easterEggEnabled=true` · `easterEggRate=0.15` · `strategy=pureRandom` | PASS（`language` 见发现 6） |
| B3e | `NeonTheme` 辉光令牌 | `glowShadows()` 三层值与原版 CSS 逐值一致（sigma = 2.5 / 5.0 / 7.5）；`layers` 只裁层数；`glowStrength=0` 时 `glowShadows`/`animationGlow`/`softGlow` 全空；`animationGlow` = 单层 accent、sigma = 5.0（= 原版中间那层 10 px） | PASS |
| B3f | 应用级：动画中 / 播完 / 减少动效 | 播放中 `shadows.length == 1`；播完 `== 3`；`reduceMotion` 时直接 `== 3` | PASS |
| B4a | `ShuffleBag`：26 个互异元素 × 200 轮 | 每轮 26 个元素**恰好各出现一次**，无重复 | PASS |
| B4b | `ShuffleBag`：`['a','a','b','b','b','c','d','d']` × 200 轮 | 每轮多重集合 == 源列表多重集合（重复项按重数抽取） | PASS |
| B4c | 跨轮边界：4000 次抽取 | 只要列表里有 ≥2 种值，每轮首个元素 **从不**等于上轮末尾（`_avoidBoundaryRepeat` 按值而非按位置筛选候选） | PASS |
| B4d | 边界：全同值列表 / 空列表 / 单项 | 全同值可重复（无从避免）；空列表 `next() == null`；单项恒定 | PASS |
| B5a | 随机调用结构（自写 `_CountingRandom implements Random`） | 2000 次生成：每次**恰好 1 次 `nextDouble`**（彩蛋判定）；三段式再 **3 次 `nextInt`**，彩蛋再 **1 次**；彩蛋占比 0.1485 ≈ 0.15 | PASS（与原版 `script.js` 的调用次数/顺序同构） |
| B5b | `nextInt` 均匀性：7 桶 × 21000 次 | χ² < 40（df=6，p=0.001 临界 22.46） | PASS |
| B5c | `pureRandom` 允许重复 | 400 次生成出现连续重复 > 0 次 | PASS |

### Check C — 门禁复现

| # | 命令 | 观察值 | 判定 |
| --- | --- | --- | --- |
| C1 | `flutter analyze` | `No issues found! (ran in 6.0s)` | PASS（0 issue） |
| C2 | `flutter test`（最终 revision） | **114 个测试全部通过**（`00:11 +114: All tests passed!`） | PASS |
| C2' | `flutter test`（20:31 之前的 revision） | 113 通过——差 1 个来自 20:32:47 的 `widget_test.dart` 外部改动，见发现 1 | — |
| C3 | `python tools/subset_fonts.py --verify` | **exit 0**；采集 **701 个码点**（601 CJK/全角 + 100 拉丁/符号）；5 个输出字体 cmap 全部覆盖 | PASS |
| C4 | `flutter build web --release --no-web-resources-cdn --output=%TEMP%\fzl-webbuild` | **exit 0**；产物含 `canvaskit/`（CDN 已内联）、`main.dart.js` 2,459,837 B、`index.html` 7,653 B、`manifest.json`、service worker | PASS |
| C5 | `Get-ChildItem assets\images` | 只有 `instruction.png`（70,817 B） | PASS |
| C6 | 全仓 grep：`history` / `favourite` / `about` / `share` / `clipboard` / `haptic` / `NavigationRail` / `NavigationBar` / `AppThemeMode` / `AppInfo` / `url_launcher` / `themeMode` / `autoCopy` / `historyLimit` | `lib/`：仅 3 处说明性注释；`test/`：`findsNothing` 反向断言 + 垃圾输入字符串；`web/`、`.github/`、`pubspec.yaml`：**0 命中** | PASS（`docs/` 除外，见发现 8） |

---

## 2. 发现（按严重度）

### 1. [中] 验证期间仓库被并发改动，未固定 revision 的验证结论会自动失效

* **位置 / 证据**：`windows/runner/main.cpp`、`windows/CMakeLists.txt`（mtime **20:31:18**）、`test/widget_test.dart`（**20:32:47**）、`README.md`（**20:33:28**）在本会话（起始 20:28:44）开始后、且在我 20:29:47 取快照之后被改写；这四处都不是我跑过的命令（`flutter build windows`、`flutter analyze`、`flutter test`、`flutter gen-l10n`）会写的文件。
* **最小复现**：
  1. 20:29:47 用 robocopy 取一份副本；
  2. 在副本里跑 `flutter build windows --profile -t benchmark/frame_bench_glow.dart`；
  3. **构建失败**：`windows\runner\main.cpp(1,1): error C2220: 以下警告被视为错误 … warning C4819`（该快照还没有 `windows/CMakeLists.txt` 里的 `target_compile_options(${TARGET} PRIVATE /utf-8)`）；
  4. 把仓库当前的 `windows/` 同步进副本后，同一命令 exit 0。
* **观察 vs 预期**：观察 = 同名文件在会话中途内容变化（`main.cpp` 1485 B ↔ 1591 B；`widget_test.dart` 让测试总数 113 → 114）。预期 = 一次验证对应一个固定 revision。
* **影响**：任何早于 20:32:47 的 `flutter test` 结论都不覆盖当前的 `widget_test.dart`；性能基线二进制也在窗口期内被换过一次。本报告 §1 的所有数字都已在最终 revision（§0 指纹）上重跑。**建议**：验收时用 commit/tarball 固定 revision，或记录文件指纹。
* **本次验证在仓库里留下的痕迹**（供核对）：新增 `docs/VERIFICATION-PERF.md`；`build/` 下的 profile/web 产物；`lib/l10n/app_localizations*.dart` 被 `flutter test` 同内容重写（字节不变）；仓库根目录多出一个 0 字节 `w.log`（已被 `.gitignore` 的 `*.log` 忽略，非源码）。源码、测试、资源、配置、`指令/` 均未改动。
* **补充（已排除）**：`lib/l10n/app_localizations*.dart` 的 20:35:20 mtime 来自 `flutter test`/`gen-l10n` 的**同内容重写**——三个文件与副本里重新生成的结果逐字节相同，不影响结论。

### 2. [低] 乱码「清晰层」只裁到整个文本框，比字格更宽的字形会盖住最后一个已锁定字符

* **位置**：`lib/features/generator/widgets/scramble_text.dart:1084-1087`（`clipRect(bounds)` 后画字形），对照 `:1057-1058` 的注释「…这一逐像素保证就没了」。位置计算在 `:1009-1015`（按真实字格居中，不按字格裁剪）。
* **最小复现**（副本 `test/zz_realfont_test.dart`）：加载 `assets/fonts/Inter-SemiBold.ttf` + `LXGWWenKai-Regular.ttf` 子集，样式取 `generator_page.dart:219-229` 同构（24 px / w600 / letterSpacing 2 / height 4/3），文本 `'请在两分钟内对着镜子说30!'`，`glyphs: 'W'`，泵到 `lockedCount == 12`，再把锁定区与「`Text` 裁到同样字格」逐像素对比。
* **观察 vs 预期**：观察 = **23 字节（≈6 像素）差异**，集中在最后一个已锁定字格 `['3'，宽 17.27 px]` 的 `x∈[485,487]`（`'W'` 步进 26.48 px，居中后向左溢出 ≈3.6 px）。预期 = 0。对照：隔离变量（乱码层画空格）差异 **0**；纯中文真身 + `W` 差异 **0**（中文格 26.0 px 刚好放得下）；宿主字体 simhei 因拉丁字形等宽（`i` 与 `W` 都是 11.0 px）也恒为 0。
* **影响**：仅在「最后一个已锁定字符是窄 ASCII（数字/标点）且下一格抽到宽字形」时出现几像素的瞬时重叠，肉眼几乎不可见；**不是本次性能修复引入的**（清晰层一直是这个裁法）。但它说明注释里「已锁定前缀逐像素等于裁剪 Text」的表述过强——准确的表述是：**辉光层**被裁到未锁定字格（A2f 已证明无漫溢），**清晰层**只裁到文本框。建议把清晰层一并裁到 `unlockedPath`。

### 3. [低] `kCorpusSourceNote` 是死代码，注释还指向已删除的「关于」页

* **位置**：`lib/data/instruction_corpus_data.dart:157-159`。
* **最小复现**：`grep -rn "kCorpusSourceNote" lib test` → 只有定义处一处命中。
* **观察 vs 预期**：观察 = 无任何引用，注释写「用于「关于」页展示」。预期 = 关于页已删除（Check C6 确认），该常量应删除或改注释。
* **影响**：误导读者以为仍存在关于页；`tools/subset_fonts.py` 会把它的码点收进字体子集（方向安全，只是白收一个 URL）。

### 4. [低] `kInstructionPrefix` 与 ARB 的 `instructionPrefix` 是两份硬编码

* **位置**：`lib/data/instruction_corpus_data.dart:164`（`'致：'`）vs `lib/l10n/app_zh.arb:6`（`"instructionPrefix": "致："`）。
* **最小复现**：改 `app_zh.arb` 的前缀 → 只有 `generator_page.dart:81` 的显示会变；两者不会互相校验。
* **观察 vs 预期**：观察 = 同一 UI 字符串两处定义。预期 = 单一来源。风险目前被 `subset_fonts.py` 也扫描 `app_zh.arb`（verify 输出「`lib/l10n/app_zh.arb : 60 JSON string(s)`」）兜住，所以改前缀不会产生豆腐块。
* **影响**：纯维护性问题；两处漂移后字体子集的「一个不多、一个不少」不再成立（方向仍是超集，安全）。

### 5. [低] `paletteId` 不做白名单校验，脏值会被原样保留并落盘

* **位置**：`lib/data/models/app_settings.dart:140`（`stringOr('paletteId', …)` 只检查「非空字符串」）。
* **最小复现**：`AppSettings.fromJson({'paletteId': 'no_such_palette'}).paletteId == 'no_such_palette'`。
* **观察 vs 预期**：观察 = 脏 id 被保留，`settings == AppSettings.defaults` 永假 → 设置弹窗「恢复默认」按钮长期可点；`NeonPalette.byId` 渲染时兜底到 `index_blue`，界面仍然正确。预期 = 按 `NeonPalette.values` 规范化。
* **影响**：无视觉影响，只是脏值无限期驻留。与 `neon_palette.dart:16` 的注释（「改动会导致旧设置回退到默认色板」）描述的行为不完全一致。

### 6. [低] 默认 `language: system` 让「默认值即原版行为」只在中文系统成立

* **位置**：`lib/data/models/app_settings.dart:28`、`lib/app.dart:64-90`。
* **最小复现**：`tester.platformDispatcher.localesTestValue = [Locale('en','US')]` + 默认设置 → 按钮渲染为 `GET INSTRUCTION`（原站只有中文）。
* **观察 vs 预期**：观察 = 英文系统上默认界面为英文。预期 = 原版逐像素一致。
* **影响**：属于新功能的有意设计（弹窗里也可切回中文），但「不改任何一项时应用与原站逐像素一致」这句话需要加「中文系统」这个前提。

### 7. [低] 英文模式下 Web 外壳仍是中文

* **位置**：`web/index.html`（`<html lang="zh-CN">`、`<title>指令</title>`、闪屏 `.splash-title` = 「指令」）、`web/manifest.json`（`name`/`short_name`/`description`/`lang`）。
* **最小复现**：Web 构建里选 English → 浏览器标签标题、PWA 安装名、启动闪屏仍为中文。
* **观察 vs 预期**：观察 = 外壳不随应用语言变化（静态 HTML，无本地化机制）。预期 = 至少 `<html lang>` 与标题一致。
* **影响**：不一致但可控；应用内文案不受影响。属于本次「英文回归」的边界外残留。

### 8. [低] 文档过期：`docs/VERIFICATION-1TO1.md` 仍断言语言切换/色板/洗牌袋已被删除

* **位置**：`docs/VERIFICATION-1TO1.md:132`。
* **最小复现**：`grep -n "语言切换" docs/VERIFICATION-1TO1.md` → 「未发现残留功能（… 语言切换 … `GenerationStrategy`、`ShuffleBag` … `NeonPalette` …）」。这些现在都是本轮**有意加回**的功能。
* **观察 vs 预期**：观察 = 旧报告把现已存在的功能列为「已确认无残留」。预期 = 加一句修订说明或标注结论失效范围。
* **影响**：后续读者/审查者会被误导。

---

## 3. 无法验证的部分

1. **修复前的基线（raster p50 59.57 ms、318/335 帧超预算）**：基线二进制被同路径的 profile 产物覆盖，仓库里也没有可比对的旧 commit 产物，因此「提速 10 倍」这个**幅度**只能靠当前值的绝对达标来间接支持，无法直接复现。可证的只有：当前构建 raster p50 5.29–5.84 ms、p90 6.90–7.36 ms，稳定在 60fps 预算内。
2. **声称值的逐位一致性**：声称 p50 6.13 ms / 5-of-1257，我实测 5.29–5.84 ms / 0–5-of-1251…1259。同一区间，但不能断言是同一台机器同一时刻的同一数字。
3. **`saveLayer` 的操作计数**：`_glyphGlow`/`_paintGlyphs` 是私有的，无法直接统计保存层调用次数；只能用像素后果反证（A2e 证明无 shadow 时不产生任何被辉光色染色的像素；有 shadow 时墨迹 1750 → 5500、染色像素 3804），并辅以代码审读。
4. **Impeller 上的像素级结论**：`flutter test` 走的是 CPU/Skia 光栅化路径；§1 的像素对比（A2a–A2f、D 系列）都在该路径上完成，Impeller 只被基准程序覆盖到（耗时维度）。裁剪是否生效属于 picture 语义，理论上与后端无关，但未在 Impeller 上做像素复核。
5. **真机/真浏览器的英文渲染**：只做了 widget 测试，没有在 Web/Windows 产物上肉眼核对英文界面与 `text-transform` 效果。
6. **发现 2 的可见性**：只在 1.0 倍像素比、24 px 字号下量到 23 字节；不同 DPR / 字号 / 系统字体回退下是否可见未测。
7. **非 Windows 平台**：Android / iOS / macOS / Linux 的构建与基准完全未验证。
8. **并发改动的影响面**：`windows/runner/main.cpp` 与 `windows/CMakeLists.txt` 的改动只做了「改后能构建」的间接验证（副本同步后 `flutter build windows` exit 0），没有逐行审读这次改动本身。

---

## 10. Lead 处置记录

以下处置在收到本报告后完成，**未改动本报告的任何结论**。处置后 `flutter analyze` 为 0 issue，
`flutter test` 为 **115/115 通过**。

| # | 严重度 | 是否成立 | 处置 |
| --- | --- | --- | --- |
| 1 | 中 | 说明 | 验证期间确实在并发改仓库（补 `/utf-8`、加测试、改 README）。报告的数字已在最终 revision 重跑，验收以本文件之后的最终 commit 为准 |
| 2 | 低 | 成立 | 清晰字形层不再只裁文本框，改为裁 `Path.combine(difference, 文本框, 已锁定字格)`，宽字形（如窄格里的 `W`）不会再盖住最后一个已锁定字符。该路径按 `(locked, offset, size)` 缓存，动画期间每秒只重算约 12 次而不是每帧 |
| 3 | 低 | 成立 | 删除死代码 `kCorpusSourceNote`（注释指向的是已删除的「关于」页） |
| 4 | 低 | 成立 | 删除 `kInstructionPrefix`：正文前缀改由 `lib/l10n/app_zh.arb` 单点提供，`corpusCodePoints()` 不再拼进前缀（构建脚本本来就会扫 ARB，字体子集覆盖不受影响）。相应测试改为断言 ARB 里的那一份 |
| 5 | 低 | 成立 | `SettingsController.normalize()`：读取设置时把白名单外的 `paletteId` 收敛回默认值，脏值不再被写回存储 |
| 6 | 低 | 有意保留 | 默认 `language = system`：跟随系统是 i18n 的常规默认。代价是「默认即原站」只对中文系统成立，已在 README 的设置表里写明默认值与回退规则 |
| 7 | 低 | 有意保留 | Web 外壳（`index.html` / `manifest.json` / 启动 splash）是构建期固定的中文。Web 是次要目标，且按语言生成两套外壳的收益不足；已在 README「已知限制」注明 |
| 8 | 低 | 成立 | `docs/VERIFICATION-1TO1.md` 第 5 节已加上时效说明：语言切换 / `NeonPalette` / `GenerationStrategy` / `ShuffleBag` 现在是**有意保留**的功能，不再是「残留」 |

补充：报告 §2 里「`glowStrength` 1.0 → 0.0 使 raster p50 6.60 → 2.11 ms」这一测量很有价值 ——
它确认了剩余开销的主体仍是辉光，因此设置面板把「霓虹发光」同时当作性能开关暴露给用户。

