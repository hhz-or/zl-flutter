import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/widgets.dart';

/// 乱码字符集，来自原版 `script.js` 的 `scrambleChars`。
const String kScrambleGlyphs =
    r'ABCDEFGHIJKLMNOPQRSTUVWSYZ0123456789$#@&*%?±!<>-_\/[]{}—=+^abcdefghijklmnopqrstuvwsyz';

/// 乱码文字组件：逐字锁定（scramble / decode）动画。
///
/// 复刻原版网页的核心视觉：左侧已锁定的字符显示真身，右侧未锁定的字符
/// 每帧随机闪烁。**关键优化**：布局在动画期间完全稳定，不会像原版那样
/// 因为 ASCII 与中文宽度不同而整段抖动。
///
/// 契约（实现者必须满足）：
/// 1. 首次 `build` 之前不需要 `text` 之外的任何输入；`text` 变化时自动重播。
/// 2. 动画期间组件的尺寸恒定 = 用同样 [style] 渲染最终 [text] 的尺寸
///    （允许 ±0.5 逻辑像素误差），不得因乱码字符宽度不同而改变。
/// 3. 动画结束后渲染结果必须与 `Text(text, style: style, textAlign: ...)`
///    完全一致。
/// 4. [animate] 为 `false`、或系统/用户要求减少动效时，直接显示最终文本。
/// 5. 语义树中只暴露 [text]（最终文本），乱码帧不得被读屏软件读到。
///
/// ## 实现方案（以及为什么不是掩码方案）
///
/// 采用 **「真实 [Text] 打底 + 逐帧裁剪 / 覆盖」**：动画的底座是一个参数与
/// 本组件完全相同的真实 [Text]，由引擎负责排版与最终绘制。于是：
///
/// * 尺寸、换行、居中（含最后一行不齐）、[maxLines]、textScaler 全部由
///   引擎的 `RenderParagraph` 决定 → **布局零抖动**（契约 2），并且动画
///   结束后根本没有裁剪、没有覆盖，屏幕上是逐像素的 `Text`（契约 3）。
/// * 已锁定字符（`i < lockedCount`）＝ 把底座 [Text] 裁剪到这些字符的
///   “字形格子”内。格子只测量一次（`TextPainter.getBoxesForSelection`），
///   因为是真实文本自己的绘制结果，锁定部分在动画途中也与最终画面一致。
/// * 未锁定字符 ＝ 用**每个乱码字形各自缓存**的 `TextPainter`（每个字形
///   只构建一次，n 个字符共用同一批画笔）按其所在格子居中、按行基线对齐
///   绘制。位置锚定在“真实文本的格子”上，所以 ASCII 乱码的宽度不会改变
///   任何布局 → 这就是对原版抖动的修复。
/// * 没有采用「在不透明遮罩上盖乱码」的备选方案：遮罩需要知道背景色，
///   而本组件可能被放在渐变/图片之上；裁剪方案与背景无关，且在动画期间
///   就复用真实文本的绘制结果。
///
/// 每帧只做一次重绘（[ChangeNotifier] → `markNeedsPaint`），不重建控件树，
/// 也不会每帧为每个字符新建 `TextPainter`（契约 9）。
class ScrambleText extends StatefulWidget {
  const ScrambleText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.center,
    this.textDirection,
    this.maxLines,
    this.animate = true,
    this.charsPerSecond = 14,
    this.minDuration = const Duration(milliseconds: 450),
    this.maxDuration = const Duration(milliseconds: 2600),
    this.speed = 1.0,
    this.random,
    this.glyphs = kScrambleGlyphs,
    this.onCompleted,
    this.semanticLabel,
  });

  /// 最终要显示的文本。
  final String text;

  final TextStyle? style;

  final TextAlign textAlign;

  final TextDirection? textDirection;

  final int? maxLines;

  /// 是否播放动画。
  final bool animate;

  /// 每秒锁定的字符数。原版约为 12 字/秒（60fps 下每 5 帧锁定 1 字）。
  final double charsPerSecond;

  final Duration minDuration;

  final Duration maxDuration;

  /// 整体速度倍率，`> 1` 更快（时长按此值缩短），`< 1` 更慢。
  ///
  /// 时长计算：`clamp(text.length / charsPerSecond, minDuration, maxDuration) / speed`。
  final double speed;

  /// 注入随机源以便测试复现。
  final math.Random? random;

  /// 乱码字符集。
  final String glyphs;

  /// 全部字符锁定完成时回调。
  ///
  /// 保证“帧后”触发：既不会在 `build`/`layout` 期间同步回调，也只会触发
  /// 一次（`restart()` 之后可以再次触发）。
  final VoidCallback? onCompleted;

  /// 读屏软件朗读的内容，默认使用 [text]。
  final String? semanticLabel;

  @override
  State<ScrambleText> createState() => ScrambleTextState();
}

