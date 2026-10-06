// 乱码文字动画（ScrambleText）的契约测试。
//
// 覆盖：逐字锁定的进度语义、时长/速度、尺寸零抖动、完成后与 Text 逐像素
// 一致、animate=false 与减少动效、文本变化重播、语义树只暴露最终文本、
// 边界输入、随机源可复现。

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_zl/features/generator/widgets/scramble_text.dart';

/// 与需求给定的长句（19 字，纯中文 → 乱码字符集里绝不含这些字形）。
const String _kText = '请在两分钟内对着镜子说八百遍我是正常人';

const ValueKey<String> _kScrambleKey = ValueKey<String>('scramble');
const ValueKey<String> _kReferenceKey = ValueKey<String>('reference');

/// 测试宿主：提供 Directionality / MediaQuery / 居中约束。
Widget _host(Widget child, {bool disableAnimations = false}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Center(child: child),
    ),
  );
}

/// 与实现相同的时长公式：clamp(length / charsPerSecond, min, max) / speed。
Duration _durationFor(
  int length, {
  double charsPerSecond = 14,
  Duration minDuration = const Duration(milliseconds: 450),
  Duration maxDuration = const Duration(milliseconds: 2600),
  double speed = 1,
}) {
  final double minSeconds = minDuration.inMicroseconds / Duration.microsecondsPerSecond;
  final double maxSeconds = max(
    minSeconds,
    maxDuration.inMicroseconds / Duration.microsecondsPerSecond,
  );
  final double seconds = (length / charsPerSecond).clamp(minSeconds, maxSeconds);
  return Duration(microseconds: (seconds / speed * Duration.microsecondsPerSecond).round());
}

ScrambleTextState _stateOf(WidgetTester tester) =>
    tester.state<ScrambleTextState>(find.byType(ScrambleText));

/// 底座（真实 [Text]）控件实例：播放期间应当始终是同一个实例。
Text _baseText(WidgetTester tester) => tester.widget<Text>(
      find.descendant(of: find.byKey(_kScrambleKey), matching: find.byType(Text)),
    );

/// 统计图像里有墨迹（alpha != 0）的像素数。
int _inkPixels(Uint8List rgba) {
  int ink = 0;
  for (int i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0) {
      ink++;
    }
  }
  return ink;
}

/// 一直泵帧直到动画完成。
///
/// 注意：`Ticker` 只有在“帧内”启动时才用当前帧时间作为计时起点；在帧外
/// 调用 [ScrambleTextState.restart] 时，第一次 tick 只是建立起点（进度 0），
/// 所以这里按帧推进而不是只泵一个固定时长。
Future<void> _pumpUntilComplete(
  WidgetTester tester,
  ScrambleTextState state, {
  Duration step = const Duration(milliseconds: 32),
  int maxFrames = 200,
}) async {
  for (int i = 0; i < maxFrames && !state.isComplete; i++) {
    await tester.pump(step);
  }
  expect(state.isComplete, isTrue, reason: '动画没有在 $maxFrames 帧内完成');
}

/// 抓取一个 [RepaintBoundary] 的原始 RGBA 像素（含图像尺寸）。
///
/// `toImage()` / `toByteData()` 是真正的异步引擎调用，必须放在
/// [WidgetTester.runAsync] 里，否则会卡在测试的 fake-async 时区里。
Future<({Uint8List pixels, int width, int height})> _pixels(
  WidgetTester tester,
  GlobalKey key,
) async {
  final ({Uint8List pixels, int width, int height})? result = await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final Uint8List pixels = Uint8List.fromList(data!.buffer.asUint8List());
    final int width = image.width;
    final int height = image.height;
    image.dispose();
    return (pixels: pixels, width: width, height: height);
  });
  return result!;
}

