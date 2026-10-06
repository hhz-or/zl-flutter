import 'dart:math';

import '../data/models/app_settings.dart';
import '../data/models/instruction.dart';
import 'instruction_corpus.dart';

/// 洗牌袋：一轮之内不重复地抽取元素，抽空后自动重新洗牌。
///
/// 只在 `GenerationStrategy.shuffleBag` 下使用；默认的 `pureRandom` 与原版完全一致。
class ShuffleBag<T> {
  ShuffleBag({required List<T> items, Random? random})
    : _items = List<T>.unmodifiable(items),
      _random = random ?? Random();

  final List<T> _items;
  final Random _random;
  final List<T> _queue = <T>[];
  T? _lastDrawn;

  /// 本轮已抽取数量。
  int get drawn => _queue.length;

  bool get isEmpty => _items.isEmpty;

  int get length => _items.length;

  /// 取出下一个元素；[T] 为空时返回 `null`。
  T? next() {
    if (_items.isEmpty) {
      return null;
    }
    if (_queue.isEmpty) {
      refill();
      _avoidBoundaryRepeat();
    }
    final value = _queue.removeLast();
    _lastDrawn = value;
    return value;
  }

  /// 重置袋子，让下一轮从新的洗牌开始（不改变随机源）。
  void reset() {
    _queue.clear();
    _lastDrawn = null;
  }

  /// 重新洗牌，把队列填满（Fisher–Yates）。
  void refill() {
    _queue
      ..clear()
      ..addAll(_items);
    for (var i = _queue.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = _queue[i];
      _queue[i] = _queue[j];
      _queue[j] = tmp;
    }
  }

  /// 跨轮去重：把队尾换成队列中另一个**值不等于上一轮末尾**的元素。
  ///
  /// 语料允许包含重复项，所以不能只按位置判断——必须按值筛选候选位置。
  void _avoidBoundaryRepeat() {
    final last = _lastDrawn;
    if (_queue.length < 2 || last == null || _queue.last != last) {
      return;
    }
    final candidates = <int>[
      for (var i = 0; i < _queue.length - 1; i++)
        if (_queue[i] != last) i,
    ];
    if (candidates.isEmpty) {
      // 其余元素全都与上一轮末尾同值，无从避免。
      return;
    }
    final swapIndex = candidates[_random.nextInt(candidates.length)];
    final tail = _queue.last;
    _queue[_queue.length - 1] = _queue[swapIndex];
    _queue[swapIndex] = tail;
  }
}

/// 指令生成器：把语料库拼装成 [Instruction]。
///
/// 默认策略逐行对应原版 `script.js` 的按钮回调：
///
/// ```js
/// if (Math.random() < 0.15) {
///   finalSentence = `致：${easterEggs[Math.floor(Math.random() * easterEggs.length)]}`;
/// } else {
///   const scene = sceneSentence[Math.floor(Math.random() * sceneSentence.length)];
///   const action = actionSentence[Math.floor(Math.random() * actionSentence.length)];
///   const supplement = supplementSentence[Math.floor(Math.random() * supplementSentence.length)];
///   finalSentence = `致：${scene}${action}${supplement}`;
/// }
/// ```
///
/// 三段之间不加任何分隔符。随机源可注入，因此测试可以 100% 复现。
class InstructionGenerator {
  InstructionGenerator({
    required InstructionCorpus corpus,
    Random? random,
    double easterEggRate = AppSettings.originalEasterEggRate,
    bool easterEggEnabled = true,
    GenerationStrategy strategy = GenerationStrategy.pureRandom,
  }) : _corpus = corpus,
       _random = random ?? Random(),
       _easterEggRate = easterEggRate.clamp(0, 1),
       _easterEggEnabled = easterEggEnabled,
       _strategy = strategy;

  InstructionCorpus _corpus;
  final Random _random;
  double _easterEggRate;
  bool _easterEggEnabled;
  GenerationStrategy _strategy;

