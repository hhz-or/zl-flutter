import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zl/app.dart';
import 'package:flutter_zl/core/storage/key_value_store.dart';
import 'package:flutter_zl/core/theme/app_theme.dart';
import 'package:flutter_zl/core/theme/neon_palette.dart';
import 'package:flutter_zl/core/widgets/neon_button.dart';
import 'package:flutter_zl/data/models/app_settings.dart';
import 'package:flutter_zl/domain/instruction_corpus.dart';
import 'package:flutter_zl/features/generator/widgets/scramble_text.dart';

import 'support/test_app.dart';

/// 启动整个应用（真实入口 `InstructionApp`）。
Future<TestHarness> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  AppSettings settings = AppSettings.defaults,
  TestHarness? harness,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  pinPlatformLocale(tester);

  final resolved = harness ?? TestHarness(settings: settings);
  await resolved.loadAll();
  await tester.pumpWidget(InstructionApp(controllers: resolved.controllers));
  await tester.pump();
  return resolved;
}

ScrambleTextState scrambleState(WidgetTester tester) =>
    tester.state<ScrambleTextState>(find.byType(ScrambleText));

/// 原版最长的一句指令约 40 字，12 字/秒 ≈ 3.4 秒；这里统一多等一会儿。
Future<void> pumpUntilRevealed(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 12));
}