/// 公开 State 类型，便于测试与外部驱动。
///
/// 契约：动画期间布局必须恒定（等于最终文本的排版尺寸），结束后渲染结果
/// 必须与同样式 [Text] 完全一致；语义树只暴露最终文本。
class ScrambleTextState extends State<ScrambleText> with SingleTickerProviderStateMixin {
  /// 共享给绘制层的每帧状态（乱码串 + 已锁定数量），变化时只触发重绘。
  late final _ScrambleFrame _frame;

  final math.Random _fallbackRandom = math.Random();

  AnimationController? _controller;

  bool _started = false;
  bool _reduceMotion = false;
  bool _completedNotified = false;
  int _completionToken = 0;

  math.Random get _random => widget.random ?? _fallbackRandom;

  @override
  void initState() {
    super.initState();
    _frame = _ScrambleFrame(text: widget.text, glyphs: widget.glyphs, random: _random);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 注意：`MediaQueryData.disableAnimations` 只覆盖 Android 与 Web，
    // iOS / macOS 的「减弱动态效果」只设置 `AccessibilityFeatures.reduceMotion`；
    // Flutter 3.47 也没有 `MediaQuery.reduceMotionOf`，所以两者都要查。
    final bool reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    if (!_started || reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      _begin();
    }
  }

  @override
  void didUpdateWidget(ScrambleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      // 契约 1：文本变化时从头重播。
      _begin();
      return;
    }
    if (oldWidget.animate && !widget.animate) {
      // 契约 4：关掉动画时立即落到最终状态。
      completeNow();
      return;
    }
    // 契约 1：文本没变就不重播。只同步不影响播放进度的输入。
    _controller?.duration = _totalDuration();
    _frame.updateGlyphs(glyphs: widget.glyphs, random: _random);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// 已锁定的字符数量（0 ~ [ScrambleText.text].length）。
  int get lockedCount => _frame.lockedCount;

  /// 是否已全部锁定。
  bool get isComplete => _frame.isComplete;

  /// 当前这一帧正在显示的字符串（用于测试断言）。
  ///
  /// 恒满足 `currentFrame.length == text.length`；
  /// `currentFrame.substring(0, lockedCount) == text.substring(0, lockedCount)`；
  /// 其余位置来自 [ScrambleText.glyphs]。
  String get currentFrame => _frame.frameText;

  /// 立即跳到最终状态。
  ///
  /// 停止动画控制器并把 [lockedCount] 置为 `text.length`；[onCompleted]
  /// 会在下一帧后触发一次（若尚未触发过）。
  void completeNow() {
    _controller?.stop();
    _frame.complete();
    _scheduleCompleted();
  }

  /// 从头重播动画。
  void restart() => _begin();

  /// 动画总时长（契约 5）。
  Duration _totalDuration() {
    final double charsPerSecond = widget.charsPerSecond.isFinite && widget.charsPerSecond > 0
        ? widget.charsPerSecond
        : 1.0;
    final double speed = widget.speed.isFinite && widget.speed > 0 ? widget.speed : 1.0;
    final double minSeconds = widget.minDuration.inMicroseconds / Duration.microsecondsPerSecond;
    final double maxSeconds = math.max(
      minSeconds,
      widget.maxDuration.inMicroseconds / Duration.microsecondsPerSecond,
    );
    final double seconds = (widget.text.length / charsPerSecond).clamp(minSeconds, maxSeconds);
    return Duration(microseconds: (seconds / speed * Duration.microsecondsPerSecond).round());
  }

  bool get _shouldAnimate => widget.animate && !_reduceMotion && widget.text.isNotEmpty;

  /// 重置到第 0 帧，并按需要启动动画或直接完成。
  void _begin() {
    _started = true;
    _completedNotified = false;
    // 让上一轮已经排队但尚未执行的「完成」回调失效：
    // `completeNow()` 紧接着 `restart()` 时，否则 onCompleted 会被调用两次。
    _completionToken++;
    _frame.reset(text: widget.text, glyphs: widget.glyphs, random: _random);
    _controller?.stop();
    if (!_shouldAnimate) {
      // 减少动效 / animate=false / 空文本：不创建也不启动任何控制器。
      _frame.complete();
      _scheduleCompleted();
      return;
    }
    AnimationController? controller = _controller;
    if (controller == null) {
      controller = AnimationController(vsync: this)..addListener(_onTick);
      _controller = controller;
    }
    controller
      ..duration = _totalDuration()
      ..value = 0
      ..forward();
  }

