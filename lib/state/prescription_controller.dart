import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/instruction_corpus_data.dart';
import '../data/models/app_settings.dart';
import '../data/models/instruction.dart';
import '../domain/instruction_corpus.dart';
import '../domain/instruction_generator.dart';

/// 指令控制器：持有「当前这一条指令」并负责生成。
///
/// 没有历史、没有收藏——原版只有一个 `#display-container`，每次生成直接覆盖。
class PrescriptionController extends ChangeNotifier {
  PrescriptionController({
    InstructionCorpus corpus = kBuiltinCorpus,
    Random? random,
    AppSettings settings = AppSettings.defaults,
  }) : _corpus = corpus,
       _settings = settings,
       _generator = InstructionGenerator(
         corpus: corpus,
         random: random,
         easterEggRate: settings.easterEggRate,
         easterEggEnabled: settings.easterEggEnabled,
         strategy: settings.strategy,
       );

  final InstructionCorpus _corpus;
  final InstructionGenerator _generator;

  AppSettings _settings;
  Instruction? _current;
  int _generationTick = 0;

  /// 当前展示的指令；首次生成之前为 `null`（原版此时容器是空的）。
  Instruction? get current => _current;

  /// 每次生成自增。UI 用它作为 Key 强制重播动画——连续两次抽到同一句话时
  /// 文本不变，只靠文本变化无法触发重播。
  int get generationTick => _generationTick;

  InstructionCorpus get corpus => _corpus;

  AppSettings get settings => _settings;

  /// 生成一条新指令。
  Instruction generate() {
    final instruction = _generator.generate();
    _current = instruction;
    _generationTick++;
    notifyListeners();
    return instruction;
  }

  /// 让设置生效（彩蛋开关、概率与抽取策略）。
  void applySettings(AppSettings settings) {
    _settings = settings;
    _generator.configure(
      corpus: _corpus,
      easterEggRate: settings.easterEggRate,
      easterEggEnabled: settings.easterEggEnabled,
      strategy: settings.strategy,
    );
  }
}
