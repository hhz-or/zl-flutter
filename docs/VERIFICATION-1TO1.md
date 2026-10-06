# 1:1 复刻独立验证报告（对照 `指令/` 原始三件套）

验证者：独立验证子代理（未修改任何源码；本文件为唯一新增文件）
验证时间：2026-10-04 19:42–19:57
**注意：验证期间工作区被并发修改**（19:43–19:50 期间 `web/index.html`、`lib/core/storage/key_value_store.dart`、`.github/workflows/deploy-web.yml`、`README.md`、`lib/l10n/app_localizations*.dart` 有写入）。本报告所有结论均已在 19:56 之后的当前版本上复核；期间被修掉的两条（`StorageKeys.history/favorites`、CI 里 share_plus 注释）已在发现 #12 里标注为“已修复”。
基准：`指令/index.html`（53 行）、`指令/main.css`（109 行）、`指令/script.js`（154 行）逐行阅读；
所有结论均由我自己的脚本 / Chrome 154 headless / `flutter test` 实测复现，**不采信** README、代码注释、仓库自带测试与提交信息。
探针与日志（可复跑）：`%TEMP%\verify1to1\`（`extract.py`、`css_probe.mjs`、`metrics_probe.mjs`、`rate_probe_test.dart`、`geometry_probe_test.dart`、`port_schedule2_test.dart`、`keyboard_probe_test.dart`、`hover_test.dart`、`bold_flutter_test.dart`、`bold_probe.mjs`）。

## 1. 结论

**不通过** —— 语料、生成语义、随机分支、乱码字符集与动画速率均**逐字节/逐帧等价**，但存在 1 处功能性差异（按钮无法键盘激活）与多处可测量的布局/视觉偏差（logo 下方缺 4px 行内基线间隙、CJK 行高 34px vs 32px、悬停过渡只动背景不动文字、发光 alpha 被调低），另有若干原版没有的可见元素与遗留引用。

## 2. Check A：CSS/HTML/JS ↔ Flutter 全量映射

判定：MATCH=等价；APPROX=有可测偏差；MISSING=未复刻；EXTRA=原版没有。

### 2.1 `index.html` 结构

| 原版声明 | file:line | 端口实现 | file:line | 判定 |
|---|---|---|---|---|
| `<!DOCTYPE html>` `<html lang="zh-CN">` | index.html:1-2 | 同 | web/index.html:2 | MATCH |
| `<meta charset="UTF-8">` | index.html:4 | 同 | web/index.html:12 | MATCH |
| `<meta name="viewport" content="width=device-width, initial-scale=1.0">` | index.html:5 | 追加 `maximum-scale=1.0, user-scalable=no, viewport-fit=cover` | web/index.html:15 | APPROX（禁用了双指缩放，原版可缩放） |
| `<title>指令</title>` | index.html:6 | `<title>指令</title>` + `onGenerateTitle` | web/index.html:18 / app.dart:52 | MATCH |
| `<link rel="icon" href="./instruction.png">` | index.html:8 | `favicon.png` 32×32 + apple-touch-icon + 4 个 PWA 图标 | web/index.html:22-23, icons/ | EXTRA（同一形象，额外文件） |
| `<meta name="description" content="食指指令生成器">` | index.html:9 | 同前缀 + “—— 随机生成一条来自食指的指令” | web/index.html:19 | APPROX（文案加长，不可见） |
| Umami 统计 `<script>` | index.html:10 | 完全删除（仅注释说明） | web/index.html:50 | MATCH（按要求删除） |
| `Cache-Control / Pragma / Expires` meta | index.html:13-15 | 删除 | web/index.html:53-57（注释） | APPROX（本身无效，可接受） |
| `.image-header > img[alt="Header Image"]` | index.html:21-23 | `_HeaderImage`，`semanticLabel = "指令"` | generator_page.dart:104-123 | APPROX（alt 文案被改） |
| `<div id="display-container"></div>`（空） | index.html:25 | 未生成前不渲染文本，仅 `minHeight:100` 占位 | generator_page.dart:165-166 | MATCH |
| `<button id="trigger-btn">获取指令</button>` | index.html:27 | `NeonButton(label: l10n.generateButton)` | generator_page.dart:86-89 / neon_button.dart | APPROX（见 A-2 / 发现 #1） |
| `.footer-note` 文案 | index.html:29 | ARB `footerWarning` 逐字相同 | app_zh.arb:13 | MATCH |
| giscus 评论区 | index.html:35-50 | 完全删除 | web/index.html:51 | MATCH（按要求删除） |

### 2.2 `main.css` 声明逐条

| 原版声明 | file:line | 端口实现 | file:line | 判定 |
|---|---|---|---|---|
| `--neon-blue:#00d2ff` `--bright-white:#fff` `--dark-bg:#000` | main.css:3-5 | `OriginalColors.neonBlue/brightWhite/darkBg` | app_theme.dart:23-32 | MATCH |
| `body{background-color:var(--dark-bg)}` | main.css:9 | `Scaffold(backgroundColor: neon.background)` | app.dart:79 | MATCH |
| `body{color:var(--bright-white)}` | main.css:10 | `textTheme` bodyColor | app_theme.dart:188 | MATCH |
| `body{font-family:'Inter','LXGWWenKai',sans-serif}` | main.css:11 | `fontFamily:'Inter'` + `fontFamilyFallback:['LXGWWenKai']` | app_theme.dart:8-10,185-190 | MATCH |
| `display:flex` | main.css:12 | `Column` + `Scaffold` | generator_page.dart:61 | MATCH（等效） |
| `flex-direction:column` | main.css:13 | `Column` | generator_page.dart:61 | MATCH |
| `align-items:center` | main.css:14 | `crossAxisAlignment:center` | generator_page.dart:67 | MATCH |
| `justify-content:flex-start` | main.css:15 | `Column` 无 spacer + `Expanded(scroll)` | generator_page.dart:62-93 | MATCH |
| `height:100vh` | main.css:16 | Scaffold body 撑满视口 | app.dart:78-87 | MATCH |
| `margin:0` | main.css:17 | Flutter 无 body margin | — | MATCH |
| `overflow-x:hidden` | main.css:18 | 无横向溢出可能 | generator_page.dart:64 | MATCH |
| `.image-header{width:50%}` | main.css:23 | `viewportWidth*0.5` | generator_page.dart:111 | MATCH |
| `.image-header{max-width:600px}` | main.css:24 | `.clamp(0,600)` | generator_page.dart:111 | MATCH |
| `.image-header{margin-top:40px}` | main.css:25 | `SizedBox(height:40)` | generator_page.dart:70 | MATCH |
| `.image-header{text-align:center}` | main.css:26 | 图片在居中 Column 中 | generator_page.dart:67,71 | MATCH |
| **`.image-header` 作为含行内 `<img>` 的行盒** | —— | 端口无对应物 | —— | **MISSING（原版多出 4px 基线间隙，见发现 #3）** |
| `img{width:30%}` | main.css:30 | `(vw*0.5).clamp(0,600)*0.3` | generator_page.dart:111 | MATCH |
| `img{height:auto}` | main.css:31 | 只给 width + `BoxFit.contain`，高度按 186:230 比例 | generator_page.dart:112-118 | MATCH |
| `img{border-radius:8px}` | main.css:32 | `ClipRRect(8)` | generator_page.dart:112-113 | MATCH |
| `#display-container{margin-top:40px}` | main.css:37 | `SizedBox(height:40)` | generator_page.dart:73 | MATCH |
| `min-height:150px` → `min-height:100px` | main.css:38-39 | `minHeight:100` | generator_page.dart:164 | **MATCH：同一声明块内后者胜出，Chrome 实测 computed = `100px`** |
| `font-size:24px` | main.css:40 | `fontSize:24` | generator_page.dart:178 | MATCH（实测 24.0） |
| `font-weight:600` | main.css:41 | `FontWeight.w600` | generator_page.dart:179 | MATCH（含 CJK 伪粗体，实测两端都会合成） |
| `text-align:center` | main.css:42 | `TextAlign.center` | generator_page.dart:171 | MATCH |
| `margin-bottom:60px` | main.css:43 | `SizedBox(height:60)` | generator_page.dart:83 | MATCH |
| `color:var(--bright-white)` | main.css:45 | `neon.textPrimary` | generator_page.dart:181 | MATCH（实测 #FFFFFF） |
| `text-shadow:0 0 5px #fff, 0 0 10px #00d2ff, 0 0 15px #00d2ff` | main.css:46-49 | `glowShadows()` 三层，**alpha 被改成 0.85 / 1.0 / 0.82** | app_theme.dart:73-89 | APPROX（见发现 #5） |
| `padding:0 20px` | main.css:52 | `EdgeInsets.symmetric(horizontal:20)` | generator_page.dart:162 | MATCH（外框 940 = 内容 900 + 40，与 content-box 一致） |
| `max-width:900px` | main.css:53 | `BoxConstraints(maxWidth:900)` | generator_page.dart:164 | MATCH（Chrome 实测内容盒 900、外框 940；端口同为 900/940） |
| `letter-spacing:2px` | main.css:54 | `letterSpacing:2` | generator_page.dart:180 | MATCH |
| `button{margin-top:30px}` | main.css:58 | `SizedBox(height:30)` | generator_page.dart:85 | MATCH |
| `button{padding:15px 20px}` | main.css:59 | `symmetric(horizontal:20, vertical:15)` | neon_button.dart:72-75 | MATCH |
| `button{font-size:14px}` | main.css:60 | `fontSize:14` | neon_button.dart:94 | MATCH |
| `button{background:transparent}` | main.css:61 | `Colors.transparent` | neon_button.dart:77 | MATCH |
| `button{color:#fff}` | main.css:62 | `neon.textPrimary` | neon_button.dart:52 | MATCH |
| `button{border:0px}` | main.css:63 | 无 border 绘制 | neon_button.dart:76-86 | MATCH |
| `button{cursor:pointer}` | main.css:64 | `SystemMouseCursors.click` | neon_button.dart:59 | MATCH |
| `button{transition:all .3s ease}` | main.css:65 | `AnimatedContainer(300ms, Curves.ease)` | neon_button.dart:69-71 | APPROX（只过渡背景/阴影，颜色与字重瞬变，见发现 #4） |
| `button{text-transform:uppercase}` | main.css:66 | `widget.label.toUpperCase()` | neon_button.dart:89 | MATCH |
| `button{letter-spacing:4px}` | main.css:67 | `letterSpacing:4` | neon_button.dart:95 | MATCH |
| `button{text-shadow:0 0 5px #00d2ff}` | main.css:69 | 单层 `softGlow`（悬停时同样保持蓝色） | neon_button.dart:99-104 | MATCH |
| `button{font-family:'Inter','LXGWWenKai',sans-serif}` | main.css:70 | Inter + LXGW 回退 | neon_button.dart:92-93 | MATCH |
| `button:hover{background:#fff}` | main.css:74 | `active → neon.textPrimary` | neon_button.dart:77 | MATCH |
| `button:hover{color:#000}` | main.css:75 | `foreground = neon.background` | neon_button.dart:52 | APPROX（瞬变，发现 #4） |
| `button:hover{box-shadow:0 0 30px #00d2ff}` | main.css:76 | `BoxShadow(accent, blur 25.09)` | neon_button.dart:78-85 | MATCH（σ=15 换算正确） |
| `button:hover{font-weight:bold}` | main.css:77 | `FontWeight.bold` | neon_button.dart:97 | APPROX（瞬变 + 键盘聚焦也触发，发现 #4/#8） |
| `.footer-note{position:fixed}` | main.css:82 | 退化为 Column 底部常驻行（不覆盖内容） | generator_page.dart:94,195-217 | APPROX（等效于不溢出时；溢出时原版覆盖内容） |
| `.footer-note{bottom:20px}` | main.css:83 | `padding bottom:20` | generator_page.dart:204 | MATCH（实测文字底边距视口 20px） |
| `.footer-note{font-size:12px}` | main.css:84 | `fontSize:12` | generator_page.dart:209 | MATCH |
| `.footer-note{color:#fff}` | main.css:85 | `neon.textPrimary` | generator_page.dart:211 | MATCH |
| `.footer-note{letter-spacing:2px}` | main.css:86 | `letterSpacing:2` | generator_page.dart:210 | MATCH |
| `.footer-note{text-shadow:0 0 5px #00d2ff}` | main.css:87 | `softGlow` | generator_page.dart:212 | MATCH |
| `.footer-note` 无左右内边距 | —— | 额外 `padding L/R=20`、`top=8`、`SafeArea` | generator_page.dart:201-204 | EXTRA（320px 下换行点不同，见发现 #6） |
| `@font-face LXGWWenKai`（truetype/normal/swap） | main.css:92-98 | 子集化后的同源字体，`weight 400` | pubspec.yaml:49-52 | MATCH |
| `@font-face Inter`（可变 100–900） | main.css:100-106 | 拆成 Regular/Medium/SemiBold/Bold 四个静态子集 | pubspec.yaml:37-46 | APPROX（用到的 400/600/700 等价；可变轴不再存在） |
| （原版无）行高 | —— | Flutter 按字体 hhea 指标排版，24px 中文行进 = 34px | generator_page.dart:177-183 | APPROX（原版 32px，见发现 #2） |