  void _onTick() {
    final AnimationController? controller = _controller;
    if (controller == null) {
      return;
    }
    final double value = controller.value;
    if (value >= 1) {
      _frame.complete();
      _scheduleCompleted();
    } else {
      _frame.setProgress(value);
    }
  }

  /// 触发 [ScrambleText.onCompleted]，保证**每一轮只触发一次**且在帧后执行
  /// （不会在 build / layout 期间同步回调调用方）。
  void _scheduleCompleted() {
    if (_completedNotified) {
      return;
    }
    _completedNotified = true;
    final VoidCallback? callback = widget.onCompleted;
    if (callback == null) {
      return;
    }
    // 记录排队时的轮次；回调真正执行时若已经 `_begin()` 过，就丢弃它。
    final int token = _completionToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == _completionToken) {
        callback();
      }
    });
    // `addPostFrameCallback` 本身不会安排新帧：如果当前不在帧内（例如外部
    // 直接调用 `completeNow()`），补一次调度，保证回调一定会被执行。
    final SchedulerPhase phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DefaultTextStyle defaultTextStyle = DefaultTextStyle.of(context);
    TextStyle? effectiveStyle = widget.style;
    if (widget.style == null || widget.style!.inherit) {
      effectiveStyle = defaultTextStyle.style.merge(widget.style);
    }
    if (MediaQuery.boldTextOf(context) && effectiveStyle != null) {
      effectiveStyle = effectiveStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final TextDirection? textDirection = widget.textDirection ?? Directionality.maybeOf(context);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final Locale? locale = Localizations.maybeLocaleOf(context);
    // 与 Text 的解析保持一致，用于测量字符格子（底座 Text 自己也会这样解析）。
    final ui.TextHeightBehavior? textHeightBehavior =
        defaultTextStyle.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context);

    return Semantics(
      container: true,
      label: widget.semanticLabel ?? widget.text,
      child: ExcludeSemantics(
        child: _ScrambleTextLayout(
          text: widget.text,
          frame: _frame,
          effectiveStyle: effectiveStyle,
          textAlign: widget.textAlign,
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: widget.maxLines,
          softWrap: defaultTextStyle.softWrap,
          overflow: effectiveStyle?.overflow ?? defaultTextStyle.overflow,
          locale: locale,
          textHeightBehavior: textHeightBehavior,
          glyphs: widget.glyphs,
          // 底座 Text 单独成层：它的三层模糊辉光是本应用最贵的一次栅格化，
          // 而它在整个动画期间**完全不变**。缓存之后，逐帧重绘的只有乱码字形，
          // 于是「动画期间的辉光」与「播完后的辉光」可以是同一个样式。
          child: RepaintBoundary(
            child: Text(
              widget.text,
              style: widget.style,
              textAlign: widget.textAlign,
              textDirection: widget.textDirection,
              maxLines: widget.maxLines,
            ),
          ),
        ),
      ),
    );
  }
}

/// 每帧共享状态：逐字符的显示内容（已锁定位置是真身，其余是乱码）。
///
/// 只在动画推进时 [notifyListeners]，绘制层据此 `markNeedsPaint`，
/// 因此每帧只重绘、不重建控件树。
class _ScrambleFrame extends ChangeNotifier {
  _ScrambleFrame({required String text, required String glyphs, required math.Random random}) {
    reset(text: text, glyphs: glyphs, random: random);
  }

  String _text = '';
  String _glyphs = '';
  math.Random _random = math.Random();
  List<String> _cells = const <String>[];
  int _lockedCount = 0;
  bool _isComplete = false;

  String get text => _text;

  /// 每个 UTF-16 码元对应一个显示字符，长度恒等于 `text.length`。
  List<String> get cells => _cells;

  int get lockedCount => _lockedCount;

  bool get isComplete => _isComplete;

  String get frameText => _cells.join();

  void reset({required String text, required String glyphs, required math.Random random}) {
    _text = text;
    _glyphs = glyphs;
    _random = random;
    _lockedCount = 0;
    _isComplete = text.isEmpty;
    _cells = List<String>.generate(text.length, (_) => _randomGlyph(), growable: false);
    notifyListeners();
  }

  void updateGlyphs({required String glyphs, required math.Random random}) {
    if (glyphs == _glyphs && identical(random, _random)) {
      return;
    }
    _glyphs = glyphs;
    _random = random;
    if (_isComplete) {
      return;
    }
    _writeCells(_lockedCount);
    notifyListeners();
  }

  /// 按整体进度（0~1）推进；`lockedCount` 取整。
  void setProgress(double progress) {
    if (_isComplete || _text.isEmpty) {
      return;
    }
    final double clamped = progress.clamp(0.0, 1.0);
    _writeCells((clamped * _text.length).floor().clamp(0, _text.length));
    notifyListeners();
  }

