// 指令生成器与设置模型的单元测试。
//
// 生成算法是原版 `script.js` 按钮回调的逐行复刻：**纯随机、允许重复**，
// 没有洗牌袋、没有历史去重、没有 id 与时间戳。这里用可注入的随机源把每一
// 条语义都钉死——包括用第二个同种子 `Random` 独立复算原版公式，这是最强
// 的保真度检查，因为任何多余的取数都会让两条序列错位。

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_zl/data/instruction_corpus_data.dart';
import 'package:flutter_zl/data/models/app_settings.dart';
import 'package:flutter_zl/data/models/instruction.dart';
import 'package:flutter_zl/domain/instruction_corpus.dart';
import 'package:flutter_zl/domain/instruction_generator.dart';

/// 原版 `script.js` 硬编码的彩蛋概率：`Math.random() < 0.15`。
const double _kOriginalRate = AppSettings.originalEasterEggRate;

/// 二项分布的正态近似 99% 置信区间半宽：`z * sqrt(p(1-p)/n)`，z = 2.5758。
///
/// n = 20000、p = 0.15 时约等于 0.0065；n = 6000、p = 0.5 时约等于 0.0166。
double _halfWidth99(double p, int n) =>
    2.5758293035489004 * sqrt(p * (1 - p) / n);

/// 按原版公式独立复算「下一条指令」。
///
/// 取数顺序严格对应 `script.js`：
/// 1. `if (Math.random() < 0.15)` —— 每次**都会**先消耗一次 `nextDouble()`；
/// 2. 命中 → `easterEggs[floor(random() * length)]`，只再取一次；
/// 3. 未命中 → 依次取 场景 / 行为 / 补充。
///
/// 原版用 `arr[Math.floor(Math.random() * arr.length)]`，移植版换成
/// `arr[nextInt(arr.length)]`（均匀且无模偏置），所以复算也必须用 `nextInt`。
/// 因此这条复算校验的是「取数次数、顺序与下标完全一致」，而不是 JS 引擎的
/// 具体随机位——后者本来也无法跨语言复现。
///
/// 仅适用于 `easterEggEnabled == true` 且彩蛋非空的语料。
Instruction _replayOriginal(InstructionCorpus corpus, Random random, double rate) {
  if (random.nextDouble() < rate) {
    return Instruction.easterEgg(
      text: corpus.easterEggs[random.nextInt(corpus.easterEggs.length)],
    );
  }
  return Instruction.assembled(
    scene: corpus.scenes[random.nextInt(corpus.scenes.length)],
    action: corpus.actions[random.nextInt(corpus.actions.length)],
    supplement: corpus.supplements[random.nextInt(corpus.supplements.length)],
  );
}

/// 统计 [InstructionKind.easterEgg] 的条数，并收集三段式指令的片段。
({int eggs, Set<String> scenes, Set<String> actions, Set<String> supplements})
    _sample(InstructionGenerator generator, int draws) {
  final Set<String> scenes = <String>{};
  final Set<String> actions = <String>{};
  final Set<String> supplements = <String>{};
  var eggs = 0;
  for (var i = 0; i < draws; i++) {
    final Instruction instruction = generator.generate();
    if (instruction.isEasterEgg) {
      eggs++;
      continue;
    }
    scenes.add(instruction.scene!);
    actions.add(instruction.action!);
    supplements.add(instruction.supplement!);
  }
  return (
    eggs: eggs,
    scenes: scenes,
    actions: actions,
    supplements: supplements,
  );
}