**计算宽度复核（Check A 专项）**：端口公式 `(vw*0.5).clamp(0,600)*0.3` 与 CSS `min(50vw,600px)*30%` 在 320/768/1280/2560 下实测：48.0 / 115.2 / 180.0 / 180.0，Chrome 实测原版：**45.75**（320×480，页面纵向溢出、经典滚动条占 15px，`clientWidth=305`）/ 115.188 / 180 / 180。768、1280、2560 完全吻合；320 因端口按 MediaQuery 视口宽而非 body 内容宽计算，差 2.25px（见发现 #7）。

## 3. Check B：乱码动画时序与字符集

**字符集**（`script.js:89` ↔ `scramble_text.dart:9-10`，用 Python 各自解析 JS 字符串字面量与 Dart raw 字符串后比较）：
UTF-16 长度均为 **85**，`IDENTICAL == True`；两个原版笔误 `UVWSYZ`、`uvwsyz` 均在；`\\`（反斜杠 + `/`）转义一致；重复字符恰为 `S`、`s`。

**每字锁定时刻**（原版 = 我按 `script.js:97-131` 逐行转写的 60Hz 帧计数模型；端口 = 逐帧 `pump(16667µs)` 读 `ScrambleTextState.lockedCount`）：

| 分支 | 原版每字锁定时刻 | 端口每字锁定时刻 | 偏差 |
|---|---|---|---|
| L=30, step 1 | i/12 s（首字 0.0167） | (i+1)/12 s（首字 0.0833） | 恒定 +1 字（+83.3ms） |
| L=57, step 1 | i/12 s | (i+1)/12 s | 恒定 +1 字 |
| L=20, step 0.6 | 0.1/0.2667/0.35/0.5167/0.6833… | 0.15/0.2833/0.4167/0.5667/0.7… | −16.7ms ~ +66.7ms（≤1 个 5 帧步长） |
| L=12, 5 | 同上 | 同上 | 同上 |