  void complete() {
    _isComplete = true;
    _writeCells(_text.length);
    notifyListeners();
  }

  void _writeCells(int locked) {
    _lockedCount = locked;
    for (int i = 0; i < _cells.length; i++) {
      _cells[i] = i < locked ? _text[i] : _randomGlyph();
    }
  }

  String _randomGlyph() {
    if (_glyphs.isEmpty) {
      return ' ';
    }
    return _glyphs[_random.nextInt(_glyphs.length)];
  }
}

/// 一次性的排版测量结果：每个字符的字形格子与所在行基线。
///
/// 只保存普通数值，不持有任何引擎资源，因此不需要释放；乱码字形画笔由
/// [_ScrambleTextRender] 单独缓存（见 [_GlyphKey]）。
class _ScrambleMetrics {
  _ScrambleMetrics({required this.cells, required this.baselines});

  /// 与文本等长；`null` 表示该字符没有可见格子（换行、被 ellipsis 截断、
  /// 半个代理对等）。
  final List<Rect?> cells;

  /// 与 [cells] 等长；该项所在行的基线（用于乱码字形对齐）。
  final List<double> baselines;

  /// 用与 `Text` 相同的排版参数测量真实文本，得到字符格子与行基线。
  static _ScrambleMetrics build({
    required String text,
    required TextStyle? style,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required int? maxLines,
    required bool softWrap,
    required TextOverflow overflow,
    required Locale? locale,
    required ui.TextHeightBehavior? textHeightBehavior,
    required double minWidth,
    required double maxWidth,
  }) {
    final int length = text.length;
    final List<Rect?> cells = List<Rect?>.filled(length, null);
    final List<double> baselines = List<double>.filled(length, 0);
    if (length > 0) {
      // 与 `RenderParagraph._layoutTextWithConstraints` 完全一致的排版参数，
      // 这样坐标系、换行与对齐都与底座 Text 一致。
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: style, locale: locale),
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: maxLines,
        ellipsis: overflow == TextOverflow.ellipsis ? '\u2026' : null,
        locale: locale,
        textWidthBasis: TextWidthBasis.parent,
        textHeightBehavior: textHeightBehavior,
      )..layout(
          minWidth: minWidth,
          maxWidth: softWrap || overflow == TextOverflow.ellipsis ? maxWidth : double.infinity,
        );
      final List<ui.LineMetrics> lines = painter.computeLineMetrics();
      for (int i = 0; i < length; i++) {
        final List<TextBox> boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
          // max：取“字格”（advance box）而不是墨迹框，相邻格子首尾相接，
          // 既不会互相渗透，也不会切掉字形的抗锯齿边缘。
          boxHeightStyle: ui.BoxHeightStyle.max,
          boxWidthStyle: ui.BoxWidthStyle.max,
        );
        if (boxes.isEmpty) {
          // 换行、ellipsis 截断、半个代理对等情况：没有格子，跳过。
          continue;
        }
        final TextBox box = boxes.first;
        final Rect cell = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
        if (cell.width <= 0 || cell.height <= 0) {
          continue;
        }
        cells[i] = cell;
        baselines[i] = _baselineFor(cell, lines);
      }
      painter.dispose();
    }
    return _ScrambleMetrics(cells: cells, baselines: baselines);
  }

  /// 找到包含该格子的行基线；找不到时取最近的一行。
  static double _baselineFor(Rect cell, List<ui.LineMetrics> lines) {
    if (lines.isEmpty) {
      return cell.bottom;
    }
    final double center = cell.center.dy;
    double best = lines.first.baseline;
    double bestDistance = double.infinity;
    for (final ui.LineMetrics line in lines) {
      if (center >= line.baseline - line.ascent && center <= line.baseline + line.descent) {
        return line.baseline;
      }
      final double distance = (center - line.baseline).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = line.baseline;
      }
    }
    return best;
  }

  /// 已锁定字符的**按行合并**裁剪区：每行一个矩形。
  ///
  /// 已锁定的是前缀，所以同一行内它必然是从行首开始的一段连续字符，合并成
  /// 一个矩形与逐字并集等价；而路径段数从「字符数」降到「行数」（通常 1~3），
  /// 裁剪层每帧细分这条路径的成本因此低得多。
  /// 都要重新细分这条路径，段数越少越便宜。
  Path? lockedLinePath(Offset offset, int lockedCount) {
    final int count = math.min(lockedCount, cells.length);
    if (count <= 0) {
      return null;
    }
    final List<Rect> rects = <Rect>[];
    double? lineBaseline;
    Rect? run;
    for (int i = 0; i < count; i++) {
      final Rect? cell = cells[i];
      if (cell == null) {
        continue;
      }
      final double baseline = baselines[i];
      if (lineBaseline == null || baseline != lineBaseline) {
        final Rect? pending = run;
        if (pending != null) {
          rects.add(pending);
          run = null;
        }
        lineBaseline = baseline;
      }
      run = run == null ? cell : run.expandToInclude(cell);
    }
    final Rect? tail = run;
    if (tail != null) {
      rects.add(tail);
    }
    if (rects.isEmpty) {
      return null;
    }
    final Path path = Path();
    for (final Rect rect in rects) {
      path.addRect(rect.shift(offset));
    }
    return path;
  }

  /// 未锁定字符的格子并集（用于把乱码层的辉光限制在乱码区域内）。
  ///
  /// 不裁剪的话，模糊后的辉光会漫到已锁定的真身上，破坏
  /// 「已锁定前缀 = 真实 Text 的对应裁剪」这一像素级保证。
  Path? unlockedPath(Offset offset, int lockedCount) {
    Path? path;
    for (int i = math.max(0, lockedCount); i < cells.length; i++) {
      final Rect? cell = cells[i];
      if (cell == null) {
        continue;
      }
      path ??= Path();
      path.addRect(cell.shift(offset));
    }
    return path;
  }
}