void main() {
  group('随机源可复现', () {
    test('相同种子的两个生成器产生逐条相同的序列', () {
      final InstructionGenerator a = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(20261004),
      );
      final InstructionGenerator b = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(20261004),
      );
      final List<String> bodiesA = <String>[];
      final List<String> bodiesB = <String>[];
      for (var i = 0; i < 200; i++) {
        final Instruction instructionA = a.generate();
        final Instruction instructionB = b.generate();
        expect(instructionA, instructionB, reason: '第 $i 条应当完全相同');
        bodiesA.add(instructionA.body);
        bodiesB.add(instructionB.body);
      }
      expect(bodiesA, equals(bodiesB));
      expect(bodiesA.toSet().length, greaterThan(100), reason: '纯随机不该退化成固定句');
    });

    test('不同种子的序列不同', () {
      final InstructionGenerator a = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(42),
        easterEggEnabled: false,
      );
      final InstructionGenerator b = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(43),
        easterEggEnabled: false,
      );
      final List<String> bodiesA = <String>[
        for (var i = 0; i < 60; i++) a.generate().body,
      ];
      final List<String> bodiesB = <String>[
        for (var i = 0; i < 60; i++) b.generate().body,
      ];
      expect(bodiesA, isNot(equals(bodiesB)));
    });
  });

  group('复刻原版公式（独立复算）', () {
    test('2000 条指令与原版公式的独立复算逐条一致', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(20261004),
      );
      final Random replay = Random(20261004);
      var eggs = 0;
      for (var i = 0; i < 2000; i++) {
        final Instruction expected = _replayOriginal(
          kBuiltinCorpus,
          replay,
          _kOriginalRate,
        );
        final Instruction actual = generator.generate();
        expect(actual.kind, expected.kind, reason: '第 $i 条的分支应当一致');
        expect(actual.segments, expected.segments, reason: '第 $i 条的片段应当一致');
        expect(actual.body, expected.body, reason: '第 $i 条的正文应当一致');
        if (actual.isEasterEgg) {
          eggs++;
        }
      }
      expect(eggs, greaterThan(0), reason: '这条随机流应当覆盖彩蛋分支');
      expect(eggs, lessThan(2000), reason: '这条随机流应当覆盖三段式分支');
    });

    test('概率为 0 与 1 时复算同样成立', () {
      for (final double rate in <double>[0, 1]) {
        final InstructionGenerator generator = InstructionGenerator(
          corpus: kBuiltinCorpus,
          random: Random(7777),
          easterEggRate: rate,
        );
        final Random replay = Random(7777);
        for (var i = 0; i < 200; i++) {
          expect(
            generator.generate().body,
            _replayOriginal(kBuiltinCorpus, replay, rate).body,
            reason: '第 $i 条（rate=$rate）',
          );
        }
      }
    });

    test('easterEggEnabled: false 时不掷彩蛋骰，RNG 只用于三段取值', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(99),
        easterEggEnabled: false,
      );
      final Random replay = Random(99);
      for (var i = 0; i < 200; i++) {
        final Instruction expected = Instruction.assembled(
          scene: kBuiltinCorpus.scenes[replay.nextInt(kBuiltinCorpus.scenes.length)],
          action:
              kBuiltinCorpus.actions[replay.nextInt(kBuiltinCorpus.actions.length)],
          supplement: kBuiltinCorpus
              .supplements[replay.nextInt(kBuiltinCorpus.supplements.length)],
        );
        expect(generator.generate().body, expected.body, reason: '第 $i 条');
      }
    });

    test('语料没有彩蛋时也不掷彩蛋骰（短路顺序与原版一致）', () {
      final InstructionCorpus noEggs = kBuiltinCorpus.copyWith(
        easterEggs: const <String>[],
      );
      final InstructionGenerator generator = InstructionGenerator(
        corpus: noEggs,
        random: Random(2026),
        easterEggRate: 1,
        easterEggEnabled: true,
      );
      final Random replay = Random(2026);
      for (var i = 0; i < 100; i++) {
        final Instruction expected = Instruction.assembled(
          scene: noEggs.scenes[replay.nextInt(noEggs.scenes.length)],
          action: noEggs.actions[replay.nextInt(noEggs.actions.length)],
          supplement: noEggs.supplements[replay.nextInt(noEggs.supplements.length)],
        );
        final Instruction actual = generator.generate();
        expect(actual.kind, InstructionKind.assembled, reason: '第 $i 条');
        expect(actual.body, expected.body, reason: '第 $i 条');
      }
    });
  });

  group('正文与片段', () {
    test('正文没有分隔符：body 恒等于 segments 直接拼接', () {
      for (final double rate in <double>[0, 1]) {
        final InstructionGenerator generator = InstructionGenerator(
          corpus: kBuiltinCorpus,
          random: Random(5),
          easterEggRate: rate,
        );
        for (var i = 0; i < 200; i++) {
          final Instruction instruction = generator.generate();
          expect(
            instruction.body,
            instruction.segments.join(),
            reason: 'rate=$rate 第 $i 条',
          );
          if (instruction.isAssembled) {
            expect(instruction.segments, hasLength(3));
            expect(
              instruction.body,
              '${instruction.scene}${instruction.action}${instruction.supplement}',
              reason: '原版就是把「致：」+ 场景 + 行为 + 补充直接相加，中间没有任何字符',
            );
            expect(instruction.body, startsWith(instruction.scene!));
            expect(instruction.body, endsWith(instruction.supplement!));
          } else {
            expect(instruction.segments, hasLength(1));
            expect(instruction.body, instruction.segments.single);
            expect(kBuiltinCorpus.easterEggs, contains(instruction.body));
          }
        }
      }
    });

    test('三段式的三个片段都是语料原句', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(8),
        easterEggRate: 0,
      );
      for (var i = 0; i < 300; i++) {
        final Instruction instruction = generator.generate();
        expect(kBuiltinCorpus.scenes, contains(instruction.scene));
        expect(kBuiltinCorpus.actions, contains(instruction.action));
        expect(kBuiltinCorpus.supplements, contains(instruction.supplement));
      }
    });
  });

  group('彩蛋开关与概率', () {
    test('easterEggEnabled: false 时 3000 次零彩蛋', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(7),
        easterEggEnabled: false,
      );
      var eggs = 0;
      for (var i = 0; i < 3000; i++) {
        if (generator.generate().kind == InstructionKind.easterEgg) {
          eggs++;
        }
      }
      expect(eggs, 0);
    });

    test('easterEggRate: 1 时每一条都是彩蛋，且都来自语料', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(11),
        easterEggRate: 1,
      );
      final Set<String> eggs = <String>{};
      for (var i = 0; i < 500; i++) {
        final Instruction instruction = generator.generate();
        expect(instruction.kind, InstructionKind.easterEgg);
        expect(instruction.segments, hasLength(1));
        expect(kBuiltinCorpus.easterEggs, contains(instruction.body));
        eggs.add(instruction.body);
      }
      expect(eggs, hasLength(23), reason: '500 次足以覆盖全部 23 条彩蛋');
    });

    test('easterEggRate: 0 时全是三段式且三段齐全', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(3),
        easterEggRate: 0,
      );
      for (var i = 0; i < 500; i++) {
        final Instruction instruction = generator.generate();
        expect(instruction.kind, InstructionKind.assembled);
        expect(instruction.isAssembled, isTrue);
        expect(instruction.isEasterEgg, isFalse);
        expect(instruction.scene, isNotNull);
        expect(instruction.action, isNotNull);
        expect(instruction.supplement, isNotNull);
      }
    });

    test('构造时越界的概率被夹到 0~1', () {
      final InstructionGenerator low = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(5),
        easterEggRate: -3,
      );
      final InstructionGenerator high = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(5),
        easterEggRate: 9,
      );
      expect(low.easterEggRate, 0);
      expect(high.easterEggRate, 1);
      expect(low.generate().kind, InstructionKind.assembled);
      expect(high.generate().kind, InstructionKind.easterEgg);
      expect(
        InstructionGenerator(corpus: kBuiltinCorpus).easterEggRate,
        _kOriginalRate,
        reason: '默认概率就是原版的 0.15',
      );
      expect(
        InstructionGenerator(corpus: kBuiltinCorpus).easterEggEnabled,
        isTrue,
        reason: '原版固定参与彩蛋抽取',
      );
    });
  });

  group('统计与覆盖（20000 条）', () {
    test('默认 0.15 的观测频率落在 99% 置信区间内，抽到的句子都来自语料', () {
      // 二项分布的正态近似：n = 20000、p = 0.15 时
      // 99% 置信区间半宽 = 2.5758 × sqrt(0.15 × 0.85 / 20000) ≈ 0.0065。
      // 随机源固定，所以这条断言是确定性的：实现若把概率写成别的值，
      // 观测频率会远远落在区间之外。
      const int draws = 20000;
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(20261004),
      );
      final Stopwatch stopwatch = Stopwatch()..start();
      final ({int eggs, Set<String> scenes, Set<String> actions, Set<String> supplements})
          sample = _sample(generator, draws);
      stopwatch.stop();
      final double observed = sample.eggs / draws;

      expect(
        observed,
        closeTo(_kOriginalRate, _halfWidth99(_kOriginalRate, draws)),
        reason: '观测到 ${sample.eggs}/$draws，99% 置信区间半宽约 0.0065',
      );
      expect(
        (observed - _kOriginalRate).abs(),
        lessThan(0.0066),
        reason: '99% 置信区间半宽约 0.0065',
      );
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: '统计测试必须保持轻快（实测仅数十毫秒）',
      );

      // 抽到的每一句都必须是语料原句，且 20000 次足以覆盖全部条目。
      expect(sample.scenes.difference(kBuiltinCorpus.scenes.toSet()), isEmpty);
      expect(sample.actions.difference(kBuiltinCorpus.actions.toSet()), isEmpty);
      expect(
        sample.supplements.difference(kBuiltinCorpus.supplements.toSet()),
        isEmpty,
      );
      expect(sample.scenes, hasLength(27));
      expect(sample.actions, hasLength(62));
      expect(sample.supplements, hasLength(18));
    });
  });

  group('空语料与残缺语料（优雅退化）', () {
    test('空语料：generate() 不抛异常，概率为 1 时返回空正文', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: const InstructionCorpus.empty(),
        random: Random(1),
        easterEggRate: 1,
        easterEggEnabled: true,
      );
      expect(generator.generate, returnsNormally);
      final Instruction instruction = generator.generate();
      expect(instruction.kind, InstructionKind.easterEgg);
      expect(instruction.body, isEmpty);
      expect(instruction.length, 0);
      expect(
        instruction.segments,
        <String>[''],
        reason: '退化路径是 Instruction.easterEgg(text: "")，判据是正文为空',
      );
      expect(generator.generate().body, isEmpty, reason: '反复调用同样安全');
    });

    test('空语料在概率为 0 时也不抛异常', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: const InstructionCorpus.empty(),
        random: Random(2),
        easterEggRate: 0,
      );
      expect(generator.generate, returnsNormally);
      expect(generator.generate().body, isEmpty);
    });

    test('只剩行为句的残缺语料退化为语料里的第一条彩蛋', () {
      final InstructionCorpus partial = kBuiltinCorpus.copyWith(
        scenes: const <String>[],
        supplements: const <String>[],
      );
      expect(partial.canAssemble, isFalse);
      final Instruction instruction = InstructionGenerator(
        corpus: partial,
        random: Random(6),
        easterEggRate: 0,
      ).generate();
      expect(instruction.kind, InstructionKind.easterEgg);
      expect(instruction.body, kBuiltinCorpus.easterEggs.first);
      expect(instruction.body, '不念完自然常数e就不要回家。');
    });

    test('既不能拼装又没有彩蛋时退化为空正文', () {
      const InstructionCorpus broken = InstructionCorpus(
        scenes: <String>['甲'],
        actions: <String>[],
        supplements: <String>[],
        easterEggs: <String>[],
      );
      expect(broken.canAssemble, isFalse);
      expect(broken.canPickEasterEgg, isFalse);
      final InstructionGenerator generator = InstructionGenerator(
        corpus: broken,
        random: Random(6),
        easterEggRate: 1,
      );
      expect(generator.generate, returnsNormally);
      expect(generator.generate().body, isEmpty);
    });
  });

  group('configure 热更新', () {
    test('关闭彩蛋后立刻生效', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(21),
      );
      expect(generator.easterEggEnabled, isTrue);
      final List<Instruction> before = <Instruction>[
        for (var i = 0; i < 200; i++) generator.generate(),
      ];
      expect(
        before.where((Instruction item) => item.isEasterEgg),
        isNotEmpty,
        reason: '默认 0.15 下 200 条里应当出现彩蛋',
      );

      generator.configure(easterEggEnabled: false);
      expect(generator.easterEggEnabled, isFalse);
      for (var i = 0; i < 1000; i++) {
        expect(generator.generate().kind, InstructionKind.assembled);
      }
    });

    test('改概率后立刻生效', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(22),
      );
      generator.configure(easterEggRate: 0.5);
      expect(generator.easterEggRate, 0.5);

      const int draws = 6000;
      final int eggs = _sample(generator, draws).eggs;
      final double observed = eggs / draws;
      // n = 6000、p = 0.5 时 99% 置信区间半宽约 0.0166。
      expect(
        observed,
        closeTo(0.5, _halfWidth99(0.5, draws)),
        reason: '观测到 $eggs/$draws，应当明显高于原来的 0.15',
      );
      expect(observed, greaterThan(0.4));
    });

    test('configure 传入的越界概率同样被夹紧', () {
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(23),
      );
      generator.configure(easterEggRate: -1);
      expect(generator.easterEggRate, 0);
      generator.configure(easterEggRate: 4);
      expect(generator.easterEggRate, 1);
      generator.configure(easterEggRate: double.infinity);
      expect(generator.easterEggRate, 1);
      generator.configure(easterEggRate: double.negativeInfinity);
      expect(generator.easterEggRate, 0);
    });

    test('换语料后立刻使用新语料，旧句子不再出现', () {
      const InstructionCorpus custom = InstructionCorpus(
        scenes: <String>['甲情景'],
        actions: <String>['乙行为'],
        supplements: <String>['丙补充'],
        easterEggs: <String>['丁彩蛋'],
      );
      final InstructionGenerator generator = InstructionGenerator(
        corpus: kBuiltinCorpus,
        random: Random(31),
        easterEggRate: 0,
      );
      expect(generator.corpus, same(kBuiltinCorpus));

      generator.configure(corpus: custom);
      expect(generator.corpus, same(custom));
      expect(generator.corpus.combinationCount, 1);
      for (var i = 0; i < 50; i++) {
        final Instruction instruction = generator.generate();
        expect(instruction.body, '甲情景乙行为丙补充');
        expect(instruction.scene, '甲情景');
        expect(instruction.action, '乙行为');
        expect(instruction.supplement, '丙补充');
      }

      // 只改一个组也要立刻生效。
      generator.configure(
        corpus: custom.copyWith(easterEggs: const <String>['戊彩蛋']),
        easterEggRate: 1,
      );
      for (var i = 0; i < 20; i++) {
        expect(generator.generate().body, '戊彩蛋');
      }
    });
  });

  group('Instruction 值语义', () {
    test('相等性只看 kind + segments，与生成路径无关', () {
      final Instruction factory = Instruction.assembled(
        scene: '甲',
        action: '乙',
        supplement: '丙',
      );
      const Instruction direct = Instruction(
        segments: <String>['甲', '乙', '丙'],
        kind: InstructionKind.assembled,
      );
      expect(factory, direct);
      expect(factory.hashCode, direct.hashCode);
      expect(factory.body, '甲乙丙');

      // 正文一样但 kind 不同 → 不相等（没有基于正文的 id 去重）。
      final Instruction egg = Instruction.easterEgg(text: '甲乙丙');
      expect(egg.body, factory.body);
      expect(egg == factory, isFalse);
      expect(egg.segments, <String>['甲乙丙']);
      expect(egg.isEasterEgg, isTrue);
      expect(egg.isAssembled, isFalse);
    });

    test('assembled 始终保留三个槽位，空片段不会让访问器错位', () {
      final Instruction instruction = Instruction.assembled(
        scene: 'A',
        action: '',
        supplement: 'C',
      );
      expect(instruction.segments, <String>['A', '', 'C']);
      expect(instruction.body, 'AC', reason: '空片段不贡献字符');
      expect(instruction.length, 2);
      expect(instruction.scene, 'A');
      expect(instruction.action, isEmpty);
      expect(instruction.supplement, 'C');
    });

    test('空片段列表（assembled）与单空串（easterEgg）是两种不同的空', () {
      final Instruction assembled = Instruction.assembled(
        scene: '',
        action: '',
        supplement: '',
      );
      final Instruction egg = Instruction.easterEgg(text: '');
      expect(assembled.segments, <String>['', '', '']);
      expect(egg.segments, <String>['']);
      expect(assembled.body, isEmpty);
      expect(egg.body, isEmpty);
      expect(assembled.length, 0);
      expect(egg.length, 0);
      expect(assembled == egg, isFalse);
      expect(egg.scene, isNull);
      expect(assembled.scene, isEmpty);
    });

    test('toString 只暴露 kind 与正文', () {
      expect(Instruction.easterEgg(text: '关闭屏幕').toString(), contains('关闭屏幕'));
      expect(Instruction.easterEgg(text: '关闭屏幕').toString(), contains('easterEgg'));
      expect(
        Instruction.assembled(scene: '甲', action: '乙', supplement: '丙').toString(),
        contains('甲乙丙'),
      );
    });
  });

  group('AppSettings（只剩四项，默认值即原版行为）', () {
    test('默认值与原版一致', () {
      const AppSettings defaults = AppSettings.defaults;
      expect(defaults.reduceMotion, isFalse);
      expect(defaults.animationSpeed, 1.0);
      expect(defaults.easterEggEnabled, isTrue);
      expect(defaults.easterEggRate, 0.15);
      expect(AppSettings.originalEasterEggRate, 0.15);
      expect(const AppSettings(), defaults);
      expect(const AppSettings().hashCode, defaults.hashCode);
    });

    test('toJson 恰好八个键', () {
      expect(
        AppSettings.defaults.toJson().keys.toSet(),
        <String>{
          'accentColor',
          'language',
          'glowStrength',
          'reduceMotion',
          'animationSpeed',
          'easterEggEnabled',
          'easterEggRate',
          'strategy',
        },
        reason: '不该再出现 historyLimit / themeMode / autoCopy 等已删除的键',
      );
    });

    test('toJson / fromJson 往返一致', () {
      final AppSettings custom = AppSettings.defaults.copyWith(
        reduceMotion: true,
        animationSpeed: 2.5,
        easterEggEnabled: false,
        easterEggRate: 0.6,
      );
      expect(AppSettings.fromJson(custom.toJson()), custom);
      expect(AppSettings.fromJson(custom.toJson()).hashCode, custom.hashCode);
      expect(
        AppSettings.fromJson(AppSettings.defaults.toJson()),
        AppSettings.defaults,
      );
    });

    test('空 map 与未知键都回退到 defaults', () {
      expect(AppSettings.fromJson(const <String, Object?>{}), AppSettings.defaults);
      expect(
        AppSettings.fromJson(const <String, Object?>{
          // 已删除的键 + 未来才会有的键，都必须被当作不存在。
          'historyLimit': 100,
          'themeMode': 'light',
          'glowEnabled': false,
          'autoCopy': true,
          'hapticsEnabled': false,
          'showSegments': true,
          '未来才有的键': <Object?>[1, 2, 3],
        }),
        AppSettings.defaults,
      );
    });

    test('合法键被正确解析（含枚举与主题色）', () {
      final AppSettings parsed = AppSettings.fromJson(const <String, Object?>{
        'accentColor': 0xFF7C3AED,
        'language': 'en',
        'glowStrength': 0.4,
        'strategy': 'shuffleBag',
      });
      expect(parsed.accentColor, 0xFF7C3AED);
      expect(parsed.language, AppLanguage.en);
      expect(parsed.glowStrength, 0.4);
      expect(parsed.strategy, GenerationStrategy.shuffleBag);
    });

    test('未知枚举值与损坏的颜色逐字段回退', () {
      final AppSettings parsed = AppSettings.fromJson(const <String, Object?>{
        'language': 'klingon',
        'strategy': 'whatever',
        'accentColor': 'not a colour',
      });
      expect(parsed.language, AppSettings.defaults.language);
      expect(parsed.strategy, AppSettings.defaults.strategy);
      expect(parsed.accentColor, AppSettings.defaultAccentColor);
    });

    test('越界数值被夹紧到合法区间', () {
      final AppSettings low = AppSettings.fromJson(const <String, Object?>{
        'animationSpeed': -100,
        'easterEggRate': -1,
      });
      expect(low.animationSpeed, 0.25);
      expect(low.easterEggRate, 0.0);

      final AppSettings high = AppSettings.fromJson(const <String, Object?>{
        'animationSpeed': 99,
        'easterEggRate': 5,
      });
      expect(high.animationSpeed, 3.0);
      expect(high.easterEggRate, 1.0);

      // 边界值本身必须原样保留。
      expect(
        AppSettings.fromJson(
          const <String, Object?>{'animationSpeed': 0.25},
        ).animationSpeed,
        0.25,
      );
      expect(
        AppSettings.fromJson(const <String, Object?>{'animationSpeed': 3})
            .animationSpeed,
        3.0,
      );
    });

    test('animationSpeed: 1e400（Infinity）不抛异常，且不影响其他字段', () {
      // `1e400` 是合法 JSON，`jsonDecode` 会得到 `Infinity`；而 `double.clamp`
      // 遇到非有限值会抛 UnsupportedError —— 这正是修过的 bug，见 fromJson 里的
      // `isFinite` 检查。
      final Map<String, Object?> decoded = Map<String, Object?>.from(
        jsonDecode(
          '{"animationSpeed": 1e400, "reduceMotion": true, '
          '"easterEggEnabled": false, "easterEggRate": 0.4}',
        ) as Map<String, Object?>,
      );
      expect(decoded['animationSpeed'], double.infinity);

      final AppSettings settings = AppSettings.fromJson(decoded);
      expect(
        settings.animationSpeed,
        AppSettings.defaults.animationSpeed,
        reason: 'Infinity 不是合法数值，该字段单独回退默认值',
      );
      expect(settings.reduceMotion, isTrue, reason: '其余字段必须原样保留');
      expect(settings.easterEggEnabled, isFalse);
      expect(settings.easterEggRate, 0.4);

      // 直接写在 Dart 里的字面量（同样溢出为 Infinity）也不能炸。
      expect(
        AppSettings.fromJson(const <String, Object?>{'animationSpeed': 1e400})
            .animationSpeed,
        1.0,
      );
      // 各种非有限值统一回退，而不是夹紧。
      expect(
        AppSettings.fromJson(
          const <String, Object?>{'animationSpeed': double.infinity},
        ).animationSpeed,
        1.0,
      );
      expect(
        AppSettings.fromJson(
          const <String, Object?>{'easterEggRate': double.negativeInfinity},
        ).easterEggRate,
        0.15,
      );
      expect(
        AppSettings.fromJson(
          const <String, Object?>{'easterEggRate': double.nan},
        ).easterEggRate,
        0.15,
      );
    });

    test('垃圾类型逐字段回退，不影响同级字段', () {
      final AppSettings settings = AppSettings.fromJson(const <String, Object?>{
        'reduceMotion': 'yes',
        'animationSpeed': 'fast',
        'easterEggEnabled': 1,
        'easterEggRate': null,
      });
      expect(settings, AppSettings.defaults);
      expect(settings.reduceMotion, isFalse);
      expect(settings.animationSpeed, 1.0);
      expect(settings.easterEggEnabled, isTrue, reason: '数字 1 不是 bool，回退默认');
      expect(settings.easterEggRate, 0.15);
      expect(settings.toJson().keys, hasLength(8), reason: '写回的键固定为八个');
    });

    test('copyWith 只改传入的字段', () {
      final AppSettings base = AppSettings.defaults.copyWith(easterEggRate: 0.5);
      expect(base.easterEggRate, 0.5);
      expect(base.reduceMotion, isFalse);
      expect(base.animationSpeed, 1.0);
      expect(base.easterEggEnabled, isTrue);
      expect(base.copyWith(), base);
      expect(base.copyWith(easterEggRate: 0).easterEggRate, 0.0);
    });
  });
}