- 速率：端口 `charsPerSecond` 为 `length>20 ? 12.0 : 7.2`（generator_page.dart:150-153），`length = body.length + prefix.length`，与原版 `targetText.length > 20`、`+= 1 / += 0.6` 每 5 帧在 **60Hz 下每字精确定价一致**（实测总时长 2.5001s / 4.7501s / 2.7834s，与 `L/cps` 的 2.5 / 4.75 / 2.7778 相差 ≤1 帧采样粒度）。
- 无 min/max 钳制失真：端口传 `minDuration: Duration.zero, maxDuration: 1 day`（generator_page.dart:175-176，`scramble_text.dart:209-221`），实测结束时刻 = `L/cps`，钳制未生效。
- **帧率依赖差异**：原版按帧计数，120Hz 屏速度 ×2、30Hz 速度 ÷2；端口按时间计，任何刷新率下都恒等于 60Hz 表现（代码注释已声明，但这是与原版的实质差异）。
- 首帧差异：长句分支原版第一次 `update()` 同步在点击回调里执行，第 0 字已显真身；端口首帧全为乱码，晚 1 字。

## 4. Check C：生成语义

| 项 | 结果 |
|---|---|
| `Math.random() < 0.15` → 彩蛋 | MATCH：`_random.nextDouble() < _easterEggRate(=0.15)`（instruction_generator.dart:64-68） |
| 否则 场景+行为+补充、无分隔符 | MATCH：`segments.join()`（instruction.dart:47），三段顺序一致（instruction_generator.dart:78-82） |
| 前缀 `致：` | MATCH：ARB `instructionPrefix='致：'`（2 个 UTF-16 单元），展示层拼接（generator_page.dart:159） |
| 彩蛋率实测（真实代码路径 `PrescriptionController.generate()`，n=1,000,000） | **0.150881**，95% CI **[0.150179, 0.151583]**，含 0.15 |
| 独立复算交叉验证（我手写 JS 公式 vs 端口生成器，同种子 200,000 条） | 正文 **200,000/200,000 完全相同**，彩蛋数同为 30,057 |
| 四组数组逐元素比对（Python 自解析 `script.js` vs Dart 字面量解码） | 场景 27 / 行为 62 / 补充 18 / 彩蛋 23，**mismatch = 0**；均无组内重复 |
| 去重 / shuffle-bag / 加权 | 均无：1,000,000 次抽到 **30,155 种不同正文 = 27×62×18+23（理论全集）**；相邻重复 194/200,000（理论期望约 202），纯随机、允许重复 |