/// 单个乱码字形的缓存画笔。
class _ScrambleGlyph {
  _ScrambleGlyph({required this.painter, required this.baseline, required this.advance});

  final TextPainter painter;

  /// 该字形自身排版基线（相对其排版原点）。
  final double baseline;

  /// 该字形的步进宽度，用于在真实字符的格子里做水平居中。
  final double advance;

  void dispose() => painter.dispose();
}

/// 乱码字形画笔缓存的失效键：只有这些输入变化时才需要重建画笔。
class _GlyphKey {
  const _GlyphKey({
    required this.glyphs,
    required this.style,
    required this.textScaler,
    required this.textDirection,
    required this.locale,
    required this.textHeightBehavior,
  });

  final String glyphs;
  final TextStyle? style;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final Locale? locale;
  final ui.TextHeightBehavior? textHeightBehavior;

  @override
  bool operator ==(Object other) {
    return other is _GlyphKey &&
        other.glyphs == glyphs &&
        other.style == style &&
        other.textScaler == textScaler &&
        other.textDirection == textDirection &&
        other.locale == locale &&
        other.textHeightBehavior == textHeightBehavior;
  }

  @override
  int get hashCode =>
      Object.hash(glyphs, style, textScaler, textDirection, locale, textHeightBehavior);
}

/// 为字符集里的每个字形各建一个画笔（每个字形只建一次，n 个字符共用）。
///
/// **画笔不带 text-shadow**：乱码字形每帧都要重画，若每个字形各自带模糊阴影，
/// 一帧就要做 N×层数 次高斯模糊（实测在 Impeller 上会把 raster 时间推到 60ms）。
/// 辉光改由整段字形共用一次 `saveLayer` + `ImageFilter.blur` 实现，见
/// `_ScrambleTextRender.paint`。
Map<String, _ScrambleGlyph> _buildGlyphPainters(_GlyphKey key) {
  final Map<String, _ScrambleGlyph> painters = <String, _ScrambleGlyph>{};
  final TextStyle? glyphStyle = key.style?.copyWith(
    shadows: const <Shadow>[],
  );
  for (int i = 0; i < key.glyphs.length; i++) {
    // 按 UTF-16 码元建画笔，与 `_ScrambleFrame._randomGlyph` 的取值方式一致，
    // 保证 `currentFrame.length == text.length`。
    final String glyph = key.glyphs[i];
    if (painters.containsKey(glyph)) {
      continue;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(text: glyph, style: glyphStyle, locale: key.locale),
      textAlign: TextAlign.left,
      textDirection: key.textDirection,
      textScaler: key.textScaler,
      textWidthBasis: TextWidthBasis.longestLine,
      textHeightBehavior: key.textHeightBehavior,
      locale: key.locale,
    )..layout(maxWidth: _kGlyphLayoutWidth);
    final List<ui.LineMetrics> lines = painter.computeLineMetrics();
    painters[glyph] = _ScrambleGlyph(
      painter: painter,
      baseline: lines.isEmpty ? painter.height : lines.first.baseline,
      advance: painter.width,
    );
  }
  return painters;
}

/// 整段乱码字形共用的辉光参数。
class _GlyphGlow {
  const _GlyphGlow(this.color, this.sigma);

  final Color color;
  final double sigma;
}

/// 乱码字形的排版约束宽度：单字符，足够大即可（保证不换行）。
const double _kGlyphLayoutWidth = 4096;