  ShuffleBag<String>? _sceneBag;
  ShuffleBag<String>? _actionBag;
  ShuffleBag<String>? _supplementBag;
  ShuffleBag<String>? _eggBag;
  List<String>? _sceneSource;
  List<String>? _actionSource;
  List<String>? _supplementSource;
  List<String>? _eggSource;

  InstructionCorpus get corpus => _corpus;

  double get easterEggRate => _easterEggRate;

  bool get easterEggEnabled => _easterEggEnabled;

  GenerationStrategy get strategy => _strategy;

  /// 热更新设置（设置弹窗改动后调用，避免重建生成器）。
  void configure({
    InstructionCorpus? corpus,
    double? easterEggRate,
    bool? easterEggEnabled,
    GenerationStrategy? strategy,
  }) {
    if (corpus != null && !identical(corpus, _corpus)) {
      _corpus = corpus;
      _resetBags();
    }
    if (easterEggRate != null) {
      _easterEggRate = easterEggRate.clamp(0, 1);
    }
    if (easterEggEnabled != null) {
      _easterEggEnabled = easterEggEnabled;
    }
    if (strategy != null && strategy != _strategy) {
      _strategy = strategy;
      _resetBags();
    }
  }

  /// 清空洗牌袋，让下一轮重新洗牌。
  void resetBags() => _resetBags();

  void _resetBags() {
    _sceneBag = null;
    _actionBag = null;
    _supplementBag = null;
    _eggBag = null;
    _sceneSource = null;
    _actionSource = null;
    _supplementSource = null;
    _eggSource = null;
  }

  /// 生成一条指令。语料残缺时优雅退化，绝不抛出。
  Instruction generate() {
    final useEasterEgg =
        _easterEggEnabled &&
        _corpus.easterEggs.isNotEmpty &&
        _random.nextDouble() < _easterEggRate;
    if (useEasterEgg) {
      return Instruction.easterEgg(text: _pickEggs());
    }
    if (!_corpus.canAssemble) {
      // 语料缺失：退化为彩蛋，仍然不抛。
      return Instruction.easterEgg(
        text: _corpus.easterEggs.isEmpty ? '' : _corpus.easterEggs.first,
      );
    }
    return Instruction.assembled(
      scene: _pickScenes(),
      action: _pickActions(),
      supplement: _pickSupplements(),
    );
  }

  String _pickScenes() => _pick(
    _corpus.scenes,
    _sceneBag,
    (bag) => _sceneBag = bag,
    _sceneSource,
    (source) => _sceneSource = source,
  );

  String _pickActions() => _pick(
    _corpus.actions,
    _actionBag,
    (bag) => _actionBag = bag,
    _actionSource,
    (source) => _actionSource = source,
  );

  String _pickSupplements() => _pick(
    _corpus.supplements,
    _supplementBag,
    (bag) => _supplementBag = bag,
    _supplementSource,
    (source) => _supplementSource = source,
  );

  String _pickEggs() => _pick(
    _corpus.easterEggs,
    _eggBag,
    (bag) => _eggBag = bag,
    _eggSource,
    (source) => _eggSource = source,
  );

  /// 等价于原版的 `arr[Math.floor(Math.random() * arr.length)]`。
  /// 空列表返回空串（原版此时会得到 `undefined`）。
  String _pick(
    List<String> items,
    ShuffleBag<String>? bag,
    void Function(ShuffleBag<String>) assignBag,
    List<String>? source,
    void Function(List<String>) assignSource,
  ) {
    if (items.isEmpty) {
      return '';
    }
    if (_strategy == GenerationStrategy.pureRandom) {
      return items[_random.nextInt(items.length)];
    }
    // 语料换成了「等长但内容不同」的列表时，旧袋子会吐出已经不存在的句子。
    if (bag == null || !identical(source, items)) {
      bag = ShuffleBag<String>(items: items, random: _random);
      assignBag(bag);
      assignSource(items);
    }
    return bag.next() ?? items[_random.nextInt(items.length)];
  }
}