## 5. Check D：“不要乱加任何”

> ⚠️ **本节结论仅适用于当时的 revision（严格 1:1、只有设置按钮）。**
> 之后按用户要求又加回了英文（en）本地化、7 套色板、`glowStrength`、抽取策略
> （`GenerationStrategy` / `ShuffleBag`），因此上面列出的 `语言切换`、`NeonPalette`、
> `GenerationStrategy`、`ShuffleBag` 现在**是有意保留的功能**，不再是残留。
> 仍然删除且不应再出现的是：history/favorites UI、分享、剪贴板、触觉反馈、
> 导航栏/抽屉/关于页、`AppThemeMode`、`AppInfo`、`url_launcher`、`share_plus`、
> giscus、Umami。

**未发现残留功能**（`lib/`、`test/`、`web/`、`pubspec.yaml`、CI 全量 grep）：history/favorites UI、收藏、主题/配色切换、语言切换、分享、剪贴板、触觉反馈、导航栏/抽屉/关于页、`GenerationStrategy`、`ShuffleBag`、`AppThemeMode`、`NeonPalette`、`AppInfo`、`url_launcher`、`share_plus`（唯一残留是 CI 注释，已于验证中途被改写，见发现 #12）。giscus 与 Umami 在 `web/` 与**构建产物**中均不存在（产物 `index.html` 里只有说明性注释）。

