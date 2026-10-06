# AGENT.md — 给编码助手的项目说明

本文件写给 AI 编码助手（以及新加入的人类）。它记录的是**代码里看不出来的东西**：
为什么这么写、哪些约定不能破、哪些坑已经踩过。

改代码前请先读完「硬性约定」与「已踩过的坑」两节。

---

## 1. 这是什么

[hhz-or/web-instruction](https://github.com/hhz-or/web-instruction) 的 Flutter 复刻：
按下按钮，用乱码动画逐字揭示一条随机拼装的 Project Moon「食指」指令。

**首要目标平台是 Windows 桌面**，Web 是顺带产物。没有移动端目标，
但代码不含任何平台专属 API，理论上可移植。

原版是纯静态 HTML + CSS + JS，本地参考副本在 `指令/`（**已 gitignore**，
它是独立的 git clone，需要时自己 clone 回来）。

---

## 2. 命令速查

```bash
flutter pub get
flutter gen-l10n                        # 改过 lib/l10n/*.arb 之后必须跑
flutter run -d windows

flutter analyze                         # 必须 0 issue
flutter test                            # 必须全绿
flutter test --coverage
python tools/subset_fonts.py --verify   # 字体覆盖率门禁，exit 0
python tools/subset_fonts.py            # 重新生成字体（需要 指令/）
python tools/subset_fonts.py --images   # 顺带重新生成图片与图标

# 帧时间基准：改任何渲染相关代码前后各跑一次，对比 raster p50
flutter build windows --profile -t benchmark/frame_bench.dart
build/windows/x64/runner/Profile/flutter_zl.exe

flutter build windows --release
flutter build web --release --base-href / --no-web-resources-cdn
```

> ⚠️ **不要并发执行 `flutter` 命令。** 它们会争抢 Flutter 的启动锁，可能卡死十几分钟。

---

## 3. 架构地图

```
lib/
├── main.dart                        启动：读设置 → runApp（设置读失败也要能起来）
├── app.dart                         MaterialApp（主题 / 语言 / 动效）+ HomePage
├── core/
│   ├── storage/key_value_store.dart  KeyValueStore 抽象 + SharedPreferences/InMemory 实现
│   ├── theme/app_theme.dart          颜色令牌、CSS→Flutter 的 blur 换算、辉光生成、ThemeData
│   └── widgets/neon_button.dart      「获取指令」按钮
├── data/
│   ├── models/app_settings.dart      8 个设置字段 + 容错序列化
│   └── instruction_corpus_data.dart  四组语料（逐字转录，**禁止修改**）
├── domain/instruction_generator.dart 抽取逻辑 + ShuffleBag（纯 Dart，不依赖 Flutter）
├── features/
│   ├── generator/
│   │   ├── generator_page.dart       页面结构、页脚、按钮接线
│   │   └── widgets/scramble_text.dart 乱码动画的渲染核心（本项目最复杂的文件）
│   └── settings/settings_dialog.dart 设置面板
├── l10n/*.arb                        中英文案（en 是模板）
└── state/                            SettingsController / PrescriptionController / AppScope
```

### 状态管理

**刻意不引入任何状态管理依赖。** 两个纯 `ChangeNotifier` 控制器通过 `AppScope`
（`InheritedWidget`）注入，控制器不依赖 `BuildContext`，因此可以在纯 Dart 测试里直接构造。

新增状态时请沿用这个模式，不要引入 provider / riverpod / bloc。

---

## 4. 硬性约定

### 4.1 默认值 = 原版行为

`AppSettings` 的每一项默认值都必须复现原版网页。用户不动设置时，
应用与原站**逐像素一致**。新增设置项时，默认值要选「原版行为」那一侧。

### 4.2 语料一个字符都不能改

`instruction_corpus_data.dart` 里的 130 句是逐字转录的，包含荒诞、黑色幽默
乃至不适的内容——**这是原作设定的一部分**。测试会拦住归一化、脱敏、去重、
翻译、增删。这是内容，不是代码，不要「顺手改进」。

### 4.3 注释写「为什么」

注释用中文，解释**为什么**这么写、以及不这么写会怎样。不要复述代码在做什么。
凡是看起来「多此一举」的写法，几乎都是踩过坑之后加的，删之前先看注释。

### 4.4 改文案要连带两件事

1. `flutter gen-l10n`（模板是 `app_en.arb`，中英两份都要加键）；
2. `python tools/subset_fonts.py`（新的汉字必须进字体子集）。

漏了第 2 步的后果：Flutter 会**静默地**从 `fonts.gstatic.com` 下载 Noto Sans SC 兜底，
既破坏离线自持，又引起文字重排。CI 里的 `--verify` 就是拦这个的。

### 4.5 测试要读渲染值，不是目标值

`AnimatedContainer.decoration` / `AnimatedDefaultTextStyle.style` 是**补间目标**，
不是当前渲染值。测「视觉状态」时必须读 `DecoratedBox` 等真正参与绘制的
render object，否则补间类 bug 测不出来（见 §5.2）。

### 4.6 像素测试必须用真实字体

`flutter_test` 默认字体 Ahem 把所有字形画成等宽方块，任何与字形宽度有关的
像素断言在它下面都恒真。`test/widget/scramble_text_test.dart` 里的像素测试会
加载 `assets/fonts/` 下的真实字体，并在字体缺失时跳过——照抄那套写法。

---

## 5. 已踩过的坑

### 5.1 `canvas.clipPath()` 裁不到 `RepaintBoundary` 子节点

裁剪记录在**当前 picture** 里，而 repaint boundary 子节点是作为独立图层
**并列**合成的，裁剪根本作用不到它。

症状：`ScrambleText` 的底座文字包了 `RepaintBoundary` 之后，动画一开始整句
真身就全露出来了。

正确做法：用 `PaintingContext.pushClipPath(...)`（生成裁剪图层）。
注意它的签名是**位置参数**、且 `bounds`/`path` 用**局部坐标**（偏移由它自己加）。

### 5.2 `BoxShadow.lerpList` 无法从「一个阴影」补间到 `null`

它对「多出来的那一项」调用 `scale(t)`，而 `t == 1` 时等于原样保留 —— 阴影**永不消失**。

症状：按钮悬停过一次之后，那圈 accent 发光一直亮着。

正确做法：始终给出**等长**的阴影列表，靠颜色 alpha 淡出。

### 5.3 不要靠「削辉光层数」省性能

曾经为了性能把动画期间的辉光从 3 层削成 1 层。结果是**肉眼可见的「发光变弱」**。

正确做法：让 3 层变便宜。底座文字在动画期间一字不变，把它放进 `RepaintBoundary`
缓存成图层，逐帧只换裁剪区，三层模糊只栅格化一次 —— 既恢复完整辉光，还更快
（raster p50 4.88 ms → 3.83 ms）。

### 5.4 MSVC 需要 `/utf-8`

`windows/CMakeLists.txt` 里给 target 加了 `/utf-8`。源码含中文字符串（窗口标题「指令」），
默认代码页 936 下 MSVC 会报 C4819，配合 `/WX` 直接构建失败。不要删这一行。

### 5.5 CSS 的 blur-radius ≠ Flutter 的 blurRadius

换算走 `cssBlurToFlutter()`：CSS 的 blur-radius 是高斯核标准差的两倍，
Flutter 的 `blurRadius` 会先换算成 `sigma = blurRadius * 0.57735 + 0.5`。
写死数字会让霓虹观感与原版对不上。

### 5.6 JSON 里的 `1e400` 是合法的

`jsonDecode('{"x":1e400}')` 得到 `Infinity`，`clamp()` 会抛 `UnsupportedError`。
`AppSettings.fromJson` 里所有数值都要先 `isFinite` 检查。

### 5.7 OFL 的保留字体名

随应用分发的中文子集叫 `WenKaiZL` 而不是 `LXGW WenKai`：子集在 OFL 意义上属于
Modified Version，而霞鹜文楷声明了 Reserved Font Name，其附加许可只覆盖
「纯为网页字体分发」的子集，**不包括可安装的桌面应用**。

改名前请先读 `THIRD_PARTY_NOTICES.md`。改名涉及三处：
`tools/subset_fonts.py` 的 `LXGW_SUBSET_FAMILY` / `LXGW_SUBSET_PS_NAME`、
`pubspec.yaml` 的 `family:`、`lib/core/theme/app_theme.dart` 的 `kCjkFontFamily`。

### 5.8 截图脚本需要全新的 `--user-data-dir`

`tools/capture_screenshots.mjs` 用 CDP 驱动 headless Chrome（Flutter 渲染在
`<canvas>` 上，普通 DOM 自动化点不到）。复用一个 profile 会拿到缓存里的旧产物。
坐标常量（按钮、齿轮、空白处）在脚本顶部，改了布局要同步改。

---

## 6. 改动后的验收清单

按改动类型选择，**全绿才算完成**：

| 改了什么 | 必须跑 |
| --- | --- |
| 任何 `lib/` 改动 | `flutter analyze` + `flutter test` |
| 文案 / ARB | 上面两项 + `flutter gen-l10n` + `subset_fonts.py`（重新生成） |
| 渲染 / 动画 / 布局 | 上面全部 + 帧时间基准（对比 raster p50）+ 重新截图 |
| 语料 | 上面全部（测试会拦改动，除非是有意为之） |
| `windows/` | `flutter build windows --release` |
| 依赖 | `flutter analyze` + `flutter test` + 两个平台的 release 构建 |

提交前请确认工作区没有 `build/`、`coverage/`、`*.log`、临时 profile 目录等残留。

---

## 7. 有意保留的差异

以下是**有意**与原版不同，不是 bug，不要「修回去」：

* 右上角设置按钮 + 设置弹窗（本应用唯一新增的界面）
* 「获取指令」按钮有 8px 圆角（原版 `border: 0` 无圆角）
* 底部警告下方多一行免责声明
* 内容区允许滚动（原版窄屏下内容会被 flex-shrink 压扁并压住按钮）
* 动画按**时间**推进而非按帧（原版在 120 Hz 屏上会快一倍）
* 启动时有一层纯文字 splash（Flutter Web 要等 CanvasKit）
* 不使用 `--wasm`（flutter#190039，多线程 skwasm 在逐帧变化的文本上有堆破坏）

细节与理由见 [docs/FIDELITY.md](docs/FIDELITY.md)。
