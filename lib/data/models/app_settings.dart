import 'package:flutter/foundation.dart';

/// 界面语言。
enum AppLanguage {
  /// 跟随系统；系统语言不是中/英时回退简体中文。
  system,

  zh,
  en,
}

/// 抽取策略。
enum GenerationStrategy {
  /// 纯随机，与原版 `Math.random()` 行为一致（允许重复）。默认值。
  pureRandom,

  /// 洗牌袋：抽完一轮之前不重复，避免连续抽到同一句。
  shuffleBag,
}

/// 用户可持久化的设置。
///
/// **默认值就是原版网页的行为**：不改任何一项时，应用与原站逐像素一致。
@immutable
class AppSettings {
  const AppSettings({
    this.paletteId = 'index_blue',
    this.language = AppLanguage.system,
    this.glowStrength = 1,
    this.reduceMotion = false,
    this.animationSpeed = 1,
    this.easterEggEnabled = true,
    this.easterEggRate = 0.15,
    this.strategy = GenerationStrategy.pureRandom,
  });

  /// 霓虹主色 ID，见 `lib/core/theme/neon_palette.dart`。默认原版的 `#00d2ff`。
  final String paletteId;

  /// 界面语言。默认跟随系统。
  final AppLanguage language;

  /// 霓虹发光强度（0 ~ 1）。`1` = 原版 CSS 的三层 text-shadow，`0` = 完全关闭。
  ///
  /// 这既是观感选项，也是性能开关：发光是逐帧重绘时最贵的一项。
  final double glowStrength;

  /// 减少动效：直接显示指令，不播放乱码动画。
  ///
  /// 系统级的 `disableAnimations` / `reduceMotion` 始终优先生效。
  final bool reduceMotion;

  /// 乱码动画速度倍率（0.25 ~ 3.0，越大越快）。`1.0` 即原版速度。
  final double animationSpeed;

  /// 是否允许抽到彩蛋。原版固定参与抽取。
  final bool easterEggEnabled;

  /// 彩蛋概率（0.0 ~ 1.0）。原版硬编码 `Math.random() < 0.15`。
  final double easterEggRate;

  /// 抽取策略。默认纯随机（原版行为）。
  final GenerationStrategy strategy;

  static const AppSettings defaults = AppSettings();

  /// 原版的彩蛋概率。
  static const double originalEasterEggRate = 0.15;

  AppSettings copyWith({
    String? paletteId,
    AppLanguage? language,
    double? glowStrength,
    bool? reduceMotion,
    double? animationSpeed,
    bool? easterEggEnabled,
    double? easterEggRate,
    GenerationStrategy? strategy,
  }) {
    return AppSettings(
      paletteId: paletteId ?? this.paletteId,
      language: language ?? this.language,
      glowStrength: glowStrength ?? this.glowStrength,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      easterEggEnabled: easterEggEnabled ?? this.easterEggEnabled,
      easterEggRate: easterEggRate ?? this.easterEggRate,
      strategy: strategy ?? this.strategy,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'paletteId': paletteId,
    'language': language.name,
    'glowStrength': glowStrength,
    'reduceMotion': reduceMotion,
    'animationSpeed': animationSpeed,
    'easterEggEnabled': easterEggEnabled,
    'easterEggRate': easterEggRate,
    'strategy': strategy.name,
  };

  /// 容错反序列化：任何字段异常都单独回退到默认值，绝不抛出。
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const fallback = AppSettings.defaults;

    bool boolOr(String key, bool value) {
      final raw = json[key];
      return raw is bool ? raw : value;
    }

    // 注意 `1e400` 是合法 JSON，`jsonDecode` 会得到 `Infinity`；
    // 不检查 `isFinite` 的话 `clamp` 会抛 `UnsupportedError`。
    double doubleOr(String key, double value, double min, double max) {
      final raw = json[key];
      if (raw is num && raw.isFinite) {
        return raw.toDouble().clamp(min, max);
      }
      return value;
    }

    T enumOr<T extends Enum>(String key, List<T> values, T value) {
      final raw = json[key];
      if (raw is String) {
        for (final candidate in values) {
          if (candidate.name == raw) {
            return candidate;
          }
        }
      }
      return value;
    }

    String stringOr(String key, String value) {
      final raw = json[key];
      return raw is String && raw.isNotEmpty ? raw : value;
    }

    return AppSettings(
      paletteId: stringOr('paletteId', fallback.paletteId),
      language: enumOr('language', AppLanguage.values, fallback.language),
      glowStrength: doubleOr(
        'glowStrength',
        fallback.glowStrength,
        0,
        1,
      ),
      reduceMotion: boolOr('reduceMotion', fallback.reduceMotion),
      animationSpeed: doubleOr(
        'animationSpeed',
        fallback.animationSpeed,
        0.25,
        3,
      ),
      easterEggEnabled: boolOr(
        'easterEggEnabled',
        fallback.easterEggEnabled,
      ),
      easterEggRate: doubleOr('easterEggRate', fallback.easterEggRate, 0, 1),
      strategy: enumOr(
        'strategy',
        GenerationStrategy.values,
        fallback.strategy,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.paletteId == paletteId &&
          other.language == language &&
          other.glowStrength == glowStrength &&
          other.reduceMotion == reduceMotion &&
          other.animationSpeed == animationSpeed &&
          other.easterEggEnabled == easterEggEnabled &&
          other.easterEggRate == easterEggRate &&
          other.strategy == strategy;

  @override
  int get hashCode => Object.hash(
    paletteId,
    language,
    glowStrength,
    reduceMotion,
    animationSpeed,
    easterEggEnabled,
    easterEggRate,
    strategy,
  );

  @override
  String toString() =>
      'AppSettings($paletteId, ${language.name}, glow: $glowStrength, '
      'reduceMotion: $reduceMotion, speed: $animationSpeed, '
      'egg: $easterEggEnabled@$easterEggRate, ${strategy.name})';
}