| 额外物 | 判定 |
|---|---|
| 右上角设置按钮（app.dart:91-138） | 允许（用户明确许可） |
| 设置弹窗 4 项：减少动效 / 动画速度 / 启用彩蛋 / 彩蛋概率 | 默认值 = `AppSettings.defaults` = `false / 1.0 / true / 0.15`，即原版行为（实测：`switches=[false,true] sliders=[1.0(0.25..3.0),0.15(0..1)]`） |
| 弹窗内“恢复默认”“关闭”按钮、齿轮 Tooltip | 边界内但属额外可见控件（低） |
| `web/index.html` 启动遮罩 `#splash`（标题 + 三层辉光 + 320ms 淡出） | 额外可见元素（低，见发现 #10） |
| PWA manifest / 4 图标 / service worker / `theme-color` / OG+Twitter meta / `color-scheme` / `overscroll-behavior:none` | 平台化附加（低，发现 #11） |
| `shared_preferences` + `KeyValueStore` 抽象、l10n(ARB/intl/flutter_localizations)、Scaffold/ThemeData、`Semantics` | 内部实现细节（可接受） |
| `StorageKeys.history / favorites` | 验证中途已被删除（19:50），当前仅剩 `settings`（低，见发现 #12） |
| `reduceMotion` 响应系统 `prefers-reduced-motion`（app_theme.dart:153-162 等） | 无障碍附加：原版任何情况下都会播放动画（低） |

## 6. Check E：质量门禁复现

