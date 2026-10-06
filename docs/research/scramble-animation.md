# Flutter 版「乱码解码」(Scramble) 动画技术调研

> 移植网站 JS 版 `startScrambleAnimation`，并针对**中文 + 霓虹辉光 + 多行 + 零抖动 + 减弱动效**优化。
> 基准：**Flutter 3.47.5 / Dart 3.13.4**（本机 `C:\Users\Administrator\flutter`，`flutter --version` 已核实）。下文 API 均在该 SDK 源码中逐条核对。

## 0. 结论速览

| 议题 | 结论 |
|---|---|
| 驱动 | `AnimationController` + `CustomPainter(repaint: controller)`；**不要** `Timer.periodic`，**不要**每帧 `setState` |
| 抗抖动 | **方案 (e)：预留最终文本布局，只换蒙版**。`TextPainter` 只对最终文案排版一次，`getBoxesForSelection` 取每字盒子；逐帧只重绘不重排 |
| 尺寸恒定 | `CustomPaint.size = TextPainter.size`（最终文案尺寸）⇒ 父级永不重排 |
| 随机字形 | 预烘焙 `ui.Paragraph` 字形缓存；**绝不**把 ASCII 拼进 `Text.rich` |
| 辉光 | 动画中只开 1 层小模糊 `Shadow`，结束后切 3 层完整辉光 + `RepaintBoundary` |
| 确定性 | 字形选择用纯函数 `int Function(int frame, int charIndex)`（或注入 `Random(seed)`） |
| 减弱动效 | **必须同时查** `MediaQuery.disableAnimationsOf` **和** `PlatformDispatcher.accessibilityFeatures.reduceMotion`（iOS 只给后者） |
| 无障碍 | `ExcludeSemantics` 包动画层 + 外层 `Semantics(label: 最终文案)` |
| Web | `--wasm` + `forceSingleThreadedSkwasm: true`（3.47.x 多线程 skwasm 逐帧改文本会崩，§4.5） |

---

## 1. 动画驱动：Controller vs Ticker vs Timer.periodic

| | `Timer.periodic` | `Ticker` | `AnimationController` |
|---|---|---|---|
| vsync 对齐 | ❌ 独立时钟，掉帧后连发回调 | ✅ 每帧一次 | ✅ 内部即 `Ticker` |
| 自动静音 | ❌ | ✅ 随 `TickerMode` | ✅ 同左 |
| 时间语义 / 测试 | 无 / 差 | `Duration elapsed` / 中 | `double value` 0→1 + `TickerFuture` / ✅ `tester.pump(Duration)` |
| 减弱动效 | 自己写 | 自己写 | ✅ `AnimationBehavior` 内建 |

