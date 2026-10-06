// 内置语料库的「忠实度」测试。
//
// 期望值全部从原版 `指令/script.js` 现场数出：四组共 130 条句子（27 / 62 /
// 18 / 23），逐字与源文件一致；字符码点总数也是按源文件独立复算的（533 个）。
//
// 本项目是复刻，语料属于「内容」而非「代码」——包括其中荒诞、黑色幽默
// 与不友善的部分。这些断言存在的意义就是拦住后来者的「顺手改进」：
// 不允许归一化、脱敏、去重、翻译，也不允许增删任何一条。
//
// 正文前缀「致：」不属于语料，它是展示层文案（`lib/l10n/app_zh.arb`），
// 因此不在这里的码点统计内。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_zl/data/instruction_corpus_data.dart';
import 'package:flutter_zl/domain/instruction_corpus.dart';

/// 四组语料及其在源文件里的名字，顺序与 `script.js` 一致。
final Map<String, List<String>> _kGroups = <String, List<String>>{
  'scenes（场景限定句）': kBuiltinCorpus.scenes,
  'actions（核心行为句）': kBuiltinCorpus.actions,
  'supplements（补充要求句）': kBuiltinCorpus.supplements,
  'easterEggs（彩蛋）': kBuiltinCorpus.easterEggs,
};

/// 独立复算：四组语料里出现过的每一个码点（不含正文前缀）。
Set<int> _corpusOnlyCodePoints() {
  final Set<int> codePoints = <int>{};
  for (final List<String> group in _kGroups.values) {
    for (final String sentence in group) {
      codePoints.addAll(sentence.runes);
    }
  }
  return codePoints;
}