| 门禁 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze` | `No issues found!`，exit 0（首次 17.2s；19:56 当前版本复跑 5.3s，仍 0 issues） |
| 测试 | `flutter test` | **106 passing**（`+106: All tests passed!`），exit 0（19:56 当前版本复跑同结果） |
| 字体子集 | `python tools/subset_fonts.py --verify` | exit 0；脚本自采集 **679** 码点全覆盖（并打印 `! lib/l10n/app_en.arb not found` 警告） |
| 字体独立复核 | fontTools 读 5 个字体的 cmap | 我独立采集的 **631** 码点（script.js 字符串 + index.html 文本 + ARB）0 缺失；乱码 85 字形在 Inter 与 LXGW 中均存在 |
| Web 构建 | `flutter build web --release --no-web-resources-cdn --output %TEMP%\verify1to1\webbuild` | exit 0；45 个文件 **42,930,765 B（40.94 MB）**；`canvaskit/canvaskit.wasm` 7,284,602 B、`main.dart.js` 2,436,434 B、`LXGWWenKai-Regular.ttf` 393,900 B、Inter×4 ≈ 392,152 B、`instruction.png` 70,817 B；`*.map` 0 个；构建警告 2 条（wasm dry-run 提示；`Expected to find fonts for (MaterialIcons, packages/cupertino_icons/CupertinoIcons)` —— 来自 l10n 的 Cupertino delegate，未渲染任何 CupertinoIcons，无害） |

构建产物即浏览器实际下载量级：`index.html` 7,764 B + `flutter_bootstrap.js` 16,156 B + `flutter.js` 12,136 B + `main.dart.js` 2,436,434 B + `canvaskit/canvaskit.wasm` 7,284,602 B + 字体 ≈ 786 KB + `instruction.png` 70,817 B ≈ **10.6 MB**（原版为 52 KB HTML/CSS/JS + 24.9 MB 全量 LXGW 字体；端口把字体裁到 394 KB）。

## 7. 发现清单（按严重度）

**阻断**：无。

**#1 高 · 按钮无法用键盘激活（原版 `<button>` 可以）**
- 位置：`lib/core/widgets/neon_button.dart:62-68`（`FocusableActionDetector` 未传 `actions`/`shortcuts`，故不注册 `ActivateIntent`；外层只有 `GestureDetector`）
- 复现：`flutter test %TEMP%\verify1to1\keyboard_probe_test.dart`
- 实测：`tabsToReachCta=2 focused=true` → `enterGenerated=false`、`spaceGenerated=false`、`directFocusEnterGenerated=false`
- 预期：原版是原生 `<button>`，Tab 聚焦后 Enter/Space 触发 `click` 监听器生成指令
- 影响：键盘/读屏用户完全无法生成指令；仓库自带测试（test/widget_test.dart:158）只测了“未聚焦时按空格无效”，掩盖了该差异
- 修复方向（不在本次授权内）：给 `FocusableActionDetector` 加 `actions: {ActivateIntent: CallbackAction(...)}` + `shortcuts`（或直接用 `ButtonStyleButton`）

**#2 中 · 中文行高 34px vs 原版 32px（24px 字号）**
- 位置：`generator_page.dart:177-183`（未设 `height`，Flutter 用字体 hhea 指标）
- 复现：`flutter test %TEMP%\verify1to1\port_metrics_test.dart` 对比 `node %TEMP%\verify1to1\metrics_probe.mjs`
- 实测：同一句 57 字文本，320px 视口下端口文本块 **280×204**（6 行，34px/行）；Chrome 原版 6 行行距 **32px**（行盒 y=142.56/174.56/…），内容高 189
- 预期：行距 32px（12px 页脚行高同理：端口 17px/行，原版 15px/行）
- 影响：≥3 行时指令块比原版高（3 行 +2px、6 行 +12px），窄屏（≤360px）下按钮位置随之下移

**#3 中 · logo 下方缺少 4px 行内基线间隙，整条竖直节奏上移 4px**
- 位置：`generator_page.dart:104-123`（端口把 `<img>` 当作独立块级子元素，没有 `.image-header` 行盒）
- 复现：`node %TEMP%\verify1to1\metrics_probe.mjs`（`gapBelowImg`）+ `flutter test %TEMP%\verify1to1\port_metrics_test.dart`
- 实测：原版 `.image-header` 高 226.58 = 图 222.58 + **4.00**；空态“图底→按钮顶”= **234**（40+4+100+60+30），端口 = **230**；1280px 下按钮顶边 y=496.578（原版）vs 492.581（端口）
- 预期：logo 盒高 = 图片高 + 4px（body 字体基线间隙）
- 影响：logo 以下所有内容（展示区、按钮）整体上移 4px

**#4 中 · `button:hover` 的 300ms 过渡只作用于背景/阴影，文字色与字重瞬变**
- 位置：`neon_button.dart:52`（`foreground` 在 build 中直接切换）、`:97`（`FontWeight.bold` 直接切换）、`:69-86`（`AnimatedContainer` 仅动画 decoration）
- 复现：`flutter test %TEMP%\verify1to1\hover_test.dart`
- 实测：悬停当帧即 `fg=#000000, weight=w700`，而背景由 `transparent` 用 300ms 渐入
- 预期：CSS `transition: all .3s ease` 同时插值 `color` 与 `font-weight`，原版文字由白渐变为黑、背景同步渐白
- 影响：悬停瞬间出现「黑字压在仍透明的黑底上」的不可见帧（取消悬停时同样反向），唯一交互反馈与原版观感不同

**#5 中 · `#display-container` 三层辉光被调低了 alpha**
- 位置：`lib/core/theme/app_theme.dart:73-89`（第 1 层 `textPrimary@0.85`、第 3 层 `accent@0.82`）
- 复现：`flutter test %TEMP%\verify1to1\geometry_probe_test.dart`（打印 displayStyle shadows）对比 `node %TEMP%\verify1to1\css_probe.mjs` 的 `text-shadow`
- 实测：端口 `[#fff@0.85/3.46, #00d2ff@1.0/7.79, #00d2ff@0.82/12.12]`；原版 computed `rgb(255,255,255) 0 0 5px, rgb(0,210,255) 0 0 10px, rgb(0,210,255) 0 0 15px`（全部不透明）
- 预期：三层全部 1.0 alpha
- 影响：招牌霓虹辉光比原版淡（模糊半径换算本身正确：`cssBlurToFlutter` 与 Flutter 的 `radius*0.57735+0.5=σ` 互逆）

**#6 低 · 页脚多出左右 20px / 上方 8px 内边距与 SafeArea**
- 位置：`generator_page.dart:201-204`
- 复现：`flutter test %TEMP%\verify1to1\small_probe_test.dart`
- 实测：320px 视口下页脚文字宽 280（原文可占 305），换行点比原版提前 2 字（行数相同，均 2 行）
- 影响：极窄屏断行位置不同；刘海屏上底部位置与原版不同