`Ticker` 是唯一被官方认定的逐帧原语："Calls its callback once per animation frame, when enabled."（[Ticker](https://api.flutter.dev/flutter/scheduler/Ticker-class.html)）。`AnimationController` 每次设备准备显示新帧时产生一个新值（"typically, this rate is around 60–120 values per second"），并随 `TickerMode` 静音（[AnimationController](https://api.flutter.dev/flutter/animation/AnimationController-class.html)）。**不要用 `Timer.periodic`**：120 Hz 设备上它仍按自有节奏触发，视觉上半速；丢帧时还会补偿连发，破坏 `frame % stepSpeed` 节奏。

**把"帧计数"改成帧率无关**（原 JS 在 120 Hz 下速度会翻倍）：

```dart
final double step = N > longTextThreshold ? charsPerStepLong : charsPerStepShort; // 1.0 / 0.6
final int totalFrames = (N / step).ceil() * framesPerStep;                       // 原 JS: 5
_controller = AnimationController(vsync: this, duration: frameBudget * totalFrames);
// frameBudget = 16683µs ≈ 59.94fps；paint 内恢复等价游标：
final int elapsed = (_controller.value * totalFrames).floor();
final int cursor  = ((elapsed ~/ framesPerStep) * step).clamp(0, N).toInt();
```

**避免重建子树（代价由低到高）**：① `CustomPainter` + `repaint: Listenable`（**首选**）—— 官方原文："the `CustomPaint` widget or `RenderCustomPaint` render object will listen to the `Listenable` and repaint whenever the animation ticks, **avoiding both the build and layout phases** of the pipeline."（[CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)）；`repaint` 只触发 `paint()`，painter 实例在 `build()` 时才新建，逐帧数据要在 `paint()` 内从 controller 读取。② `AnimatedBuilder` / `ListenableBuilder` 会重建 builder 子树，静态子树须经 `child:` 传入 —"Using this pre-built child … can improve performance significantly"（[AnimatedBuilder](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html)、[性能最佳实践](https://docs.flutter.dev/perf/best-practices)）。③ `ValueListenableBuilder` 是重建语义；`setState` 最差（连带 layout 与父级 intrinsic 传递）。

**帧预算**：60 Hz ⇒ 16.67 ms，120 Hz ⇒ 8.33 ms。官方："As 120fps devices become more widely available, you'll want to render frames in under 8ms (total)"（[性能最佳实践](https://docs.flutter.dev/perf/best-practices)）。用 `SchedulerBinding.instance.addTimingsCallback` 采集 `FrameTiming.buildDuration`/`rasterDuration` 真机验证（[addTimingsCallback](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)）。本效果每帧 = 1 次文本裁剪绘制（+ 可选辉光）+ ≤60 次 `drawParagraph`；**唯一风险点是模糊辉光**（§4.4）。

---

## 2. 消除布局抖动（核心）

**为什么"把随机字拼进字符串"必然抖动**：① 汉字≈1em 全角，`A`/`#`/`—` 宽窄各异 ⇒ 同行重排；② CJK 可在任意两个表意文字间断行，拉丁只按空格/连字符断 ⇒ 把汉字换成 `$#@&*%?±!` 后**可行断行点集合完全改变**；③ 行数一变，父级 `Center`/`Column` 重排，整页跳动；④ 每帧新建 `InlineSpan` ⇒ `RenderParagraph` 每帧完整整形 + 断行。

⇒ **任何"替换字符再交给文本引擎排版"的方案（字符串拼接 / 逐字 `TextSpan` / `Text.rich`）都无法保证零抖动。** `kinetic_text` 包也承认这点：其 `Scramble` "sets its stand-in glyphs one at a time, so **keep it to Latin text and figures**"（[kinetic_text](https://pub.dev/packages/kinetic_text)）——它刻意不支持 CJK。

| 方案 | 零抖动 | CJK | 断行正确 | 每帧成本 | 结论 |
|---|---|---|---|---|---|
| (a) 乱码段用等宽字体 | ❌ | ❌ | ❌ | 低 | 汉字没有真正的等宽拉丁替身 |
| (b) `TextPainter` 量宽 + padding | ❌ | 部分 | ❌ | 中 | 只能撑到最坏宽度，**内部**仍重排、行数仍变 |
| (c) `CustomPainter` 手工定位 | ✅ | ✅ | ⚠️ 自己实现 | 低 | 等于重造 SkParagraph 断行 |
| (d) 逐字 `WidgetSpan`/`Stack` 定宽盒 | ✅ | ✅ | ❌ | **高** | 每字一个 RenderObject；丢失 shaping/kerning/中文标点避头尾 |
| **(e) 预留最终布局 + 只换蒙版** | ✅ | ✅ | ✅ | **低** | **推荐** |

**方案 (e) 原理**：① 用**最终文案**建一个 `TextPainter`，按真实约束 `layout(maxWidth: …)`，由此决定断行、每行内容、每字位置、整体 `Size`；② `CustomPaint.size = textPainter.size` ⇒ **控件尺寸在动画全程恒定**，父级永不重排；③ 每帧只做两件事 —— **已揭示前缀**把最终文本裁剪到 `[0, cursor)` 覆盖区域后 `paint` 一次（原字形、原位置，零误差），**未揭示字符**从缓存取随机字形 `ui.Paragraph` 居中画进**最终布局的格子**（落笔位置与随机字形宽度无关 ⇒ 零抖动）。

```dart
// 每字盒子（惰性缓存一次）
final List<ui.TextBox> boxes = textPainter.getBoxesForSelection(
  TextSelection(baseOffset: i, extentOffset: i + 1));
// 已揭示前缀（连续区域，一次调用拿到每行一段）
final List<ui.TextBox> revealed = textPainter.getBoxesForSelection(
  TextSelection(baseOffset: 0, extentOffset: cursor),
  boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle); // 更高的盒子，辉光不被裁
```

`getBoxesForSelection` 返回"bound the given selection"的矩形列表，双向文本可能返回多于一段；**返回坐标已叠加 `paintOffset`，因此 `TextAlign.center` 的对齐偏移已经算进去了**（[getBoxesForSelection](https://api.flutter.dev/flutter/painting/TextPainter/getBoxesForSelection.html)）。`cursor` 必须按 **UTF-16 code unit** 计（Dart `String.length` 即 code unit 数），与 `text[i]`、`TextSelection` 偏移天然一致；中文属 BMP 无代理对，含 emoji 时先用 `characters` 包切分再映射回 code unit 偏移。

**前缀裁剪两种实现**：① `coverColor != null`（本项目纯黑背景，最便宜）— 对每个未揭示字符 `canvas.drawRect(box, Paint()..color = coverColor)` 盖住再画随机字形，零接缝零 clip；② `coverColor == null`（渐变/图片/透明背景）— `canvas.save(); canvas.clipPath(并集); tp.paint(canvas, Offset.zero); canvas.restore();`，每个 rect 先 `inflate(0.5 + glowPadding)` 再 `Path.addRect`（`PathFillType.nonZero`），半像素外扩消除抗锯齿细缝。

| 中文断行参数 | 取值与理由 |
|---|---|
| `locale` | `Localizations.maybeLocaleOf(context)`（`zh_CN`）：SkParagraph 依赖 locale 选断行/禁则规则 |
| `textWidthBasis` | `TextWidthBasis.parent`：有界宽下按父约束换行；`longestLine` 会改变 `size.width` 语义（[TextWidthBasis](https://api.flutter.dev/flutter/painting/TextWidthBasis.html)） |
| `textAlign` / `strutStyle` | `TextAlign.center`（与 JS 一致，对齐偏移已体现在 box 坐标）；`StrutStyle(forceStrutHeight: true)` 锁死中英混排行高 |
| `textScaler` / 宽度 | `MediaQuery.textScalerOf(context)` 必须透传；`LayoutBuilder` → `layout(maxWidth: c.maxWidth)`，宽度变化才重建 |

> `TextPainter` **必须 `dispose()`**（持有原生 Paragraph 资源）："Call dispose when the object will no longer be accessed to release native resources."（[TextPainter](https://api.flutter.dev/flutter/painting/TextPainter-class.html)）

---

## 3. 逐字显示组件的渲染路径

**不用 `RichText`/`Text.rich` 逐字 `TextSpan`**：每个字符一个 span 会让 run 边界落在任意字符间，可能禁用跨 run 的 kerning/连字；内容每帧变化 ⇒ `RenderParagraph` 每帧重新整形 + 断行，`TextSpan` 树每帧新建还带来 GC 压力；**最致命的是 §2 的断行漂移**。

**随机字形缓存**（别每帧给每格 `TextPainter.layout()` —— 60 字 × 60 fps = 3600 次排版/秒）：

```dart
Map<String, ui.Paragraph> buildGlyphCache(TextStyle style, TextScaler scaler) {
  final ui.ParagraphStyle ps = style.getParagraphStyle(
      textAlign: TextAlign.left, textDirection: TextDirection.ltr);
  final ui.TextStyle ts = style.getTextStyle(textScaler: scaler);
  return <String, ui.Paragraph>{
    for (final String ch in glyphChars)
      ch: (ui.ParagraphBuilder(ps)..pushStyle(ts)..addText(ch)).build()
        ..layout(const ui.ParagraphConstraints(width: 200)),
  };
}
```

`TextStyle.getTextStyle({TextScaler})` / `getParagraphStyle({...})` 均在 3.47.5 存在（`packages/flutter/lib/src/painting/text_style.dart:1333 / 1388`）。运行时每格只需 `canvas.drawParagraph(para, box.center - Offset(para.width / 2, para.height / 2))`（[Canvas.drawParagraph](https://api.flutter.dev/flutter/dart-ui/Canvas/drawParagraph.html)）。

> 极致优化：把乱码表预渲染成一张 `ui.Image` 图集（`PictureRecorder` + `Picture.toImageSync`），用 `Canvas.drawAtlas` 一次提交全部字形（[drawAtlas](https://api.flutter.dev/flutter/dart-ui/Canvas/drawAtlas.html)）。120 Hz/低端机兜底方案，先不要上。

**组件骨架**：`LayoutBuilder(constraints)` →（宽度变化时）重建 `TextPainter(最终文案).layout(maxWidth)` → `CustomPaint(size: tp.size, painter: _ScramblePainter(repaint: controller))`，外包 `RepaintBoundary`，最外 `ExcludeSemantics` + `Semantics(label: 最终文案)`。`RepaintBoundary` 把重绘限制在本子树内（[RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)），对**静态**最终态还能让引擎缓存栅格化结果。

---

## 4. 霓虹辉光

### 4.1 CSS → Flutter 直接映射

CSS `text-shadow: 0 0 5px #fff, 0 0 10px #00d2ff, 0 0 15px #00d2ff;` ⇒ `style.copyWith(shadows: kCssGlow)`：

```dart
const List<Shadow> kCssGlow = <Shadow>[
  Shadow(color: Color(0xFFFFFFFF), blurRadius: 5),   // #fff
  Shadow(color: Color(0xFF00D2FF), blurRadius: 10),  // #00d2ff
  Shadow(color: Color(0xFF00D2FF), blurRadius: 15),  // #00d2ff
];
```

`TextStyle.shadows`："A list of Shadows that will be painted **underneath** the text … **Shadows must be in the same order** for TextStyle to be considered as equivalent as order produces differing transparency."（[TextStyle.shadows](https://api.flutter.dev/flutter/painting/TextStyle/shadows.html)）

### 4.2 `blurRadius` 与 CSS **不等价**

`Shadow.blurRadius` 的文档字符串写的是 "The standard deviation of the Gaussian"，但 `sky_engine/lib/ui/painting.dart` 的实现并非如此：

```dart
static double convertRadiusToSigma(double r) => r > 0 ? r * 0.57735 + 0.5 : 0; // SkBlurMask
double get blurSigma => convertRadiusToSigma(blurRadius);
// Shadow.toPaint():  ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma)
```

（[Shadow.convertRadiusToSigma](https://api.flutter.dev/flutter/dart-ui/Shadow/convertRadiusToSigma.html)）。而 CSS Backgrounds 3 §6.1.2 规定阴影用"标准差等于模糊半径一半"的高斯（[css-backgrounds-3 #shadow-blur](https://www.w3.org/TR/css-backgrounds-3/#shadow-blur)）：CSS `σ = R/2`（R=10 ⇒ σ=5），Flutter/Skia `σ = 0.57735·R + 0.5`（R=10 ⇒ σ=6.27）。⇒ **同数值下 Flutter 比 CSS 更糊约 25%**；想对齐 CSS 的 `10px` 取 `blurRadius ≈ 7.8`：

```dart
/// CSS text-shadow blur-radius(px) → 视觉等价的 Flutter blurRadius
double cssBlurToFlutter(double px) => px <= 0 ? 0 : ((px / 2) - 0.5) / 0.57735;
```

### 4.3 增强/替代手段

| 手段 | 说明 | 成本 |
|---|---|---|
| `Shadow(blurRadius:)` × N | 语义最贴 CSS | 每个 shadow = 一次模糊绘制 |
| `MaskFilter.blur(BlurStyle.normal, sigma)` 配 `Paint` | `drawParagraph` 自绘时的等价物；sigma 即高斯标准差（[MaskFilter.blur](https://api.flutter.dev/flutter/dart-ui/MaskFilter/MaskFilter.blur.html)）。官方警告 "A blur is an expensive operation and should therefore be used sparingly." | 同上 |
| `ImageFiltered` / `BackdropFilter` | 整体 bloom/外发光（[ImageFiltered](https://api.flutter.dev/flutter/widgets/ImageFiltered-class.html)） | 触发 `saveLayer` |
| `ShaderMask` / `ColorFiltered` | 扫光上色 / RGB split 调色（[ColorFiltered](https://api.flutter.dev/flutter/widgets/ColorFiltered-class.html)） | `ShaderMask` **官方点名会触发 `saveLayer`**（[性能最佳实践](https://docs.flutter.dev/perf/best-practices)） |
| **预烘焙 `ui.Image`** | `PictureRecorder` 画一次"文案+辉光" → `Picture.toImageSync()`，之后每帧只 `drawImage` | ✅ **零模糊开销**，适合最终静态态 |
| `FragmentProgram` | 自定义 GLSL 做辉光/RGB split（[FragmentProgram](https://api.flutter.dev/flutter/dart-ui/FragmentProgram-class.html)、[官方教程](https://docs.flutter.dev/ui/design/graphics/fragment-shaders)） | 高；Skia 下建议 "precache the fragment program objects before starting the animation" |

### 4.4 性能陷阱（必读）

带模糊的文本阴影在 **Impeller** 上会掉进通用高斯通道（downsample + 横模糊 + 竖模糊）：

- **[flutter#190395](https://github.com/flutter/flutter/issues/190395)**（Windows + Impeller/GLESDF，2026-08）：`TextStyle.shadows` 仅 `blurRadius: 1`，滚动场景 **raster p50 从 3.609 ms 涨到 98.236 ms（≈27×），FPS 59.5 → 10.25**；同负载 Skia 仅 2.298 ms。引擎作者确认根因："the blur of the text is falling down the generic gaussian blur path which is multiple render passes (down sample, blur vertical, blur horizontal). **One of those frames has 85 render passes.**"
- 该 issue 由 PR #190681 缓解：3.48.0-1.0.pre-237 上 blur-1 的 raster p50 降到 5.0 ms，**仍高于 Skia，且 3.47.x 稳定分支未包含该修复**。
- **[flutter#165116](https://github.com/flutter/flutter/issues/165116)**（Android + Impeller，`blurRadius: 8`）同样报告滚动性能下降。
- Impeller 已有 `TextShadowCache`，但**多字形**的缓存键用 `TextFrame` 对象地址；逐帧改文字会让 `TextFrame` 每帧重建 ⇒ **缓存全部失效**，正好命中"每帧换字形"这类负载。

**对策**：① 动画期间只用 1 层小模糊 `Shadow`；② 结束后切完整 3 层辉光并包 `RepaintBoundary`（静态子树不会每帧重画模糊）；③ 乱码字形不带模糊阴影，辉光只作用在已揭示前缀上；④ 若 Windows/Impeller 实测仍慢，用 `flutter run -d windows --profile --no-enable-impeller` 对比并考虑降为 2 层；⑤ 上线前在 60/120 Hz 设备各测一遍。

### 4.5 Web（CanvasKit / skwasm）

| 事实 | 影响 |
|---|---|
| CanvasKit 走 `dart2js`，skwasm 走 `dart2wasm`；`--wasm` 构建产出两条管线，Chromium 优先 skwasm，其余回退 CanvasKit（[CanvasKit vs skwasm 2026](https://startdebugging.net/2026/09/canvaskit-vs-skwasm-for-flutter-web-in-2026/)） | 同 benchmark 中"每帧改文本的 `Text`"重负载场景：CanvasKit 24.0 fps vs 单线程 skwasm 32.7 fps；dart2wasm 让 build 阶段快约 2×，正是本效果受益点 |
| **3.47.x 多线程 skwasm 在文本频繁变化时崩溃**（跨线程 `SkStrikeCache` 竞争，[#190039](https://github.com/flutter/flutter/issues/190039)；修复 [PR #190048](https://github.com/flutter/flutter/pull/190048) 只在 3.48） | `web/flutter_bootstrap.js` 加 `forceSingleThreadedSkwasm: true` |
| CanvasKit 早已从 `drawParagraph` 迁到 `drawGlyphs`（[#81224](https://github.com/flutter/flutter/issues/81224)） | 文本绘制本身不贵；要防的是"每帧新建/销毁 Paragraph"，故 §3 字形缓存同样适用于 Web |

```js
// web/flutter_bootstrap.js —— 3.47.x 规避 #190039
_flutter.loader.load({
  config: { forceSingleThreadedSkwasm: true, suppressMultithreadingWarning: true },
});
```
参考：[Customize app initialization](https://docs.flutter.dev/platform-integration/web/initialization)、[Wasm 支持](https://docs.flutter.dev/platform-integration/web/wasm)。

---

## 5. 确定性与可测试性

- **注入** `math.Random? random`（[Random(seed)](https://api.dart.dev/stable/dart-math/Random/Random.html)）。官方警告："**The implementation of the random stream can change between releases of the library.**" ⇒ 跨 SDK 版本别指望同 seed 得同串字形，**不要**用它做 golden 断言。
- **推荐：纯函数字形选择**（无状态、可精确断言、零分配）——"第 f 帧第 i 个字显示哪个字形"完全确定，golden 与截图回归都成立：
  ```dart
  int defaultGlyphIndex(int seed, int frame, int charIndex, int glyphCount) {
    int h = seed ^ 0x9E3779B9;
    h = 0x1B873593 * (h ^ charIndex);
    h = 0x85EBCA6B * (h ^ frame);
    h ^= h >>> 15;
    return h.abs() % glyphCount;
  }
  ```

```dart
testWidgets('最终帧等于目标文案 + 全程零抖动', (WidgetTester tester) async {
  const String target = '食指指令生成器：点击开始。';
  await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: ScrambleText(target)))));
  final ScrambleTextState s = tester.state(find.byType(ScrambleText));

  await tester.pump(const Duration(milliseconds: 100));
  expect(target.startsWith(s.debugRenderedText), isTrue);    // 已揭示部分必是原文前缀
  final Size before = tester.getSize(find.byType(ScrambleText));
  await tester.pump(const Duration(milliseconds: 50));
  expect(tester.getSize(find.byType(ScrambleText)), before);  // 中途尺寸不变

  await tester.pump(s.debugTotalDuration);                    // 推到结束
  await tester.pump(const Duration(milliseconds: 16));        // 收尾帧
  expect(s.debugRenderedText, target);                        // 最终帧逐字等于原文
  expect(tester.getSize(find.byType(ScrambleText)), before);   // 结束尺寸不变
});
```

- `tester.pump(Duration)`："Triggers a frame after `duration` amount of time. This makes the framework act as if the application had janked (missed frames)"（[pump](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pump.html)）。
- 需要逐帧看时用 `tester.pumpFrames(widget, maxDuration, interval)`；默认 interval = **16.683 ms（59.94 fps）**，120 Hz 场景显式传 `Duration(microseconds: 8333)`（[pumpFrames](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpFrames.html)）。
- **`pumpAndSettle` 陷阱**：它反复 pump 直到没有待处理帧；文档原文："if there is an **infinite animation** in progress … this method **will throw**"，默认 10 分钟超时（[pumpAndSettle](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html)）。本组件是**有限**动画，`pumpAndSettle` 可用；但一旦加了 `AnimationController.repeat()` 的呼吸/闪烁循环，`hasScheduledFrame` 永为真 ⇒ 必然超时。此时改用 `pump(固定时长)`，或给循环动画加 `enabled` 开关。

---

## 6. 减弱动效（Reduce Motion）

| 平台 | 设置项 | 反映到 |
|---|---|---|
| Android | 无障碍 "Remove animations" | `AccessibilityFeatures.disableAnimations` ⇒ `MediaQueryData.disableAnimations` |
| iOS / macOS | 辅助功能 "减弱动态效果" | **`AccessibilityFeatures.reduceMotion`**（**不**设置 `disableAnimations`） |
| Web | `@media (prefers-reduced-motion: reduce)` | 引擎**同时置两个位** |

- `MediaQueryData.disableAnimations` 文档明确："On iOS, reduced motion is exposed separately via `dart:ui.AccessibilityFeatures.reduceMotion` and **does not set this flag**."（[MediaQueryData.disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html)）
- 引擎 Web 实现："The web doesn't seem to distinguish between 'reduced motion' and 'disable animations', so we set both at the same time in this update."（`engine/src/flutter/lib/web_ui/lib/src/engine/platform_dispatcher.dart:1284-1303`，由 `media_query_manager.dart` 的 `(prefers-reduced-motion: reduce)` 驱动）
- `MediaQueryData.fromView` 只读 `accessibilityFeatures.disableAnimations`（`packages/flutter/lib/src/widgets/media_query.dart:321`），**不读 `reduceMotion`**。
- **`MediaQuery.reduceMotionOf` 在 3.47.5 中不存在**（该文件仅 8 个 `…Of` 布尔取值方法，`reduceMotion` 只出现在一处注释）；相关提案见 [PR #190287](https://github.com/flutter/flutter/pull/190287)。

```dart
/// 当前平台是否要求减弱动效（Android + iOS + Web 全覆盖）。
bool reduceMotionEnabled(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;
```

- 优先 `MediaQuery.disableAnimationsOf(context)` 而非 `MediaQuery.of(context).disableAnimations`：前者只在**该属性**变化时重建（[disableAnimationsOf](https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html)）。`disableAnimations` 变化会经 `WidgetsBindingObserver.didChangeAccessibilityFeatures` 自动重建 `MediaQuery`（`media_query.dart:2398`）；读 `PlatformDispatcher` 那一路不会自动重建，运行时热切换需 `addObserver`。
- **不要**依赖 `AnimationController` 的自动降级：`AnimationBehavior.normal` 只把时长压到约 1/20 并减少帧数，"极速闪一下乱码"比直接显示更糟（[AnimationBehavior](https://api.flutter.dev/flutter/animation/AnimationBehavior.html)）。应在 `initState`/`didChangeDependencies` 里判定并**根本不启动动画**。
- 回退策略：`instant`（推荐默认）直接渲染最终文案 + 完整辉光，信息完整零闪烁；`fade` 150–200 ms 交叉淡入，保留"出现"的仪式感但无乱码闪；`none` 仅 App 内显式开关时用。

---

## 7. 无障碍（读屏必须读到最终句子）

乱码字形对读屏是噪音。做法：**动画层对外完全静音，用一个干净的语义节点播报最终文案。**

```dart
Semantics(
  container: true,
  label: widget.semanticsLabel ?? widget.text,   // 始终是最终句子
  liveRegion: false,                              // 需要播报出现时置 true
  child: ExcludeSemantics(                        // 丢掉子树所有语义
    child: RepaintBoundary(child: CustomPaint(painter: _painter, size: _layout!.size)),
  ),
)
```

`ExcludeSemantics`："A widget that drops all the semantics of its descendants."（[ExcludeSemantics](https://api.flutter.dev/flutter/widgets/ExcludeSemantics-class.html)）；`Semantics(label:)` 注入正确文本（[Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html)）。本方案用 `CustomPaint`（非 `Text`），**默认根本不产生文本语义**，`ExcludeSemantics` 是双保险；若改回 `Text`/`RichText` 渲染它就是必需层。动画结束后可 `SemanticsService.announce(finalText, textDirection)` 播报一次，先查 `MediaQuery.supportsAnnounceOf(context)`（[supportsAnnounce](https://api.flutter.dev/flutter/widgets/MediaQueryData/supportsAnnounce.html)）。对比度：`#00d2ff` 在纯黑上远高于 WCAG 小字 4.5:1 要求（[UI 设计与样式](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling)）；但 `blurRadius` 过大会让笔画变淡，需目视确认。

---

## 8. 可选增强效果（成本 / 收益）

| 效果 | 实现要点 | 成本 | 收益 |
|---|---|---|---|
| **打字机** | 本方案天然支持：`cursor = floor(t)`，跳过随机字形分支 | ≈0 | 可读性最好，长句首选 |
| **逐字淡入** | 别用每字一个 `AnimatedOpacity`（60 字 = 60 个 RenderObject）；在 painter 内按 box 画 alpha 渐变裁剪 | 中 | 高级感强，建议 ≤20 字标题 |
| **RGB split / glitch** | 同文本经 `ColorFiltered(ColorFilter.mode(0xFFFF0000, BlendMode.modulate))` 出红/青两层，各偏移 1–2 px 叠 `Stack` | 中（2 次离屏合成） | 赛博朋克感最强，**只在关键帧短暂开启** |
| **`FragmentProgram` glitch** | `.frag` 内按 `FlutterFragCoord` 做块位移 + 色差；`pubspec.yaml` 声明 `shaders:` | 高（资源 + 加载 + 调试） | 上限最高，建议 v2 |
| **Glow 呼吸循环** | `repeat(reverse: true)` 调制 blur/alpha；**`pumpAndSettle` 会超时**，且每帧重算模糊（§4.4） | 高 | 建议改为两张预烘焙 `ui.Image` 间交叉淡入 |

优先级：`typewriter`（作为 `reveal` 枚举一项，成本≈0）> `RGB split`（关键帧）> 呼吸辉光（预烘焙交叉淡入）> 自定义 shader。

---

## 9. 本项目的推荐实现

**设计要点**：① 布局只算一次（最终文案的 `TextPainter`，尺寸即组件尺寸 ⇒ 结构性零抖动）；② 绘制两段（已揭示前缀 = 裁剪后的最终文本；未揭示 = 缓存字形居中绘制）；③ 驱动用 `CustomPainter(repaint: controller)`，跳过 build/layout；④ 辉光分级（动画中 1 层小模糊，结束后 3 层完整）；⑤ 减弱动效独立分支，不启动动画；⑥ **零新依赖**（当前 `pubspec.yaml` 仅 `cupertino_icons` + `flutter_lints ^6.0.0`）。

文件布局：`lib/theme/neon_glow.dart`、`lib/utils/reduce_motion.dart`、`lib/widgets/scramble_text.dart`、`test/scramble_text_test.dart`。导入：`dart:math as math`、`dart:ui as ui`、`package:flutter/material.dart`。

### 9.1 构造参数（`ScrambleText`，字段同名一一对应，`final` 声明省略）

| 参数 | 默认值 | 说明 |
|---|---|---|
| `text`（位置参数） | — | 目标文案（中文）。空串直接渲染 `SizedBox.shrink()` |
| `style` / `textAlign` | `null` / `TextAlign.center` | 与 `DefaultTextStyle` merge；对齐影响 box 坐标 |
| `textWidthBasis` / `strutStyle` | `TextWidthBasis.parent` / `null` | 断行与行高控制（§2） |
| `scrambleChars` | `kDefaultScrambleChars` | 与原 JS 同表（含 `$#@&*%?±!<>-_\/[]{}—=+^`） |
| `framesPerStep` | `5` | 原 JS `stepSpeed`：每 N 帧推进一步 |
| `charsPerStepLong` / `charsPerStepShort` / `longTextThreshold` | `1.0` / `0.6` / `20` | 原 JS 三目分支，改成参数化 |
| `frameBudget` | `Duration(microseconds: 16683)` | 单帧时间预算（59.94 fps），把帧数折成 `duration` |
| `reveal` | `ScrambleReveal.scramble` | `scramble` / `typewriter` / `instant` |
| `glow` / `glowEnabled` | `NeonGlow.neonBlue` / `true` | 霓虹辉光分层配置（§4） |
| `glyphSelector` / `seed` | `null` / `0x5EED` | `(frame, charIndex) -> 字形下标`；注入即完全确定性（§5） |
| `reduceMotionMode` | `ScrambleReveal.instant` | 减弱动效时的回退模式（§6） |
| `semanticsLabel` / `onCompleted` | `null` / `null` | 读屏播报文本（默认取 `text`）；结束回调（§7） |

### 9.2 核心 tick + build + paint 逻辑

下列代码省略了 `NeonGlow` 完整定义（即 §4.1 的三层 `Shadow` + `animatedLayerCount` 开关、`cssBlurToFlutter` 换算）、字形缓存构建（§3）、`initState`/`dispose`/`boxesFor` 等样板。

```dart
class ScrambleTextState extends State<ScrambleText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<String> _glyphChars;                 // 乱码表去重
  final Map<String, ui.Paragraph> _glyphCache = {};    // §3 预烘焙
  TextPainter? _layout;                                // 最终文案布局 —— 唯一真源
  (TextStyle, TextScaler, double)? _layoutKey;         // 变化才重排
  List<ui.TextBox>? _charBoxes;                        // 每字盒子，懒算一次
  int _totalFrames = 1;
  bool animating = true;

  // initState: _glyphChars = scrambleChars.split('').toSet().toList();
  //            _controller = AnimationController(vsync: this, duration: widget.frameBudget)
  //              ..addStatusListener((s) { if (s == AnimationStatus.completed && mounted) {
  //                    setState(() => animating = false);      // 切完整辉光 + 允许栅格缓存
  //                    widget.onCompleted?.call(); } });

  @override
  void didChangeDependencies() { super.didChangeDependencies(); _restart(); }

  /// §6：Android/Web 看 disableAnimations，iOS/macOS 另看 reduceMotion。
  bool get _reducedMotion =>
      MediaQuery.disableAnimationsOf(context) ||
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;

  void _restart() {
    final int n = widget.text.length;
    final double step =
        n > widget.longTextThreshold ? widget.charsPerStepLong : widget.charsPerStepShort;
    _totalFrames = n == 0 ? 1 : ((n / step).ceil() * widget.framesPerStep).clamp(1, 1 << 20);
    _controller.stop();
    _controller.duration = widget.frameBudget * _totalFrames;   // 帧率无关（§1）
    if (_reducedMotion && widget.reduceMotionMode == ScrambleReveal.instant) {
      _controller.value = 1.0;                                  // 直接呈现最终态
      animating = false;
    } else {
      animating = true;
      _controller.forward(from: 0);
    }
  }

  /// 当前游标（UTF-16 code unit）；debug* 只读属性仅供测试断言（§5）。
  int get debugCursor {
    if (!animating || widget.reveal == ScrambleReveal.instant) return widget.text.length;
    final int n = widget.text.length;
    final double step =
        n > widget.longTextThreshold ? widget.charsPerStepLong : widget.charsPerStepShort;
    return (((_controller.value * _totalFrames).floor() ~/ widget.framesPerStep) * step)
        .clamp(0, n).toInt();
  }
  @visibleForTesting int get debugFrame => (_controller.value * _totalFrames).floor();
  @visibleForTesting Duration get debugTotalDuration => widget.frameBudget * _totalFrames;
  @visibleForTesting String get debugRenderedText =>
      debugCursor >= widget.text.length ? widget.text : widget.text.substring(0, debugCursor);

  /// 先排「最终文案」——尺寸由此决定，故动画全程恒定（§2 方案 e）。
  void _ensureLayout(TextStyle style, TextScaler scaler, double maxWidth) {
    final (TextStyle, TextScaler, double) key = (style, scaler, maxWidth);
    if (_layout != null && _layoutKey == key) return;
    _layout?.dispose();
    _layoutKey = key;
    _charBoxes = null;                                       // 布局变了，盒子失效
    _layout = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textAlign: widget.textAlign,
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),           // 中文断行/禁则
      strutStyle: widget.strutStyle,
      textWidthBasis: widget.textWidthBasis,
    )..layout(maxWidth: maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = DefaultTextStyle.of(context).style.merge(widget.style).copyWith(
        shadows: widget.glowEnabled ? widget.glow.shadows(animating: animating) : null);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      _ensureLayout(style, scaler, c.maxWidth);
      final TextPainter tp = _layout!;
      return Semantics(                                      // §7 读屏只读最终句子
        container: true,
        label: widget.semanticsLabel ?? widget.text,
        child: ExcludeSemantics(
          child: RepaintBoundary(                            // 重绘限制在本子树
            child: CustomPaint(
              size: tp.size,                                 // ← 恒定，父级永不重排
              painter: _ScramblePainter(
                state: this, layout: tp, text: widget.text, reveal: widget.reveal,
                chars: _glyphChars, glyphs: _glyphCache,
                glyphSelector: widget.glyphSelector, seed: widget.seed,
                glowPadding: !widget.glowEnabled ? 0
                    : widget.glow.shadows(animating: animating)
                        .fold<double>(0, (m, s) => math.max(m, s.blurRadius)) + 2,
                repaint: _controller,                        // ← 逐帧重绘，不走 build/layout
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 以下省略 final 字段声明：state/layout/text/reveal/chars/glyphs/
/// glyphSelector/seed/glowPadding 均与构造参数同名一一对应。
class _ScramblePainter extends CustomPainter {
  _ScramblePainter({required this.state, required this.layout, required this.text,
    required this.reveal, required this.chars, required this.glyphs,
    required this.glyphSelector, required this.seed, required this.glowPadding,
    required Listenable repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final int cursor = state.debugCursor;                    // ← 每帧从 controller 读
    final int frame = state.debugFrame;

    // ① 已揭示前缀：裁剪到 [0, cursor) 覆盖区域，按最终布局原样绘制一次
    if (cursor > 0) {
      final Path clip = Path()..fillType = PathFillType.nonZero;
      for (final ui.TextBox b in layout.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: cursor),
        boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
      )) {
        clip.addRect(b.toRect().inflate(0.5 + glowPadding)); // 外扩：保住辉光、消细缝
      }
      canvas.save();
      canvas.clipPath(clip);
      layout.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // ② 未揭示字符：在「最终布局的格子」里居中画随机字形（与字宽无关 ⇒ 零抖动）
    if (reveal != ScrambleReveal.scramble || cursor >= text.length) return;
    final List<ui.TextBox> boxes = state.boxesFor(layout);
    for (int i = cursor; i < text.length; i++) {
      final Rect box = boxes[i].toRect();
      if (box.right <= box.left) continue;                             // 换行符等
      final String ch = chars[(glyphSelector ?? _glyphIndex)(frame, i).abs() % chars.length];
      final ui.Paragraph para = glyphs[ch]!;
      canvas.drawParagraph(para, box.center - Offset(para.width / 2, para.height / 2));
    }
  }

  /// 纯函数字形选择：同 (frame, index) 恒得同一字形 ⇒ golden 可断言（§5）。
  int _glyphIndex(int frame, int charIndex) {
    int h = seed ^ 0x9E3779B9;
    h = 0x1B873593 * (h ^ charIndex);
    h = 0x85EBCA6B * (h ^ (frame * 0x85EBCA6B));
    h ^= h >>> 15;
    return h;
  }

  // painter 实例只在 rebuild 时替换；逐帧重绘由 repaint: controller 驱动。
  @override
  bool shouldRepaint(_ScramblePainter old) =>
      old.text != text || old.layout != layout || old.reveal != reveal;
}
```

实现备注：① `boxesFor(tp)` 逐字调 `getBoxesForSelection(TextSelection(i, i+1))` 并缓存，换行等零宽字符回退为零宽矩形（不参与绘制）以免下标错位；② `_glyphCache` 在 `style`/`textScaler` 变化时清空重填，每个 `ui.Paragraph` 在 `dispose()` 释放；③ 背景为不透明纯色时，在 ② 之前补 `canvas.drawRect(box.inflate(1), Paint()..color = coverColor)` 盖住未揭示字符，即可**完全省掉 ① 的 clipPath**（更快、无接缝）；④ 做 `typewriter` 时 `cursor` 逻辑相同，跳过 ② 即可；⑤ 需要**中途重播**时在 `didUpdateWidget` 比对 `text` 并调用 `_restart()`。

### 9.3 验收清单

- [ ] 15/30/60 字，纯中文 / 中英混排 / 含中英标点，**动画全程 `tester.getSize()` 不变**
- [ ] 最终帧 `debugRenderedText == widget.text`（含标点，逐字相等）
- [ ] 120 Hz 下总时长与 60 Hz 一致（帧率无关）
- [ ] `disableAnimations = true` 与 `reduceMotion = true` 两种测试环境下都直接呈现最终态
- [ ] 语义树中只有一条 label = 最终文案，无乱码字符
- [ ] Windows/Impeller 与 Android/Impeller 上 `rasterDuration` p95 < 8 ms(120 Hz) / 16 ms(60 Hz)
- [ ] Web：`flutter build web --wasm` + `forceSingleThreadedSkwasm: true`，长时间运行不崩（规避 [#190039](https://github.com/flutter/flutter/issues/190039)）

---

## 10. 主要参考

**Flutter API**：[AnimationController](https://api.flutter.dev/flutter/animation/AnimationController-class.html) · [AnimationBehavior](https://api.flutter.dev/flutter/animation/AnimationBehavior.html) · [Ticker](https://api.flutter.dev/flutter/scheduler/Ticker-class.html) · [addTimingsCallback](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html) · [CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) · [RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html) · [AnimatedBuilder](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html) · [TextPainter](https://api.flutter.dev/flutter/painting/TextPainter-class.html) · [getBoxesForSelection](https://api.flutter.dev/flutter/painting/TextPainter/getBoxesForSelection.html) · [getOffsetForCaret](https://api.flutter.dev/flutter/painting/TextPainter/getOffsetForCaret.html) · [computeLineMetrics](https://api.flutter.dev/flutter/painting/TextPainter/computeLineMetrics.html) · [TextWidthBasis](https://api.flutter.dev/flutter/painting/TextWidthBasis.html) · [Shadow](https://api.flutter.dev/flutter/dart-ui/Shadow-class.html) · [convertRadiusToSigma](https://api.flutter.dev/flutter/dart-ui/Shadow/convertRadiusToSigma.html) · [TextStyle.shadows](https://api.flutter.dev/flutter/painting/TextStyle/shadows.html) · [MaskFilter.blur](https://api.flutter.dev/flutter/dart-ui/MaskFilter/MaskFilter.blur.html) · [Canvas.drawParagraph](https://api.flutter.dev/flutter/dart-ui/Canvas/drawParagraph.html) · [Canvas.drawAtlas](https://api.flutter.dev/flutter/dart-ui/Canvas/drawAtlas.html) · [ImageFiltered](https://api.flutter.dev/flutter/widgets/ImageFiltered-class.html) · [ColorFiltered](https://api.flutter.dev/flutter/widgets/ColorFiltered-class.html) · [ShaderMask](https://api.flutter.dev/flutter/widgets/ShaderMask-class.html) · [FragmentProgram](https://api.flutter.dev/flutter/dart-ui/FragmentProgram-class.html) · [MediaQuery.disableAnimationsOf](https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html) · [MediaQueryData.disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html) · [AccessibilityFeatures.disableAnimations](https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures/disableAnimations.html) · [AccessibilityFeatures.reduceMotion](https://api.flutter.dev/flutter/dart-ui/AccessibilityFeatures/reduceMotion.html) · [Semantics](https://api.flutter.dev/flutter/widgets/Semantics-class.html) · [ExcludeSemantics](https://api.flutter.dev/flutter/widgets/ExcludeSemantics-class.html) · [supportsAnnounce](https://api.flutter.dev/flutter/widgets/MediaQueryData/supportsAnnounce.html) · [WidgetTester.pump](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pump.html) · [pumpFrames](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpFrames.html) · [pumpAndSettle](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html) · [Random(seed)](https://api.dart.dev/stable/dart-math/Random/Random.html)

**Flutter 文档**：[Performance best practices](https://docs.flutter.dev/perf/best-practices) · [Debug performance for web apps](https://docs.flutter.dev/perf/web-performance) · [Writing and using fragment shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders) · [UI design & styling（无障碍）](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling) · [Customize app initialization](https://docs.flutter.dev/platform-integration/web/initialization) · [WebAssembly (Wasm)](https://docs.flutter.dev/platform-integration/web/wasm)

**Issues / PR**：[#190395 文本阴影非零 blur 在 Windows/Impeller 上严重变慢](https://github.com/flutter/flutter/issues/190395) · [#165116 Impeller 文本阴影性能下降](https://github.com/flutter/flutter/issues/165116) · [#81224 CanvasKit 改用 drawGlyphs](https://github.com/flutter/flutter/issues/81224) · [#190039 多线程 skwasm 文本频繁变化崩溃](https://github.com/flutter/flutter/issues/190039) · [PR #190048 修复](https://github.com/flutter/flutter/pull/190048) · [PR #190287 MediaQuery 支持 reduceMotion](https://github.com/flutter/flutter/pull/190287)

**其他**：[CanvasKit vs skwasm for Flutter web in 2026](https://startdebugging.net/2026/09/canvaskit-vs-skwasm-for-flutter-web-in-2026/) · [kinetic_text（同架构参考实现）](https://pub.dev/packages/kinetic_text) · [scrambletext](https://pub.dev/packages/scrambletext) · [use_scramble](https://pub.dev/packages/use_scramble) · [animated_text_kit](https://pub.dev/packages/animated_text_kit) · [CSS Backgrounds 3 §6.1.2 Blurring Shadow Edges](https://www.w3.org/TR/css-backgrounds-3/#shadow-blur)
