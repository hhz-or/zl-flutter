import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zl/data/instruction_corpus_data.dart';
import 'package:flutter_zl/data/models/app_settings.dart';
import 'package:flutter_zl/data/models/instruction.dart';
import 'package:flutter_zl/domain/instruction_corpus.dart';
import 'package:flutter_zl/state/prescription_controller.dart';

/// 只有一组句子的语料：每次生成的内容都完全相同。
const InstructionCorpus kTinyCorpus = InstructionCorpus(
  scenes: <String>['现在'],
  actions: <String>['去做那件事'],
  supplements: <String>['不要回头'],
  easterEggs: <String>['不要去执行任何所谓的指令。'],
);

PrescriptionController build({
  InstructionCorpus corpus = kBuiltinCorpus,
  AppSettings settings = const AppSettings(easterEggEnabled: false),
  int seed = 7,
}) {
  return PrescriptionController(
    corpus: corpus,
    settings: settings,
    random: Random(seed),
  );
}

void main() {
  group('初始状态', () {
    test('首次生成之前没有当前指令，tick 为 0', () {
      final controller = build();
      expect(controller.current, isNull);
      expect(controller.generationTick, 0);
      expect(controller.corpus, same(kBuiltinCorpus));
    });
  });

  group('generate', () {
    test('生成后 current 指向同一条指令并自增 tick', () {
      final controller = build();

      final instruction = controller.generate();

      expect(controller.current, same(instruction));
      expect(instruction.body, isNotEmpty);
      expect(instruction.kind, InstructionKind.assembled);
      expect(instruction.scene, isNotNull);
      expect(instruction.action, isNotNull);
      expect(instruction.supplement, isNotNull);
      expect(controller.generationTick, 1);
    });

    test('每次生成都会通知监听者一次', () {
      final controller = build();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.generate();
      controller.generate();
      controller.generate();

      expect(notified, 3);
      expect(controller.generationTick, 3);
    });

    test('相同种子 → 完全相同的序列', () {
      final a = build(seed: 42);
      final b = build(seed: 42);

      for (var i = 0; i < 25; i++) {
        expect(a.generate(), b.generate());
      }
    });

    test('关闭彩蛋后永远只出三段式', () {
      final controller = build(
        settings: const AppSettings(easterEggEnabled: false),
      );

      for (var i = 0; i < 300; i++) {
        expect(controller.generate().isEasterEgg, isFalse);
      }
    });

    test('概率为 1 时永远出彩蛋', () {
      final controller = build(
        settings: const AppSettings(
          easterEggEnabled: true,
          easterEggRate: 1,
        ),
      );

      for (var i = 0; i < 300; i++) {
        expect(controller.generate().isEasterEgg, isTrue);
      }
    });

    test('空语料下生成不会抛出', () {
      final controller = build(
        corpus: const InstructionCorpus.empty(),
        settings: const AppSettings(
          easterEggEnabled: true,
          easterEggRate: 1,
        ),
      );

      final instruction = controller.generate();

      expect(instruction.body, isEmpty);
    });

    test('语料统计可透传（用于文档/自检）', () {
      final controller = build();
      expect(controller.corpus.scenes, hasLength(27));
      expect(controller.corpus.actions, hasLength(62));
      expect(controller.corpus.supplements, hasLength(18));
      expect(controller.corpus.easterEggs, hasLength(23));
      expect(controller.corpus.combinationCount, 27 * 62 * 18);
    });
  });

  group('applySettings', () {
    test('关闭彩蛋立即生效', () {
      final controller = build(
        settings: const AppSettings(
          easterEggEnabled: true,
          easterEggRate: 1,
        ),
      );
      expect(controller.generate().isEasterEgg, isTrue);

      controller.applySettings(
        const AppSettings(easterEggEnabled: false, easterEggRate: 1),
      );

      for (var i = 0; i < 50; i++) {
        expect(controller.generate().isEasterEgg, isFalse);
      }
    });

    test('概率归零立即生效', () {
      final controller = build(
        settings: const AppSettings(
          easterEggEnabled: true,
          easterEggRate: 1,
        ),
      );

      controller.applySettings(
        const AppSettings(easterEggEnabled: true, easterEggRate: 0),
      );

      for (var i = 0; i < 50; i++) {
        expect(controller.generate().isEasterEgg, isFalse);
      }
    });

    test('切换语料立即生效', () {
      final controller = build();
      controller.applySettings(const AppSettings(easterEggEnabled: false));

      controller.applySettings(
        const AppSettings(easterEggEnabled: false),
      );

      expect(controller.settings.easterEggEnabled, isFalse);
      expect(controller.generate().body, isNotEmpty);
    });
  });
}