/// 只显示“已锁定前缀”的裁剪器：测试侧独立测量的字符格子并集。
///
/// 用它把一份普通 `Text` 裁成同样的前缀，可以与 [ScrambleText] 的中间帧
/// 做逐像素对比 —— 这是对“锁定字符位置与引擎排版一致”的独立验证。
class _LockedOnlyClipper extends CustomClipper<Path> {
  _LockedOnlyClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_LockedOnlyClipper oldClipper) => oldClipper.path != path;
}

Path _lockedPrefixPath(String text, TextStyle style, int locked, double width) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    textWidthBasis: TextWidthBasis.parent,
  )..layout(maxWidth: width);
  final Path path = Path();
  for (int i = 0; i < locked; i++) {
    final List<TextBox> boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
      boxHeightStyle: ui.BoxHeightStyle.max,
      boxWidthStyle: ui.BoxWidthStyle.max,
    );
    if (boxes.isEmpty) {
      continue;
    }
    path.addRect(boxes.first.toRect());
  }
  painter.dispose();
  return path;
}

/// 主机上的真实中文字体（用于验证“ASCII 与中文宽度不同”的真实场景）。
///
/// 找不到就跳过对应的测试：其余测试使用测试字体，不依赖主机字体。
const String _kHostFontPath = r'C:\Windows\Fonts\simhei.ttf';
const String _kHostFontFamily = 'ScrambleTestHei';

bool _hostFontAvailable() => File(_kHostFontPath).existsSync();

