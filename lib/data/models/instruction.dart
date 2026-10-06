import 'package:flutter/foundation.dart';

/// 指令的生成方式，对应原版 `script.js` 的两个分支。
enum InstructionKind {
  /// `sceneSentence + actionSentence + supplementSentence`
  assembled,

  /// `easterEggs` 里的完整句子
  easterEgg,
}

/// 一条「指令」。
///
/// 不可变值对象；正文由 [segments] 直接拼接而成，**不含**「致：」前缀
/// （前缀属于展示层，与原版 `致：${...}` 的拼接位置一致）。
@immutable
class Instruction {
  const Instruction({required this.segments, required this.kind});

  /// 三段式：场景 + 行为 + 补充。
  ///
  /// 三个槽位**始终保留**（即使某个片段是空串）：抽掉空片段会让
  /// [scene] / [action] / [supplement] 整体错位。
  factory Instruction.assembled({
    required String scene,
    required String action,
    required String supplement,
  }) {
    return Instruction(
      segments: List<String>.unmodifiable(<String>[scene, action, supplement]),
      kind: InstructionKind.assembled,
    );
  }

  /// 彩蛋：自成因果的完整句子。
  factory Instruction.easterEgg({required String text}) => Instruction(
    segments: List<String>.unmodifiable(<String>[text]),
    kind: InstructionKind.easterEgg,
  );

  /// 按顺序拼接的片段：三段式为 `[场景, 行为, 补充]`，彩蛋为 `[整句]`。
  final List<String> segments;

  final InstructionKind kind;

  /// 最终正文（原版 `finalSentence` 去掉「致：」后的部分）。
  String get body => segments.join();

  int get length => body.length;

  bool get isEasterEgg => kind == InstructionKind.easterEgg;

  bool get isAssembled => kind == InstructionKind.assembled;

  String? get scene =>
      isAssembled && segments.isNotEmpty ? segments.first : null;

  String? get action => isAssembled && segments.length > 1 ? segments[1] : null;

  String? get supplement =>
      isAssembled && segments.length > 2 ? segments[2] : null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Instruction &&
          other.kind == kind &&
          listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(segments));

  @override
  String toString() => 'Instruction(${kind.name}, "$body")';
}
