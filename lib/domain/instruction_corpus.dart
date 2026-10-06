import 'package:flutter/foundation.dart';

/// 指令语料库：四组句子模板。
///
/// 这是纯粹的**数据载体**（不关心持久化与生成算法），
/// 内置语料见 `lib/data/instruction_corpus_data.dart`。
@immutable
class InstructionCorpus {
  const InstructionCorpus({
    required this.scenes,
    required this.actions,
    required this.supplements,
    required this.easterEggs,
  });

  const InstructionCorpus.empty()
    : scenes = const <String>[],
      actions = const <String>[],
      supplements = const <String>[],
      easterEggs = const <String>[];

  /// 场景限定句：时间/环境/姿态。
  final List<String> scenes;

  /// 核心行为句：动宾结构。
  final List<String> actions;

  /// 补充要求句：后缀，增加难度或仪式感。
  final List<String> supplements;

  /// 彩蛋：自成因果的完整句子。
  final List<String> easterEggs;

  /// 至少能拼出三段式指令。
  bool get canAssemble =>
      scenes.isNotEmpty && actions.isNotEmpty && supplements.isNotEmpty;

  bool get canPickEasterEgg => easterEggs.isNotEmpty;

  bool get isEmpty => scenes.isEmpty && actions.isEmpty && supplements.isEmpty;

  /// 三段式理论组合数（仅用于展示）。
  int get combinationCount =>
      scenes.length * actions.length * supplements.length;

  int get totalSentences =>
      scenes.length + actions.length + supplements.length + easterEggs.length;

  InstructionCorpus copyWith({
    List<String>? scenes,
    List<String>? actions,
    List<String>? supplements,
    List<String>? easterEggs,
  }) {
    return InstructionCorpus(
      scenes: scenes ?? this.scenes,
      actions: actions ?? this.actions,
      supplements: supplements ?? this.supplements,
      easterEggs: easterEggs ?? this.easterEggs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'scenes': scenes,
    'actions': actions,
    'supplements': supplements,
    'easterEggs': easterEggs,
  };

  factory InstructionCorpus.fromJson(Map<String, Object?> json) {
    List<String> listOf(String key) {
      final raw = json[key];
      if (raw is! List) {
        return const <String>[];
      }
      return List<String>.unmodifiable(
        raw.whereType<String>().where((item) => item.trim().isNotEmpty),
      );
    }

    return InstructionCorpus(
      scenes: listOf('scenes'),
      actions: listOf('actions'),
      supplements: listOf('supplements'),
      easterEggs: listOf('easterEggs'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstructionCorpus &&
          listEquals(other.scenes, scenes) &&
          listEquals(other.actions, actions) &&
          listEquals(other.supplements, supplements) &&
          listEquals(other.easterEggs, easterEggs);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(scenes),
    Object.hashAll(actions),
    Object.hashAll(supplements),
    Object.hashAll(easterEggs),
  );
}