/// 承载绘制层的渲染对象：底座是真实 [Text]，按帧裁剪 / 覆盖。
class _ScrambleTextLayout extends SingleChildRenderObjectWidget {
  const _ScrambleTextLayout({
    required this.text,
    required this.frame,
    required this.effectiveStyle,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.maxLines,
    required this.softWrap,
    required this.overflow,
    required this.locale,
    required this.textHeightBehavior,
    required this.glyphs,
    required super.child,
  });

  final String text;
  final _ScrambleFrame frame;
  final TextStyle? effectiveStyle;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final TextScaler textScaler;
  final int? maxLines;
  final bool softWrap;
  final TextOverflow overflow;
  final Locale? locale;
  final ui.TextHeightBehavior? textHeightBehavior;
  final String glyphs;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _ScrambleTextRender(
      text: text,
      frame: frame,
      effectiveStyle: effectiveStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
      softWrap: softWrap,
      overflow: overflow,
      locale: locale,
      textHeightBehavior: textHeightBehavior,
      glyphs: glyphs,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _ScrambleTextRender renderObject) {
    renderObject
      ..frame = frame
      ..text = text
      ..effectiveStyle = effectiveStyle
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..maxLines = maxLines
      ..softWrap = softWrap
      ..overflow = overflow
      ..locale = locale
      ..textHeightBehavior = textHeightBehavior
      ..glyphs = glyphs;
  }
}

class _ScrambleTextRender extends RenderProxyBox {
  _ScrambleTextRender({
    required String text,
    required _ScrambleFrame frame,
    required TextStyle? effectiveStyle,
    required TextAlign textAlign,
    required TextDirection? textDirection,
    required TextScaler textScaler,
    required int? maxLines,
    required bool softWrap,
    required TextOverflow overflow,
    required Locale? locale,
    required ui.TextHeightBehavior? textHeightBehavior,
    required String glyphs,
  })  : _text = text,
        _frame = frame,
        _effectiveStyle = effectiveStyle,
        _textAlign = textAlign,
        _textDirection = textDirection,
        _textScaler = textScaler,
        _maxLines = maxLines,
        _softWrap = softWrap,
        _overflow = overflow,
        _locale = locale,
        _textHeightBehavior = textHeightBehavior,
        _glyphs = glyphs;

  String _text;
  _ScrambleFrame _frame;
  TextStyle? _effectiveStyle;
  TextAlign _textAlign;
  TextDirection? _textDirection;
  TextScaler _textScaler;
  int? _maxLines;
  bool _softWrap;
  TextOverflow _overflow;
  Locale? _locale;
  ui.TextHeightBehavior? _textHeightBehavior;
  String _glyphs;

  _ScrambleMetrics? _metrics;
  BoxConstraints? _metricsConstraints;
  bool _metricsDirty = true;
  bool _listening = false;

  /// 每个乱码字形一个画笔（见 [_GlyphKey]），全生命周期按需重建。
  Map<String, _ScrambleGlyph> _glyphPainters = <String, _ScrambleGlyph>{};
  _GlyphKey? _glyphKey;

  String get text => _text;

  set text(String value) {
    if (value == _text) {
      return;
    }
    _text = value;
    _invalidateMetrics();
  }

  _ScrambleFrame get frame => _frame;

  set frame(_ScrambleFrame value) {
    if (identical(value, _frame)) {
      return;
    }
    if (_listening) {
      _frame.removeListener(_onFrameChanged);
      value.addListener(_onFrameChanged);
    }
    _frame = value;
    _invalidateMetrics();
    markNeedsPaint();
  }

  TextStyle? get effectiveStyle => _effectiveStyle;

  set effectiveStyle(TextStyle? value) {
    if (value == _effectiveStyle) {
      return;
    }
    _effectiveStyle = value;
    _invalidateMetrics();
  }

  TextAlign get textAlign => _textAlign;

  set textAlign(TextAlign value) {
    if (value == _textAlign) {
      return;
    }
    _textAlign = value;
    _invalidateMetrics();
  }

  TextDirection? get textDirection => _textDirection;

  set textDirection(TextDirection? value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    _invalidateMetrics();
  }

  TextScaler get textScaler => _textScaler;

  set textScaler(TextScaler value) {
    if (value == _textScaler) {
      return;
    }
    _textScaler = value;
    _invalidateMetrics();
  }

  int? get maxLines => _maxLines;

  set maxLines(int? value) {
    if (value == _maxLines) {
      return;
    }
    _maxLines = value;
    _invalidateMetrics();
  }

  bool get softWrap => _softWrap;

  set softWrap(bool value) {
    if (value == _softWrap) {
      return;
    }
    _softWrap = value;
    _invalidateMetrics();
  }

  TextOverflow get overflow => _overflow;

  set overflow(TextOverflow value) {
    if (value == _overflow) {
      return;
    }
    _overflow = value;
    _invalidateMetrics();
  }