void main() {
  group('1:1 布局', () {
    testWidgets('页面结构与原版一致：logo + 空展示区 + 按钮 + 底部警告', (tester) async {
      await pumpApp(tester);
      final zh = await loadL10n();

      // `.image-header > img`
      expect(find.byType(Image), findsOneWidget);
      // `button#trigger-btn`
      expect(find.text(zh.generateButton), findsOneWidget);
      // `.footer-note`
      expect(find.text(zh.footerWarning), findsOneWidget);
      // 原版首次点击前 `#display-container` 是空的
      expect(find.byType(ScrambleText), findsNothing);
    });

    testWidgets('没有原版之外的界面元素（无导航栏 / 无计数器 / 无操作条）', (tester) async {
      await pumpApp(tester);

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      // 页面上只有两个按钮：设置齿轮 + 获取指令
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('320px / 1280px / 2560px 都不溢出', (tester) async {
      for (final size in <Size>[
        const Size(320, 640),
        const Size(1280, 900),
        const Size(2560, 1440),
      ]) {
        await pumpApp(tester, size: size);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: '尺寸 $size 溢出');
      }
    });
  });

  group('生成指令', () {
    testWidgets('点击按钮后展示「致：」开头的指令，动画播完显示完整正文', (tester) async {
      final harness = await pumpApp(tester);
      final zh = await loadL10n();

      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 32));

      final expected = '${zh.instructionPrefix}${harness.prescriptions.current!.body}';
      expect(harness.prescriptions.current, isNotNull);
      expect(scrambleState(tester).isComplete, isFalse, reason: '此刻应当在播放动画');

      await pumpUntilRevealed(tester);
      expect(scrambleState(tester).isComplete, isTrue);
      expect(scrambleState(tester).currentFrame, expected);
    });

    testWidgets('动画播放期间重复点击会被忽略（复刻原版 isRunning）', (tester) async {
      final harness = await pumpApp(tester);
      final zh = await loadL10n();

      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.prescriptions.generationTick, 1);

      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        harness.prescriptions.generationTick,
        1,
        reason: '原版在 isRunning 为真时直接 return',
      );

      // 动画播完之后按钮恢复可用。
      await pumpUntilRevealed(tester);
      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 32));
      expect(harness.prescriptions.generationTick, 2);
    });

    testWidgets('连续两次抽到同一条指令时动画依然重播', (tester) async {
      final harness = await pumpApp(
        tester,
        harness: TestHarness(
          corpus: const InstructionCorpus(
            scenes: <String>['现在'],
            actions: <String>['去做那件事'],
            supplements: <String>['不要回头'],
            easterEggs: <String>['彩蛋'],
          ),
          settings: const AppSettings(easterEggEnabled: false),
        ),
      );
      final zh = await loadL10n();

      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 32));
      await pumpUntilRevealed(tester);
      expect(scrambleState(tester).isComplete, isTrue);
      final firstBody = harness.prescriptions.current!.body;

      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 32));

      expect(harness.prescriptions.current!.body, firstBody, reason: '内容确实一样');
      expect(harness.prescriptions.generationTick, 2);
      expect(
        scrambleState(tester).isComplete,
        isFalse,
        reason: '文本没变也必须重播',
      );
    });

    testWidgets('底部警告下面有免责声明', (tester) async {
      await pumpApp(tester);
      final zh = await loadL10n();

      expect(find.text(zh.footerWarning), findsOneWidget);
      expect(find.text(zh.footerDisclaimer), findsOneWidget);
    });

    testWidgets('动画期间与播完后的辉光完全一致（不因锁定而变弱）', (tester) async {
      await pumpApp(tester);
      final zh = await loadL10n();

      List<Shadow> shadowsNow() => tester
          .widget<ScrambleText>(find.byType(ScrambleText))
          .style!
          .shadows!;

      await tester.tap(find.text(zh.generateButton));
      await tester.pump(const Duration(milliseconds: 32));

      final during = shadowsNow();
      expect(
        during,
        hasLength(3),
        reason: '动画期间必须是原版的三层 text-shadow，不能为了性能削成一层',
      );

      await tester.pump(const Duration(seconds: 4));
      expect(shadowsNow(), during, reason: '锁定进度不应该影响辉光');
    });

    testWidgets('原版没有全局快捷键：未聚焦任何控件时空格不会生成指令', (tester) async {
      final harness = await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 200));

      expect(harness.prescriptions.current, isNull);
      expect(harness.prescriptions.generationTick, 0);
    });

    testWidgets('按钮可以像原生 <button> 一样用键盘激活', (tester) async {
      final harness = await pumpApp(tester);
      final zh = await loadL10n();

      // 阅读顺序遍历：右上角设置齿轮先获得焦点，再是「获取指令」。
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 32));

      expect(
        harness.prescriptions.generationTick,
        1,
        reason: 'Enter 应当触发按钮，原版是真的 <button>',
      );
      expect(
        find.text(zh.settingsTitle),
        findsNothing,
        reason: '两次 Tab 之后焦点应当在「获取指令」上，而不是设置齿轮',
      );

      // 动画播完后用 Space 再触发一次（原生 button 同样响应空格）。
      await pumpUntilRevealed(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 32));

      expect(harness.prescriptions.generationTick, 2);
    });
  });

  group('设置按钮', () {
    testWidgets('右上角有设置按钮，点击打开设置弹窗', (tester) async {
      await pumpApp(tester);
      final zh = await loadL10n();

      final button = find.byKey(const Key('settings-button'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text(zh.settingsTitle), findsOneWidget);
      expect(find.text(zh.settingsReduceMotion), findsOneWidget);
      expect(find.text(zh.settingsAnimationSpeed), findsOneWidget);
      expect(find.text(zh.settingsEasterEgg), findsOneWidget);
      expect(find.text(zh.settingsEasterEggRate), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();
      expect(find.text(zh.settingsTitle), findsNothing);
    });

    testWidgets('开关写回设置并持久化', (tester) async {
      final harness = await pumpApp(tester);

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-reduce-motion')));
      await tester.pumpAndSettle();

      expect(harness.settingsController.value.reduceMotion, isTrue);
      final raw = harness.store.snapshot[StorageKeys.settings];
      expect(raw, isNotNull);
      expect(
        (jsonDecode(raw!) as Map<String, Object?>)['reduceMotion'],
        isTrue,
      );
    });

    testWidgets('打开「减少动效」后点击按钮立即显示，不播放动画', (tester) async {
      final harness = await pumpApp(
        tester,
        settings: const AppSettings(reduceMotion: true),
      );
      final zh = await loadL10n();

      await tester.tap(find.text(zh.generateButton));
      await tester.pump();

      expect(harness.prescriptions.current, isNotNull);
      expect(scrambleState(tester).isComplete, isTrue);
      expect(
        scrambleState(tester).currentFrame,
        '${zh.instructionPrefix}${harness.prescriptions.current!.body}',
      );
    });

    testWidgets('关闭彩蛋后生成的一定是三段式', (tester) async {
      final harness = await pumpApp(
        tester,
        settings: const AppSettings(
          easterEggEnabled: false,
          reduceMotion: true,
        ),
      );
      final zh = await loadL10n();

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(zh.generateButton));
        await tester.pump();
      }

      expect(harness.prescriptions.current!.isEasterEgg, isFalse);
      expect(harness.prescriptions.generationTick, 5);
    });

    testWidgets('切到 English 后界面文案整体变成英文', (tester) async {
      final harness = await pumpApp(tester);
      final zh = await loadL10n();
      final en = await loadL10n(const Locale('en'));

      expect(find.text(zh.generateButton), findsOneWidget);
      expect(find.text(zh.footerWarning), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-language-en')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-close')));
      await tester.pumpAndSettle();

      expect(harness.settingsController.value.language, AppLanguage.en);
      // 原版 `button { text-transform: uppercase }`，英文标签会被转成大写。
      expect(find.text(en.generateButton.toUpperCase()), findsOneWidget);
      expect(find.text(en.footerWarning), findsOneWidget);
      expect(find.text(zh.generateButton), findsNothing);
    });

    testWidgets('换主题色会即时改变霓虹主色', (tester) async {
      final harness = await pumpApp(tester);
      final scaffold = tester.element(find.byType(Scaffold).first);
      expect(scaffold.neon.accent, NeonPalette.indexBlue.accent);

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-palette-mist_red')));
      await tester.pumpAndSettle();

      expect(harness.settingsController.value.paletteId, 'mist_red');
      expect(scaffold.neon.accent, NeonPalette.mistRed.accent);
    });

    testWidgets('霓虹发光调成 0 后文字完全没有阴影', (tester) async {
      final harness = await pumpApp(
        tester,
        settings: const AppSettings(glowStrength: 0, reduceMotion: true),
      );
      final zh = await loadL10n();

      await tester.tap(find.text(zh.generateButton));
      await tester.pump();

      final scramble = tester.widget<ScrambleText>(
        find.byType(ScrambleText),
      );
      expect(scramble.style?.shadows ?? const <Shadow>[], isEmpty);
      expect(
        tester.element(find.byType(Scaffold).first).neon.glowEnabled,
        isFalse,
      );
      expect(harness.prescriptions.current, isNotNull);
    });

    testWidgets('设置弹窗可以滚到底部的「抽取策略」并切换', (tester) async {
      final harness = await pumpApp(tester);

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();

      final chip = find.byKey(const Key('settings-strategy-shuffle_bag'));
      // 弹窗限高 70% 屏高，抽取策略在折叠线以下，必须先滚动才能点到。
      await tester.scrollUntilVisible(
        chip,
        120,
        scrollable: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(
        harness.settingsController.value.strategy,
        GenerationStrategy.shuffleBag,
      );
      // 恢复默认按钮应当同时变为可用。
      final reset = tester.widget<TextButton>(
        find.byKey(const Key('settings-reset')),
      );
      expect(reset.onPressed, isNotNull);
    });

    testWidgets('按钮的悬停高亮会随指针离开而复原', (tester) async {
      await pumpApp(tester);

      // 读**实际渲染**的装饰，而不是 AnimatedContainer 的目标值：
      // 这里曾经踩过 `BoxShadow.lerpList` 的坑 —— 从「一个阴影」补间到 `null`
      // 时它走的是「多出来的一项」分支，`scale(1.0)` 等于原样保留，于是第一次
      // 悬停之后那圈发光永远不会消失。只有读渲染值才测得到。
      BoxDecoration rendered() =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(NeonButton),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      Color shadowColor() => rendered().boxShadow!.single.color;

      expect(rendered().color, Colors.transparent, reason: '初始为透明底');
      expect(shadowColor().a, 0, reason: '初始不该有可见投影');

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(NeonButton)));
      await tester.pumpAndSettle();
      expect(rendered().color, Colors.white, reason: '悬停时反白');
      expect(shadowColor().a, 1, reason: '悬停时点亮投影');

      await gesture.moveTo(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(rendered().color, Colors.transparent, reason: '移开后必须复原');
      expect(
        shadowColor().a,
        0,
        reason: '移开后投影必须真的消失（不能被 lerp 留住）',
      );
    });

    testWidgets('洗牌袋策略下连续生成不会重复', (tester) async {
      final harness = await pumpApp(
        tester,
        settings: const AppSettings(
          reduceMotion: true,
          easterEggEnabled: false,
          strategy: GenerationStrategy.shuffleBag,
        ),
      );
      final zh = await loadL10n();

      final seen = <String>{};
      for (var i = 0; i < 27; i++) {
        await tester.tap(find.text(zh.generateButton));
        await tester.pump();
        seen.add(harness.prescriptions.current!.scene!);
      }

      expect(seen, hasLength(27), reason: '一轮之内 27 个场景句不应重复');
    });
  });
}