Future<void> _loadHostFont() async {
  final Uint8List bytes = File(_kHostFontPath).readAsBytesSync();
  final FontLoader loader = FontLoader(_kHostFontFamily)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  testWidgets('逐帧锁定：进度语义 / 完成 / onCompleted 只触发一次', (WidgetTester tester) async {
    int completed = 0;
    await tester.pumpWidget(
      _host(
        ScrambleText(
          text: _kText,
          animate: true,
          random: Random(1),
          charsPerSecond: 40,
          onCompleted: () => completed++,
        ),
      ),
    );
    final ScrambleTextState state = _stateOf(tester);

    // t = 0：一个字都没锁定，且显示的不是最终文本。
    expect(state.lockedCount, 0);
    expect(state.isComplete, isFalse);
    expect(state.currentFrame.length, _kText.length);
    expect(state.currentFrame, isNot(_kText));
    expect(completed, 0);

    const Duration step = Duration(milliseconds: 16);
    final Duration total = _durationFor(_kText.length, charsPerSecond: 40);
    Duration elapsed = Duration.zero;
    int previousLocked = 0;
    while (elapsed < total + step) {
      await tester.pump(step);
      elapsed += step;
      final int locked = state.lockedCount;
      final String frame = state.currentFrame;

      // 锁定数量只增不减。
      expect(locked, greaterThanOrEqualTo(previousLocked));
      previousLocked = locked;
      // 帧长恒定，前缀是真身，其余来自乱码字符集。
      expect(frame.length, _kText.length);
      expect(frame.substring(0, locked), _kText.substring(0, locked));
      for (int i = locked; i < frame.length; i++) {
        expect(kScrambleGlyphs.contains(frame[i]), isTrue, reason: 'index $i 不在乱码字符集内');
      }
      if (state.isComplete) {
        break;
      }
    }

    expect(state.isComplete, isTrue);
    expect(state.lockedCount, _kText.length);
    expect(state.currentFrame, _kText);
    expect(completed, 1);

    // 完成后继续泵帧：不得重复回调。
    await tester.pump(step);
    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
    expect(state.currentFrame, _kText);
  });

  testWidgets('时长 = clamp(字数 / charsPerSecond, min, max) / speed', (WidgetTester tester) async {
    final String text = '指令' * 50; // 100 字 → 100 / 100 = 1s，不被 min/max 夹住
    expect(text.length, 100);

    await tester.pumpWidget(
      _host(ScrambleText(text: text, random: Random(3), charsPerSecond: 100, maxLines: 6)),
    );
    final ScrambleTextState state = _stateOf(tester);
    await tester.pump(); // 动画的第一帧（elapsed = 0）
    expect(state.lockedCount, 0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(state.lockedCount, 50); // 100 字/秒 × 0.5s
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.lockedCount, 75);
    expect(state.isComplete, isFalse);
    await tester.pump(const Duration(milliseconds: 250));
    expect(state.isComplete, isTrue);
    expect(state.currentFrame, text);

    // 速度倍率：同样的文本，speed 2 → 时长减半（min 会被再次夹住）。
    await tester.pumpWidget(
      _host(
        ScrambleText(
          key: const ValueKey<String>('fast'),
          text: text,
          random: Random(3),
          charsPerSecond: 100,
          speed: 2,
          maxLines: 6,
        ),
      ),
    );
    final ScrambleTextState fast = tester.state<ScrambleTextState>(
      find.byKey(const ValueKey<String>('fast')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(fast.lockedCount, 50); // 1s / 2 = 0.5s，过半即 50 字
    await tester.pump(const Duration(milliseconds: 250));
    expect(fast.isComplete, isTrue);
  });

  testWidgets('尺寸零抖动：与同样式 Text 在 t=0 / 动画中 / 完成后完全一致', (WidgetTester tester) async {
    const TextStyle style = TextStyle(fontSize: 16, color: Color(0xFF000000), height: 1.3);
    Widget harness() => _host(
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 220,
            child: ScrambleText(
              key: _kScrambleKey,
              text: _kText,
              style: style,
              random: Random(2),
              charsPerSecond: 40,
            ),
          ),
          SizedBox(
            width: 220,
            child: Text(_kText, key: _kReferenceKey, style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );

    Size scrambleSize() => tester.getSize(find.byKey(_kScrambleKey));
    Size referenceSize() => tester.getSize(find.byKey(_kReferenceKey));

    await tester.pumpWidget(harness());
    final ScrambleTextState state = _stateOf(tester);
    final Size reference = referenceSize();
    expect(reference.height, greaterThan(style.fontSize! * 2), reason: '参考文本应当折成多行');
    expect(scrambleSize(), reference);

    // 播放期间不得重建控件树（每帧只重绘）。
    final Text baseBefore = _baseText(tester);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (state.isComplete) {
        break;
      }
      expect(scrambleSize(), reference, reason: '动画第 $i 帧尺寸漂移');
    }
    expect(state.isComplete, isFalse, reason: '此时应当仍在播放');
    expect(identical(_baseText(tester), baseBefore), isTrue, reason: '播放期间不应重建控件树');

    await tester.pump(const Duration(seconds: 3));
    expect(state.isComplete, isTrue);
    expect(scrambleSize(), reference);

    // 底座确实是真实 Text（最终画面由引擎排版与绘制）。
    final Text base = _baseText(tester);
    expect(base.data, _kText);
    expect(base.style, style);
    expect(base.textAlign, TextAlign.center);
  });

  testWidgets('完成后与同样式 Text 逐像素一致', (WidgetTester tester) async {
    const TextStyle style = TextStyle(fontSize: 18, color: Color(0xFF00E5FF), height: 1.4);
    final GlobalKey scrambleBoundary = GlobalKey();
    final GlobalKey referenceBoundary = GlobalKey();

    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            RepaintBoundary(
              key: scrambleBoundary,
              child: SizedBox(
                width: 200,
                child: ScrambleText(
                  key: _kScrambleKey,
                  text: _kText,
                  style: style,
                  random: Random(9),
                  charsPerSecond: 40,
                ),
              ),
            ),
            RepaintBoundary(
              key: referenceBoundary,
              child: SizedBox(
                width: 200,
                child: Text(_kText, style: style, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
    final ScrambleTextState state = _stateOf(tester);
    await _pumpUntilComplete(tester, state);

    final ({Uint8List pixels, int width, int height}) scramble = await _pixels(
      tester,
      scrambleBoundary,
    );
    final ({Uint8List pixels, int width, int height}) reference = await _pixels(
      tester,
      referenceBoundary,
    );
    expect(scramble.width, reference.width);
    expect(scramble.height, reference.height);
    expect(_inkPixels(reference.pixels), greaterThan(0), reason: '参考图必须有墨迹，像素对比才有意义');

    expect(scramble.pixels.length, reference.pixels.length);
    int differences = 0;
    for (int i = 0; i < scramble.pixels.length; i++) {
      if (scramble.pixels[i] != reference.pixels[i]) {
        differences++;
      }
    }
    expect(differences, 0, reason: '完成后的画面应当与 Text 逐像素一致（差异字节：$differences）');
  });

  testWidgets('style / textScaler 变化后重新测量，尺寸跟随新样式', (WidgetTester tester) async {
    Widget harness(TextStyle style, {TextScaler? textScaler}) => Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(textScaler: textScaler ?? TextScaler.noScaling),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  child: ScrambleText(
                    key: _kScrambleKey,
                    text: _kText,
                    style: style,
                    random: Random(14),
                    charsPerSecond: 40,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: Text(
                    _kText,
                    key: _kReferenceKey,
                    style: style,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );

    void expectSameSize() => expect(
          tester.getSize(find.byKey(_kScrambleKey)),
          tester.getSize(find.byKey(_kReferenceKey)),
        );

    await tester.pumpWidget(harness(const TextStyle(fontSize: 16)));
    final ScrambleTextState state = _stateOf(tester);
    expectSameSize();

    await tester.pump(const Duration(milliseconds: 100));
    expectSameSize();

    // 样式变化：重新测量，但仍不重播（文本未变）。
    await tester.pumpWidget(harness(const TextStyle(fontSize: 24)));
    expect(state.isComplete, isFalse);
    expectSameSize();
    await tester.pump(const Duration(milliseconds: 100));
    expectSameSize();

    // textScaler 变化：同样跟随。
    await tester.pumpWidget(
      harness(const TextStyle(fontSize: 24), textScaler: TextScaler.linear(1.5)),
    );
    expectSameSize();
    await tester.pump(const Duration(milliseconds: 100));
    expectSameSize();
  });

  testWidgets('glyphs 变化后乱码取自新字符集（字形缓存失效）', (WidgetTester tester) async {
    Widget harness(String glyphs) => _host(
      ScrambleText(
        key: _kScrambleKey,
        text: _kText,
        random: Random(13),
        charsPerSecond: 40,
        glyphs: glyphs,
      ),
    );

    await tester.pumpWidget(harness('X'));
    final ScrambleTextState state = _stateOf(tester);
    expect(state.lockedCount, 0);
    expect(state.currentFrame, 'X' * _kText.length);

    await tester.pump(const Duration(milliseconds: 100));
    final int locked = state.lockedCount;
    expect(locked, greaterThan(0));
    expect(state.currentFrame.substring(locked), 'X' * (_kText.length - locked));

    // 换字符集：文本没变 → 不重播，但乱码位置改用新字符集。
    await tester.pumpWidget(harness('Y'));
    expect(state.lockedCount, greaterThanOrEqualTo(locked));
    expect(
      state.currentFrame.substring(state.lockedCount),
      'Y' * (_kText.length - state.lockedCount),
    );
  });

  testWidgets('未锁定字符确实被遮挡、已锁定字符确实被画出', (WidgetTester tester) async {
    // 用“空白乱码字形”（测试字体下空格无墨迹）把乱码层变成透明的：
    // 于是画面上的墨迹只能来自被裁剪出来的“真实已锁定字符”。
    final GlobalKey boundary = GlobalKey();
    await tester.pumpWidget(
      _host(
        RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: 200,
            child: ScrambleText(
              text: _kText,
              style: const TextStyle(fontSize: 20),
              random: Random(12),
              charsPerSecond: 40,
              glyphs: ' ',
            ),
          ),
        ),
      ),
    );
    final ScrambleTextState state = _stateOf(tester);
    expect(state.lockedCount, 0);
    expect(state.isComplete, isFalse);

    final ({Uint8List pixels, int width, int height}) first = await _pixels(tester, boundary);
    expect(_inkPixels(first.pixels), 0, reason: '一个字都没锁定时，真实文本不得露出任何墨迹');

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.lockedCount, greaterThan(0));
    expect(state.isComplete, isFalse);
    final ({Uint8List pixels, int width, int height}) locked = await _pixels(tester, boundary);
    final int lockedInk = _inkPixels(locked.pixels);
    expect(lockedInk, greaterThan(0), reason: '已锁定字符应当被画出来');

    await _pumpUntilComplete(tester, state);
    final ({Uint8List pixels, int width, int height}) done = await _pixels(tester, boundary);
    expect(_inkPixels(done.pixels), greaterThan(lockedInk), reason: '完成后墨迹应当最多（全部真身）');
  });

  testWidgets('animate=false：立即完成、只回调一次、不排帧', (WidgetTester tester) async {
    int completed = 0;
    await tester.pumpWidget(
      _host(
        ScrambleText(
          text: _kText,
          animate: false,
          random: Random(4),
          onCompleted: () => completed++,
        ),
      ),
    );
    final ScrambleTextState state = _stateOf(tester);
    expect(state.isComplete, isTrue);
    expect(state.lockedCount, _kText.length);
    expect(state.currentFrame, _kText);
    expect(completed, 1);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '不应有动画在跑');

    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
  });

  testWidgets('减少动效（MediaQuery.disableAnimations）：立即完成', (WidgetTester tester) async {
    int completed = 0;
    await tester.pumpWidget(
      _host(
        ScrambleText(
          text: _kText,
          random: Random(4),
          onCompleted: () => completed++,
        ),
        disableAnimations: true,
      ),
    );
    final ScrambleTextState state = _stateOf(tester);
    expect(state.isComplete, isTrue);
    expect(state.currentFrame, _kText);
    expect(completed, 1);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '不应有动画在跑');

    await tester.pump(const Duration(seconds: 1));
    expect(completed, 1);
    expect(state.currentFrame, _kText);
  });

  testWidgets('播放中打开减少动效：立即落到最终状态', (WidgetTester tester) async {
    int completed = 0;
    Widget harness(bool disable) => _host(
      ScrambleText(
        text: _kText,
        random: Random(11),
        charsPerSecond: 40,
        onCompleted: () => completed++,
      ),
      disableAnimations: disable,
    );

    await tester.pumpWidget(harness(false));
    final ScrambleTextState state = _stateOf(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.isComplete, isFalse);

    await tester.pumpWidget(harness(true));
    expect(state.isComplete, isTrue);
    expect(state.currentFrame, _kText);
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('同一帧内 completeNow() 后立即 restart()：onCompleted 不会重复触发', (WidgetTester tester) async {
    int completed = 0;
    await tester.pumpWidget(
      _host(
        ScrambleText(
          key: _kScrambleKey,
          text: _kText,
          random: Random(11),
          charsPerSecond: 30,
          onCompleted: () => completed++,
        ),
      ),
    );
    final ScrambleTextState state = _stateOf(tester);
    await tester.pump(const Duration(milliseconds: 100));

    // 两个调用都会排队一个「帧后」回调。如果不带轮次标记，completeNow 排的那个
    // 回调会在 restart 之后照常执行，于是同一次播放回报两次完成。
    state.completeNow();
    state.restart();
    await tester.pump();
    await tester.pump();

    expect(completed, 0, reason: '重播之后，上一轮排队的完成回调必须作废');
    expect(state.isComplete, isFalse);

    await _pumpUntilComplete(tester, state);
    expect(completed, 1, reason: '重播后的这一轮只应回调一次');
  });

  testWidgets('文本变化重播，文本不变不重播；completeNow/restart 可用', (WidgetTester tester) async {
    int completed = 0;
    const String textA = '请不要去执行任何所谓的指令';
    const String textB = '在路口转十四个弯并直走十二米';
    Widget harness(String text) => _host(
      ScrambleText(
        key: _kScrambleKey,
        text: text,
        random: Random(6),
        charsPerSecond: 40,
        onCompleted: () => completed++,
      ),
    );

    await tester.pumpWidget(harness(textA));
    final ScrambleTextState state = _stateOf(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final int midway = state.lockedCount;
    expect(midway, greaterThan(0));

    // 文本不变：不得重播。
    await tester.pumpWidget(harness(textA));
    expect(state.lockedCount, greaterThanOrEqualTo(midway));

    // completeNow：立刻到最终状态。
    state.completeNow();
    expect(state.isComplete, isTrue);
    expect(state.currentFrame, textA);
    await tester.pump();
    expect(completed, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);

    // restart：回到第 0 帧并可以再次完成、再次回调。
    state.restart();
    expect(state.lockedCount, 0);
    expect(state.isComplete, isFalse);
    expect(state.currentFrame, isNot(textA));
    await _pumpUntilComplete(tester, state);
    expect(state.currentFrame, textA);
    expect(completed, 2);

    // 文本变化：从 0 重播并最终显示新文本。
    await tester.pumpWidget(harness(textB));
    expect(state.lockedCount, 0);
    expect(state.currentFrame.length, textB.length);
    expect(state.isComplete, isFalse);
    await _pumpUntilComplete(tester, state);
    expect(state.isComplete, isTrue);
    expect(state.currentFrame, textB);
    expect(completed, 3);
  });

  testWidgets('语义：播放期间也只暴露最终文本', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(ScrambleText(text: _kText, random: Random(5), charsPerSecond: 40)),
    );
    final ScrambleTextState state = _stateOf(tester);
    expect(state.isComplete, isFalse);
    expect(state.currentFrame, isNot(_kText));

    // 乱码帧不得进入语义树；最终文本恰好一个节点。
    expect(find.bySemanticsLabel(_kText), findsOneWidget);
    expect(find.bySemanticsLabel(state.currentFrame), findsNothing);

    // semanticLabel 优先。
    await tester.pumpWidget(
      _host(
        ScrambleText(
          key: const ValueKey<String>('labelled'),
          text: _kText,
          semanticLabel: '自定义朗读文本',
          random: Random(5),
        ),
      ),
    );
    expect(find.bySemanticsLabel('自定义朗读文本'), findsOneWidget);
    expect(find.bySemanticsLabel(_kText), findsNothing);

    handle.dispose();
  });

  testWidgets('边界输入不抛异常', (WidgetTester tester) async {
    const String longText = '致：在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。'
        '在十二小时三十七分钟二十四秒后完成一本针织的书。';
    final String mixed = 'ABC123 指令 ±— mixed 混排 42';
    final List<String> cases = <String>['', '指', mixed, longText];

    for (final String text in cases) {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: ScrambleText(
              key: ValueKey<String>('case-${text.length}'),
              text: text,
              random: Random(8),
              charsPerSecond: 200,
              maxLines: text.length > 200 ? 3 : null,
            ),
          ),
        ),
      );
      final ScrambleTextState state = _stateOf(tester);
      expect(tester.takeException(), isNull, reason: 'text.length=${text.length}');
      expect(state.currentFrame.length, text.length);
      expect(state.lockedCount, 0);

      // 泵完整个动画，全程不抛异常、最终等于原文。
      final Duration total = _durationFor(
        text.length,
        charsPerSecond: 200,
        minDuration: const Duration(milliseconds: 450),
      );
      Duration elapsed = Duration.zero;
      while (elapsed <= total + const Duration(milliseconds: 64)) {
        await tester.pump(const Duration(milliseconds: 32));
        elapsed += const Duration(milliseconds: 32);
        expect(tester.takeException(), isNull, reason: 'text.length=${text.length}');
        if (state.isComplete) {
          break;
        }
      }
      expect(state.isComplete, isTrue, reason: 'text.length=${text.length}');
      expect(state.currentFrame, text);
    }
  });

  testWidgets('相同随机种子 → 相同的帧序列', (WidgetTester tester) async {
    Future<List<String>> run() async {
      await tester.pumpWidget(
        _host(
          ScrambleText(
            key: UniqueKey(),
            text: _kText,
            random: Random(7),
            charsPerSecond: 40,
          ),
        ),
      );
      final ScrambleTextState state = _stateOf(tester);
      final List<String> frames = <String>[];
      for (int i = 0; i < 12; i++) {
        frames.add(state.currentFrame);
        await tester.pump(const Duration(milliseconds: 16));
      }
      return frames;
    }

    final List<String> first = await run();
    final List<String> second = await run();
    expect(first.toSet().length, greaterThan(1), reason: '帧序列应当一直在变');
    expect(second, equals(first));
  });

  testWidgets('真实字体下：锁定前缀与“Text 裁剪到字符格子”逐像素一致', (WidgetTester tester) async {
    // 测试字体每个字形等宽，无法体现“ASCII 乱码与中文宽度不同”的真实场景；
    // 这里在可用时加载主机上的中文黑体，验证真实字体下的裁剪对齐。
    if (!_hostFontAvailable()) {
      // ignore: avoid_print
      print('跳过：主机缺少 $_kHostFontPath');
      return;
    }
    await _loadHostFont();

    const double fontSize = 22;
    const double width = 200;
    const TextStyle style = TextStyle(
      fontFamily: _kHostFontFamily,
      fontSize: fontSize,
      color: Color(0xFF000000),
    );
    const String text = '请在两分钟内对着镜子说八百遍我是正常人ABC iiii 12345';

    // 前提：真实字体下 ASCII 与中文宽度确实不同（否则这个测试没意义）。
    final TextPainter ascii = TextPainter(
      text: const TextSpan(text: 'iiii', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final TextPainter cjk = TextPainter(
      text: const TextSpan(text: '永永永永', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(ascii.width, isNot(cjk.width), reason: '真实字体应当有宽度差异');
    ascii.dispose();
    cjk.dispose();

    final GlobalKey mineKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: mineKey,
            child: SizedBox(
              width: width,
              child: ScrambleText(
                text: text,
                style: style,
                random: Random(21),
                minDuration: const Duration(seconds: 10),
                maxDuration: const Duration(seconds: 10),
                // 空白乱码：画面上只剩“被裁剪出来的已锁定真身”。
                glyphs: ' ',
              ),
            ),
          ),
        ),
      ),
    );
    final ScrambleTextState state = _stateOf(tester);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    final int locked = state.lockedCount;
    expect(locked, greaterThan(0));
    expect(state.isComplete, isFalse);
    final ({Uint8List pixels, int width, int height}) mine = await _pixels(tester, mineKey);

    // 参照物：同样的 Text，用测试侧独立测量的字符格子做裁剪。
    final GlobalKey referenceKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: referenceKey,
            child: SizedBox(
              width: width,
              child: ClipPath(
                clipper: _LockedOnlyClipper(_lockedPrefixPath(text, style, locked, width)),
                child: const Text(text, style: style, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );
    final ({Uint8List pixels, int width, int height}) reference = await _pixels(
      tester,
      referenceKey,
    );

    expect(mine.width, reference.width);
    expect(mine.height, reference.height);
    expect(_inkPixels(reference.pixels), greaterThan(0));
    int differences = 0;
    for (int i = 0; i < mine.pixels.length; i++) {
      if (mine.pixels[i] != reference.pixels[i]) {
        differences++;
      }
    }
    expect(
      differences,
      0,
      reason: '真实字体下锁定前缀应当与 Text 裁剪到同样字符格子逐像素一致（差异字节：$differences）',
    );
  });
}