  Locale? get locale => _locale;

  set locale(Locale? value) {
    if (value == _locale) {
      return;
    }
    _locale = value;
    _invalidateMetrics();
  }

  ui.TextHeightBehavior? get textHeightBehavior => _textHeightBehavior;

  set textHeightBehavior(ui.TextHeightBehavior? value) {
    if (value == _textHeightBehavior) {
      return;
    }
    _textHeightBehavior = value;
    _invalidateMetrics();
  }

  String get glyphs => _glyphs;

  set glyphs(String value) {
    if (value == _glyphs) {
      return;
    }
    _glyphs = value;
    _invalidateMetrics();
  }

  void _invalidateMetrics() {
    _metricsDirty = true;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_onFrameChanged);
    _listening = true;
  }

  @override
  void detach() {
    if (_listening) {
      _frame.removeListener(_onFrameChanged);
      _listening = false;
    }
    super.detach();
  }

  @override
  void dispose() {
    _disposeGlyphPainters();
    _metrics = null;
    super.dispose();
  }

  /// 每帧只标记重绘，不重建控件树（契约 9）。
  void _onFrameChanged() {
    if (attached) {
      markNeedsPaint();
    }
  }

  void _disposeGlyphPainters() {
    for (final _ScrambleGlyph glyph in _glyphPainters.values) {
      glyph.dispose();
    }
    _glyphPainters = <String, _ScrambleGlyph>{};
    _glyphKey = null;
  }

  /// 乱码字形画笔只在字体相关输入变化时重建（换文本 / 换约束不重建）。
  void _ensureGlyphPainters() {
    final _GlyphKey key = _GlyphKey(
      glyphs: _glyphs,
      style: _effectiveStyle,
      textScaler: _textScaler,
      textDirection: _textDirection ?? TextDirection.ltr,
      locale: _locale,
      textHeightBehavior: _textHeightBehavior,
    );
    if (key == _glyphKey) {
      return;
    }
    _disposeGlyphPainters();
    _glyphKey = key;
    _glyphPainters = _buildGlyphPainters(key);
  }

  @override
  void performLayout() {
    // 底座 Text 用收到的约束排版：尺寸、换行、对齐因此与直接用 Text 完全一致。
    super.performLayout();
    if (_metricsDirty || _metricsConstraints != constraints) {
      _metricsConstraints = constraints;
      _metricsDirty = false;
      _ensureGlyphPainters();
      _metrics = _ScrambleMetrics.build(
        text: _text,
        style: _effectiveStyle,
        textAlign: _textAlign,
        textDirection: _textDirection ?? TextDirection.ltr,
        textScaler: _textScaler,
        maxLines: _maxLines,
        softWrap: _softWrap,
        overflow: _overflow,
        locale: _locale,
        textHeightBehavior: _textHeightBehavior,
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      );
    }
  }

  /// 乱码字形共用的辉光：取最外层 text-shadow 的颜色与模糊半径。
  ///
  /// 原版的三层是 `0 0 5px #fff, 0 0 10px accent, 0 0 15px accent`；
  /// 乱码阶段每帧都在闪，用一层即可，视觉上分辨不出差别。
  _GlyphGlow? get _glyphGlow {
    final List<Shadow> shadows = _effectiveStyle?.shadows ?? const <Shadow>[];
    if (shadows.isEmpty) {
      return null;
    }
    final Shadow outermost = shadows.last;
    if (outermost.blurRadius <= 0 || outermost.color.a <= 0) {
      return null;
    }
    // Flutter 的 Shadow.blurRadius 换算成 sigma 的公式。
    return _GlyphGlow(
      outermost.color,
      outermost.blurRadius * 0.57735 + 0.5,
    );
  }

  void _paintGlyphs(
    Canvas canvas,
    Offset offset,
    _ScrambleMetrics metrics,
    List<String> cells,
    int locked,
    int length,
  ) {
    for (int i = locked; i < length; i++) {
      final Rect? cell = metrics.cells[i];
      if (cell == null) {
        continue;
      }
      final _ScrambleGlyph? glyph = _glyphPainters[cells[i]];
      if (glyph == null) {
        continue;
      }
      glyph.painter.paint(
        canvas,
        Offset(
          offset.dx + cell.center.dx - glyph.advance / 2,
          offset.dy + metrics.baselines[i] - glyph.baseline,
        ),
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final _ScrambleMetrics? metrics = _metrics;
    final _ScrambleFrame frame = _frame;
    if (child == null || metrics == null || frame.text != _text) {
      // 没有测量结果（例如文本刚变化）：直接画底座 Text，绝不出错。
      super.paint(context, offset);
      return;
    }
    final int length = _text.length;
    final int locked = frame.lockedCount.clamp(0, length);
    if (frame.isComplete || locked >= length) {
      // 契约 3：完成后就是纯粹的 Text 绘制（无裁剪、无覆盖）→ 逐像素一致。
      super.paint(context, offset);
      return;
    }

    // 1) 已锁定字符：把**缓存好的**底座 Text 图层按这些字符的字格裁出来。
    //
    //    底座 Text 是 RepaintBoundary，因此它的三层模糊辉光只在指令变化时
    //    栅格化一次；这里每帧只换一个裁剪区域。
    //
    //    ⚠️ 裁剪必须走 `pushClipPath`（裁剪图层），不能用
    //    `canvas.save(); clipPath(); super.paint(); restore();`：后者的裁剪记录在
    //    当前 picture 里，而 repaint boundary 子节点是作为独立图层**并列**合成
    //    的，裁剪根本作用不到它 —— 结果就是整句真身在动画一开始就全部露出来。
    if (locked > 0) {
      // `pushClipPath` 要的是**局部**坐标的 bounds 与 path，偏移由它自己加。
      final Path? clip = metrics.lockedLinePath(Offset.zero, locked);
      if (clip != null) {
        context.pushClipPath(
          true,
          offset,
          Offset.zero & size,
          clip,
          (PaintingContext inner, Offset innerOffset) =>
              super.paint(inner, innerOffset),
          clipBehavior: Clip.antiAlias,
        );
      }
    }

    // 2) 未锁定字符：把缓存的乱码字形画进各自的字格。
    final List<String> cells = frame.cells;
    if (cells.length != length) {
      return;
    }
    final Rect bounds = offset & size;
    // 辉光必须限制在乱码区域内，否则模糊会漫到已锁定的真身上，
    // 「已锁定前缀 = 真实 Text 的对应裁剪」这一逐像素保证就没了。
    final Path? scrambleArea = metrics.unlockedPath(offset, locked);
    if (scrambleArea == null) {
      return;
    }
    final _GlyphGlow? glow = _glyphGlow;
    if (glow != null) {
      // 整段字形只做**一次**高斯模糊：先把全部乱码字形画进一个图层，
      // 用 colorFilter 统一染成辉光色，再用 imageFilter 模糊后合成，
      // 最后叠上清晰的字形。比「每个字形各带 text-shadow」便宜一个数量级
      // —— 后者每帧要做 N×层数 次模糊，实测在 Impeller 上 raster 要 60ms。
      context.canvas.save();
      context.canvas.clipPath(scrambleArea);
      context.canvas.saveLayer(
        bounds,
        Paint()
          ..colorFilter = ColorFilter.mode(glow.color, BlendMode.srcIn)
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: glow.sigma,
            sigmaY: glow.sigma,
          ),
      );
      _paintGlyphs(context.canvas, offset, metrics, cells, locked, length);
      context.canvas.restore();
      context.canvas.restore();
    }
    // 清晰字形层裁到「文本框减去已锁定字格」：乱码字形可能比它所在的格子宽
    // （例如窄格里的 W），只裁文本框的话会盖到最后一个已锁定字符上。
    context.canvas.save();
    context.canvas.clipPath(_scramblePaintArea(bounds, offset, metrics, locked));
    _paintGlyphs(context.canvas, offset, metrics, cells, locked, length);
    context.canvas.restore();
  }

  // 「文本框 - 已锁定字格」的裁剪区。只在 locked / 偏移 / 尺寸变化时重算
  // （动画期间 locked 大约每秒变 12 次，而不是每帧）。
  Path? _areaCache;
  int _areaCacheLocked = -1;
  Offset? _areaCacheOffset;
  Size? _areaCacheSize;

  Path _scramblePaintArea(
    Rect bounds,
    Offset offset,
    _ScrambleMetrics metrics,
    int locked,
  ) {
    if (locked <= 0) {
      return Path()..addRect(bounds);
    }
    if (_areaCache != null &&
        _areaCacheLocked == locked &&
        _areaCacheOffset == offset &&
        _areaCacheSize == size) {
      return _areaCache!;
    }
    final Path boundsPath = Path()..addRect(bounds);
    // 按行合并（每行一个矩形）而不是逐字矩形：`Path.combine` 的段数从
    // 「字符数」降到「行数」，而两者在这里等价（已锁定的是连续前缀）。
    final Path? lockedArea = metrics.lockedLinePath(offset, locked);
    final Path area = lockedArea == null
        ? boundsPath
        : Path.combine(PathOperation.difference, boundsPath, lockedArea);
    _areaCache = area;
    _areaCacheLocked = locked;
    _areaCacheOffset = offset;
    _areaCacheSize = size;
    return area;
  }
}