**#7 低 · logo 宽度按视口而非 body 内容宽计算**
- 位置：`generator_page.dart:109-111`（`MediaQuery.sizeOf(context).width`）
- 复现：`node %TEMP%\verify1to1\css_probe.mjs`（320×480：`innerWidth=320` 但 `clientWidth=305`，`scrollHeight=533>480` 出现经典滚动条）→ 原版 `img` 宽 **45.75px**，端口 **48px**
- 影响：仅当页面纵向溢出且平台使用占位滚动条（Windows/Linux 经典滚动条）时差 2.25px（4.9%）；overlay 滚动条平台无差异

**#8 低 · 窄屏长文本的溢出行为不同**
- 位置：`generator_page.dart:63-64`（端口用 `SingleChildScrollView`，容器随文本增高）
- 复现：`node %TEMP%\verify1to1\metrics_probe.mjs` + `flutter test %TEMP%\verify1to1\port_metrics_test.dart`
- 实测：320×480、57 字文本。原版 `#display-container` 被 flex-shrink 压到 `min-height` 100px，**6 行文字溢出容器并压到按钮上**（文本底部 y≈331.6，按钮顶 y=330.56）；端口容器长到 204px、页面滚动
- 影响：极小视口下原版会重叠、端口不会（复刻 vs 改良的取舍，需产品决策）

**#9 低 · 键盘聚焦也触发 hover 样式**
- 位置：`neon_button.dart:51`（`active = _hovered || _focused`）
- 影响：原版只有 `:hover`，键盘聚焦不改变外观（属可访问性改良，但非 1:1）

**#10 低 · 原版没有的启动遮罩（splash）**
- 位置：`web/index.html:64-146,175-177`（`#splash` 显示「指令」并带三层辉光，`flutter-first-frame` 后 320ms 淡出）
- 影响：与原版首屏不同；遮罩 CSS 里引用的 `'Inter','LXGWWenKai'` 在该文档中并未加载（Flutter 字体在 assets 内），实际回退到系统字体

**#11 低 · viewport / PWA / 元信息类附加**
- `maximum-scale=1.0, user-scalable=no`（web/index.html:15）禁用了双指缩放（原版 `initial-scale=1.0` 可缩放）；`manifest.json` 使页面可安装且 `orientation:portrait-primary` 锁定方向；另有 `theme-color`、`color-scheme:dark`、OG/Twitter meta、`overscroll-behavior:none`、service worker

**#12 低 · 已删除功能的遗留引用**
- `analysis_options.yaml:26-27`：注释举例仍写 `store/clipboard/…`（`clipboard` 是上一版功能，现已无此代码）
- `tools/subset_fonts.py:86`：仍列出不存在的 `lib/l10n/app_en.arb`，`--verify` 因此每次打印 `! lib/l10n/app_en.arb not found`
- （`test/domain/instruction_generator_test.dart:654-661`、`test/state/settings_controller_test.dart:125-126` 里出现 strategy/historyLimit/paletteId/language/hapticsEnabled 属**反向断言用的垃圾输入**，判定为可接受）
- 验证期间已被修复、仅作记录：`lib/core/storage/key_value_store.dart` 的 `StorageKeys.history/favorites` 已删除（19:50）；`.github/workflows/deploy-web.yml:53` 的 `share_plus 13.x` 注释已改写成 skwasm 相关说明（19:50）。

**#13 低（信息）· 构建清理步骤只删 `*.map`**
- `.github/workflows/deploy-web.yml:64` 只 `find build/web -name '*.map' -delete`，产物中仍有 6 个 `*.symbols`（本次构建 1.5–1.8 MB/个），会一并发布

**已尝试但未能打破的点**（反向结论，供参考）：语料 4 组 0 差异；乱码字符集逐字符相同（85 单元）；彩蛋率 100 万次采样落在 15%±0.07%；1,000,000 次抽满理论全集 30,155 种正文（无去重/加权）；`min-height` 双声明确认 100px 胜出且端口采用 100px；`max-width:900px` 的 content-box 语义（内容 900 + padding 40 = 940）两端一致；`padding:15px 20px`、`letter-spacing`、`text-transform`、`cursor`、`border:0`、`:hover` 的白底黑字 + 30px 蓝影全部对应；Inter/LXGW 字体回退链在 631 个实际渲染码点上 0 缺失；CJK 字重 600 的伪粗体两端**都**会合成（Chrome 墨迹 447→652，Flutter 349→544），不存在“端口缺粗体”问题。

## 8. 无法验证的部分