void main() {
  group('kBuiltinCorpus 结构与计数', () {
    test('四组数量与源文件完全一致', () {
      expect(kBuiltinCorpus.scenes, hasLength(27));
      expect(kBuiltinCorpus.actions, hasLength(62));
      expect(kBuiltinCorpus.supplements, hasLength(18));
      expect(kBuiltinCorpus.easterEggs, hasLength(23));
    });

    test('totalSentences 与 combinationCount 由四组长度推出', () {
      expect(kBuiltinCorpus.totalSentences, 27 + 62 + 18 + 23);
      expect(kBuiltinCorpus.totalSentences, 130);
      expect(
        kBuiltinCorpus.combinationCount,
        kBuiltinCorpus.scenes.length *
            kBuiltinCorpus.actions.length *
            kBuiltinCorpus.supplements.length,
        reason: '组合数只是三段式笛卡尔积（允许重复，与生成算法无关）',
      );
      expect(kBuiltinCorpus.combinationCount, 27 * 62 * 18);
      expect(kBuiltinCorpus.combinationCount, 30132);
    });

    test('canAssemble / canPickEasterEgg / isEmpty', () {
      expect(kBuiltinCorpus.canAssemble, isTrue);
      expect(kBuiltinCorpus.canPickEasterEgg, isTrue);
      expect(kBuiltinCorpus.isEmpty, isFalse);

      expect(const InstructionCorpus.empty().canAssemble, isFalse);
      expect(const InstructionCorpus.empty().canPickEasterEgg, isFalse);
      expect(const InstructionCorpus.empty().isEmpty, isTrue);
      expect(const InstructionCorpus.empty().combinationCount, 0);
      expect(const InstructionCorpus.empty().totalSentences, 0);

      // 缺任何一组都无法拼装；但只要有彩蛋就仍可用。
      final InstructionCorpus partial = kBuiltinCorpus.copyWith(
        actions: const <String>[],
      );
      expect(partial.canAssemble, isFalse);
      expect(partial.canPickEasterEgg, isTrue);
      expect(partial.isEmpty, isFalse);
    });

    test('正文前缀由 ARB 提供，与原版网页一致', () {
      // 前缀不再是 Dart 常量（避免与 app_zh.arb 重复硬编码），
      // 但没有前缀就不会显示「致：」，所以这里守住 ARB 里的那一份。
      const String arb = 'lib/l10n/app_zh.arb';
      expect(File(arb).existsSync(), isTrue);
      expect(File(arb).readAsStringSync(), contains('"instructionPrefix": "致："'));
    });
  });

  group('逐字忠实度', () {
    test('没有空句子，也没有首尾空白', () {
      var empty = 0;
      var padded = 0;
      for (final MapEntry<String, List<String>> entry in _kGroups.entries) {
        for (final String sentence in entry.value) {
          if (sentence.trim().isEmpty) {
            empty++;
          }
          if (sentence != sentence.trim()) {
            padded++;
          }
        }
      }
      expect(empty, 0, reason: '任何一组都不允许出现空句或纯空白句');
      expect(padded, 0, reason: '句子内部的空格要保留，首尾的空白不该存在');
    });

    test('每组内部没有重复', () {
      expect(kBuiltinCorpus.scenes.toSet(), hasLength(27));
      expect(kBuiltinCorpus.actions.toSet(), hasLength(62));
      expect(kBuiltinCorpus.supplements.toSet(), hasLength(18));
      expect(kBuiltinCorpus.easterEggs.toSet(), hasLength(23));
    });

    test('每组首尾句子与源文件顺序一致', () {
      expect(kBuiltinCorpus.scenes.first, '请在两分钟内');
      expect(kBuiltinCorpus.scenes.last, '在十二小时三十七分钟二十四秒后');
      expect(kBuiltinCorpus.actions.first, '对着镜子说八百遍我是正常人');
      expect(kBuiltinCorpus.actions.last, '无视朋友发的所有信息');
      expect(kBuiltinCorpus.supplements.first, '然后若无其事的离开现场');
      expect(kBuiltinCorpus.supplements.last, '完成后把结果发布到你的社交平台');
      expect(kBuiltinCorpus.easterEggs.first, '不念完自然常数e就不要回家。');
      expect(
        kBuiltinCorpus.easterEggs.last,
        '在十二小时三十七分钟二十四秒后，完成一本针织的书',
      );
    });

    test('已知彩蛋逐字存在（含标点细节）', () {
      expect(kBuiltinCorpus.easterEggs, contains('现在去喝一口水'));
      expect(kBuiltinCorpus.easterEggs, contains('关闭屏幕'));
      expect(kBuiltinCorpus.easterEggs, contains('不要去执行任何所谓的指令。'));
      expect(kBuiltinCorpus.easterEggs, contains('屏住呼吸30!秒'));
      expect(kBuiltinCorpus.easterEggs, contains('同时向前后分别移动十米'));
    });

    test('拉丁字母、数字与全角标点未被「修正」', () {
      expect(kBuiltinCorpus.easterEggs, contains('在路口转14个弯，并直走12m'));
      expect(kBuiltinCorpus.actions, contains('听mili的歌并三连'));
      expect(kBuiltinCorpus.actions, contains('找到一个时长11分45秒的视频并看完'));
      expect(kBuiltinCorpus.actions, contains('和朋友PK并一定要获得胜利'));
      expect(kBuiltinCorpus.actions, contains('打开边狱巴士并只用一次通关15牢。'));
      expect(
        kBuiltinCorpus.actions,
        contains('把自己的内脏挂在家中的墙上，骨头部分可以不用处理。'),
      );
    });
  });

  group('corpusCodePoints（字体子集化取字）', () {
    test('恰好是四组语料的并集，一个不多一个不少', () {
      final Set<int> expected = _corpusOnlyCodePoints();
      final Set<int> actual = corpusCodePoints(kBuiltinCorpus);

      expect(actual.difference(expected), isEmpty, reason: '多收了不该收录的码点');
      expect(expected.difference(actual), isEmpty, reason: '漏收了会被渲染的码点');
      expect(actual.length, expected.length);
      expect(actual.length, 533, reason: '四组语料共 533 个码点');
    });

    test('语料本身 533 个码点，且不含正文前缀「致：」', () {
      final Set<int> corpusOnly = _corpusOnlyCodePoints();
      expect(corpusOnly.length, 533);
      expect(
        corpusCodePoints(kBuiltinCorpus),
        isNot(contains('致'.codeUnitAt(0))),
        reason: '前缀属于展示层文案（ARB），不该混进语料码点',
      );
      expect(
        corpusCodePoints(kBuiltinCorpus),
        isNot(contains('：'.codeUnitAt(0))),
      );
    });

    test('包含常用字、全角标点与 ASCII 字母数字', () {
      final Set<int> codePoints = corpusCodePoints(kBuiltinCorpus);
      // 「指」来自彩蛋「不要去执行任何所谓的指令。」。
      expect(codePoints, contains('指'.codeUnitAt(0)));
      expect(codePoints, contains('。'.codeUnitAt(0)));
      expect(codePoints, contains('，'.codeUnitAt(0)));
      // 语料里只出现小写拉丁字母（「12m」「自然常数e」「mili」）与数字。
      expect(codePoints, contains('m'.codeUnitAt(0)));
      expect(codePoints, contains('e'.codeUnitAt(0)));
      expect(codePoints, contains('0'.codeUnitAt(0)));
      expect(codePoints, contains('!'.codeUnitAt(0)));
      expect(codePoints, contains('1'.codeUnitAt(0)));
      // 没有任何半角空白，也没有半个代理对。
      expect(codePoints, isNot(contains(0x20)));
      expect(
        codePoints.where((int cp) => cp >= 0xD800 && cp <= 0xDFFF),
        isEmpty,
        reason: 'runes 已经展开代理对，不应留下 UTF-16 半截码元',
      );
      expect(codePoints.every((int cp) => cp >= 0 && cp <= 0x10FFFF), isTrue);
    });

    test('四组各自的码点数与源文件一致（79 / 375 / 123 / 215）', () {
      int uniqueIn(List<String> group) => <int>{
        for (final String sentence in group) ...sentence.runes,
      }.length;
      expect(uniqueIn(kBuiltinCorpus.scenes), 79);
      expect(uniqueIn(kBuiltinCorpus.actions), 375);
      expect(uniqueIn(kBuiltinCorpus.supplements), 123);
      expect(uniqueIn(kBuiltinCorpus.easterEggs), 215);
    });

    test('语料里既没有 ASCII a 也没有 A', () {
      final Set<int> codePoints = corpusCodePoints(kBuiltinCorpus);
      expect(codePoints, isNot(contains('a'.codeUnitAt(0))));
      expect(codePoints, isNot(contains('A'.codeUnitAt(0))));
      expect(
        codePoints.contains('a'.codeUnitAt(0)),
        isNot(codePoints.contains('m'.codeUnitAt(0))),
        reason: '「12m」里有 m 但没有 a：子集化不应顺手带上整个字母表',
      );
    });

    test('空语料返回空集合', () {
      expect(
        corpusCodePoints(const InstructionCorpus.empty()),
        isEmpty,
        reason: '前缀「致：」属于 ARB，不在语料码点里',
      );
    });

    test('自定义语料是精确集合（不多不少）', () {
      const InstructionCorpus corpus = InstructionCorpus(
        scenes: <String>['A'],
        actions: <String>['b2'],
        supplements: <String>[],
        easterEggs: <String>[],
      );
      expect(
        corpusCodePoints(corpus),
        unorderedEquals(<int>[
          'A'.codeUnitAt(0),
          'b'.codeUnitAt(0),
          '2'.codeUnitAt(0),
        ]),
      );
    });
  });

  group('InstructionCorpus 辅助方法', () {
    test('copyWith 只替换传入的组', () {
      final InstructionCorpus copy = kBuiltinCorpus.copyWith(
        easterEggs: const <String>['唯一'],
      );
      expect(copy.easterEggs, <String>['唯一']);
      expect(copy.scenes, kBuiltinCorpus.scenes);
      expect(copy.actions, kBuiltinCorpus.actions);
      expect(copy.supplements, kBuiltinCorpus.supplements);
      expect(copy.canAssemble, isTrue);
    });

    test('toJson / fromJson 往返一致', () {
      expect(
        InstructionCorpus.fromJson(kBuiltinCorpus.toJson()),
        kBuiltinCorpus,
      );
      expect(
        InstructionCorpus.fromJson(kBuiltinCorpus.toJson()).hashCode,
        kBuiltinCorpus.hashCode,
      );
    });

    test('fromJson 容忍垃圾输入并过滤空串', () {
      final InstructionCorpus garbage = InstructionCorpus.fromJson(
        const <String, Object?>{
          'scenes': 'nope',
          'actions': <Object?>['ok', 3, null, '   '],
        },
      );
      expect(garbage.scenes, isEmpty);
      expect(garbage.actions, <String>['ok'], reason: '非字符串与纯空白条目都被丢弃');
      expect(garbage.canAssemble, isFalse);
      expect(
        InstructionCorpus.fromJson(const <String, Object?>{}),
        const InstructionCorpus.empty(),
      );
    });
  });
}