1. **未做 Flutter Web 产物与原版网页的像素级比对**：几何/样式来自 widget 树实测与 Chrome computed style 两端取证，但没有把构建产物放进浏览器截图 diff（CanvasKit 光栅化与浏览器光栅化的抗锯齿差异会淹没结论）。
2. **Web(CanvasKit) 上的伪粗体路径未实测**：`bold_flutter_test.dart` 跑在宿主 Skia 上；未在浏览器里验证 CanvasKit 是否同样合成 CJK 粗体。
3. **滚动条类差异的平台普适性**：#7 只在 Windows/Linux 经典滚动条 + 页面纵向溢出时成立，macOS/iOS overlay 滚动条不占宽度。
4. **`--no-web-resources-cdn` 之外的其他构建开关（`--wasm`、`--pwa-strategy`）未逐项验证**，仅按 CI 使用的命令复现。
5. **`flutter build web` 的 `.symbols`/`AssetManifest` 是否影响线上行为**未验证（仅统计体积）。
6. **未验证真机（Android/iOS）上的 SafeArea 与系统 prefers-reduced-motion 表现**。

---

## 9. Lead 处置记录

以下处置在收到本报告后完成，**未改动本报告的任何结论**。处置后 `flutter analyze` 为 0 issue，
`flutter test` 为 **107/107 通过**（新增 1 个键盘激活的回归测试）。

| # | 严重度 | 是否成立 | 处置 |
| --- | --- | --- | --- |
| 1 | 高 | 成立 | `neon_button.dart` 补上 `shortcuts` + `actions`：`Enter`/`Space` → `ActivateIntent` → `onPressed`，复刻原生 `<button>` 的键盘激活。回归测试：`test/widget_test.dart`「按钮可以像原生 `<button>` 一样用键盘激活」 |
| 2 | 中 | 成立 | `generator_page.dart` 的展示区样式补上 `height: 4 / 3`（24px × 4/3 = 32px），与 Chrome 实测的霞鹜文楷 normal 行距一致 |
| 3 | 中 | 成立 | `_HeaderImage` 下方补 `SizedBox(height: 4)`，还原 CSS 里 inline `<img>` 的 strut 降部空间 |
| 4 | 中 | 成立 | 按钮文字改用 `AnimatedDefaultTextStyle`（300ms），让 `color` / `font-weight` 跟 `transition: all` 一起过渡，消除悬停首帧「黑字压黑底」 |
| 5 | 中 | 成立 | `NeonTheme.glowShadows()` 三层改回**全不透明**（原版没有写 rgba） |
| 6 | 低 | 成立 | `_FooterNote` 去掉左右 20px / 上方 8px 内边距与 `SafeArea`，回到 `.footer-note` 的 `bottom: 20px`（窄屏换行点与原版一致） |
| 7 | 低 | 不处置 | logo 宽度按 `MediaQuery` 而非 body 内容宽：只在「经典滚动条 + 纵向溢出」的边角情况下差 2.25px，而本项目内容区可滚动、不会出现纵向溢出 |
| 8 | 低 | 有意保留 | 窄屏长文本改为可滚动（原版会被 flex-shrink 压扁并压住按钮）。已在 README「已知限制」中说明 |
| 9 | 低 | 有意保留 | 键盘聚焦复用 hover 样式：原版聚焦时由浏览器画焦点环，两者同属「可见的聚焦指示」；第 1 项修复后键盘可用，必须看得见焦点 |
| 10 | 低 | 有意保留 | 启动 splash 已精简到**只剩标题文字**（去掉旋转圆环与脉冲动画）。原版是纯 HTML 无需启动时间，Flutter Web 要等 CanvasKit，纯黑屏体验更差 |
| 11 | 低 | 成立 | `web/index.html` 的 viewport 改回与原版逐字一致的 `width=device-width, initial-scale=1.0`，去掉 `user-scalable=no`（既更忠实也更无障碍） |
| 12 | 低 | 成立 | `analysis_options.yaml` 的示例标识符改成实际存在的参数名；`tools/subset_fonts.py` 的 `ARB_FILES` 去掉已删除的 `app_en.arb`（不再打印 warning） |
| 13 | 低 | 成立 | `deploy-web.yml` 的清理步骤同时删除 `*.symbols`（canvaskit 调试符号） |

补充说明：

* 报告中确认等价的部分（`min-height` 双声明取 100px、`max-width: 900px` 的 content-box 语义、
  logo 宽度公式、乱码字符集逐字符相同、彩蛋率 0.150881（100 万次采样）、同种子 20 万条与手写 JS
  公式逐条相同、100 万次抽满 30,155 种正文）**均未改动**，本次只修了上表列出的偏差。
* 报告提到的两条「验证期间被并发修掉」的项确认已修：`StorageKeys.history/favorites` 已删除；
  CI 里 share_plus 的注释改为说明「为什么在 3.47 上不用 `--wasm`」
  （多线程 skwasm 在每帧变化的文本上会破坏堆，flutter#190039）。

