import 'package:flutter/material.dart';

import 'neon_palette.dart';

/// 应用统一使用的字体族，与原版 `main.css` 的
/// `font-family: 'Inter', 'LXGWWenKai', sans-serif;` 一致。
///
/// 西文用 Inter（`fontFamily`），中文回退到霞鹜文楷（`fontFamilyFallback`）；
/// Flutter 的字体回退是「前者缺字才用后者」，所以顺序不能颠倒。
const String kLatinFontFamily = 'Inter';

/// 中文字族。随应用分发的是霞鹜文楷的**子集**，按 OFL 的保留字体名条款改名
/// （见 `THIRD_PARTY_NOTICES.md`），因此这里用的不是 `LXGW WenKai`。
const String kCjkFontFamily = 'WenKaiZL';
const List<String> kFontFallback = <String>[kCjkFontFamily];

/// 把 CSS `text-shadow` 的 blur-radius 换算成 Flutter `Shadow.blurRadius`。
///
/// CSS 的 blur-radius 是高斯核标准差的两倍；Flutter 的 `blurRadius` 会先被
/// 换算成 sigma（`sigma = blurRadius * 0.57735 + 0.5`）。令两者 sigma 相等即可：
/// `sigma = cssBlur / 2` ⇒ `flutterBlur = (cssBlur / 2 - 0.5) / 0.57735`。
double cssBlurToFlutter(double cssBlurRadius) {
  final sigma = cssBlurRadius / 2;
  return ((sigma - 0.5) / 0.57735).clamp(0, double.infinity);
}

/// 原版 `main.css` 里 `:root` 定义的三个颜色。
abstract final class OriginalColors {
  /// `--neon-blue: #00d2ff`
  static const Color neonBlue = Color(0xFF00D2FF);

  /// `--bright-white: #ffffff`
  static const Color brightWhite = Color(0xFFFFFFFF);

  /// `--dark-bg: #000000`
  static const Color darkBg = Color(0xFF000000);
}

/// 霓虹视觉令牌，通过 `ThemeExtension` 挂在 [ThemeData] 上。
@immutable
class NeonTheme extends ThemeExtension<NeonTheme> {
  const NeonTheme({
    this.palette = NeonPalette.indexBlue,
    this.glowStrength = 1,
    this.background = OriginalColors.darkBg,
    this.surface = const Color(0xFF0A0E14),
    this.textPrimary = OriginalColors.brightWhite,
    this.textMuted = const Color(0xFF8A97A8),
  });

  static const NeonTheme standard = NeonTheme();

  /// 当前色板。默认是原版的 `--neon-blue`。
  final NeonPalette palette;

  /// 发光强度 0 ~ 1。`1` 即原版 CSS 的三层 text-shadow。
  final double glowStrength;

  /// 页面底色，原版 `--dark-bg`。
  final Color background;

  /// 弹窗底色（原版没有弹窗，这里取一个贴近纯黑的深色）。
  final Color surface;

  /// 正文色，原版 `--bright-white`。
  final Color textPrimary;

  /// 次要文字（弹窗里的说明文字）。
  final Color textMuted;

  /// 霓虹主色，来自当前色板。
  Color get accent => palette.accent;

  Color get accentSoft => accent.withValues(alpha: 0.35);

  Color get divider => const Color(0xFF1E2833);

  /// 主色的不透明版本，用于色板圆点等需要实心填充的地方。
  bool get glowEnabled => glowStrength > 0;

  /// 逐字对应原版 `main.css` 的两处 text-shadow：
  ///
  /// * `#display-container`：`0 0 5px #fff, 0 0 10px var(--neon-blue), 0 0 15px var(--neon-blue)`
  /// * `.footer-note` / `button`：`0 0 5px var(--neon-blue)`
  ///
  /// 三层都是**全不透明**的（原版没有写 rgba）。`glowStrength == 1` 时输出与
  /// 原版逐值相同；小于 1 时按比例削弱透明度与模糊半径，等于 0 时完全不发光。
  ///
  /// [layers] 限制高斯模糊层数：文字每帧都在变时（乱码动画）用 `1` 层，
  /// 把每帧的模糊次数从 3 次降到 1 次；动画结束再恢复成 3 层。
  List<Shadow> glowShadows({int layers = 3}) {
    if (glowStrength <= 0 || layers <= 0) {
      return const <Shadow>[];
    }
    final s = glowStrength;
    final all = <Shadow>[
      Shadow(
        color: textPrimary.withValues(alpha: s),
        blurRadius: cssBlurToFlutter(5) * s,
      ),
      Shadow(
        color: accent.withValues(alpha: s),
        blurRadius: cssBlurToFlutter(10) * s,
      ),
      Shadow(
        color: accent.withValues(alpha: s),
        blurRadius: cssBlurToFlutter(15) * s,
      ),
    ];
    return layers >= all.length ? all : all.take(layers).toList(growable: false);
  }

  /// 原版 `button` / `.footer-note` 的单层蓝色 text-shadow：`0 0 5px var(--neon-blue)`。
  List<Shadow> get softGlow => glowStrength <= 0
      ? const <Shadow>[]
      : <Shadow>[
          Shadow(
            color: accent.withValues(alpha: glowStrength),
            blurRadius: cssBlurToFlutter(5) * glowStrength,
          ),
        ];

  /// 底部警告下方的免责声明用的更弱单层辉光（`0 0 4px accent`）。
  List<Shadow> get faintGlow => glowStrength <= 0
      ? const <Shadow>[]
      : <Shadow>[
          Shadow(
            color: accent.withValues(alpha: 0.55 * glowStrength),
            blurRadius: cssBlurToFlutter(4) * glowStrength,
          ),
        ];

  @override
  NeonTheme copyWith({
    NeonPalette? palette,
    double? glowStrength,
    Color? background,
    Color? surface,
    Color? textPrimary,
    Color? textMuted,
  }) {
    return NeonTheme(
      palette: palette ?? this.palette,
      glowStrength: glowStrength ?? this.glowStrength,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  NeonTheme lerp(ThemeExtension<NeonTheme>? other, double t) {
    if (other is! NeonTheme) {
      return this;
    }
    return NeonTheme(
      palette: t < 0.5 ? palette : other.palette,
      glowStrength: glowStrength + (other.glowStrength - glowStrength) * t,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NeonTheme &&
          other.palette == palette &&
          other.glowStrength == glowStrength &&
          other.background == background &&
          other.surface == surface &&
          other.accent == accent &&
          other.textPrimary == textPrimary &&
          other.textMuted == textMuted;

  @override
  int get hashCode =>
      Object.hash(background, surface, accent, textPrimary, textMuted);
}

/// 便捷读取：`context.neon.accent`。
extension NeonThemeContext on BuildContext {
  NeonTheme get neon =>
      Theme.of(this).extension<NeonTheme>() ?? NeonTheme.standard;

  /// 系统无障碍设置是否要求减少动效。
  ///
  /// `MediaQueryData.disableAnimations` 只覆盖 Android 与 Web（Web 上
  /// `prefers-reduced-motion` 会同时置位两个标记）；iOS / macOS 的「减弱动态
  /// 效果」只设置 `AccessibilityFeatures.reduceMotion`，而 Flutter 3.47 没有
  /// `MediaQuery.reduceMotionOf`，所以两者都要查。
  bool get systemDisablesAnimations {
    if (MediaQuery.maybeOf(this)?.disableAnimations ?? false) {
      return true;
    }
    return WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;
  }
}

/// 主题工厂：只有一种主题——原版的纯黑霓虹，可换色板与发光强度。
abstract final class AppTheme {
  static ThemeData build({
    NeonPalette palette = NeonPalette.indexBlue,
    double glowStrength = 1,
  }) {
    final neon = NeonTheme(palette: palette, glowStrength: glowStrength);
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: neon.accent,
        brightness: Brightness.dark,
        surface: neon.background,
      ).copyWith(
        primary: neon.accent,
        onPrimary: neon.background,
        surface: neon.background,
        onSurface: neon.textPrimary,
      ),
      scaffoldBackgroundColor: neon.background,
      canvasColor: neon.background,
    );
    final textTheme = base.textTheme.apply(
      fontFamily: kLatinFontFamily,
      fontFamilyFallback: kFontFallback,
      bodyColor: neon.textPrimary,
      displayColor: neon.textPrimary,
    );
    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: kLatinFontFamily,
        fontFamilyFallback: kFontFallback,
      ),
      extensions: <ThemeExtension<dynamic>>[neon],
      dividerColor: neon.divider,
      dialogTheme: DialogThemeData(
        backgroundColor: neon.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: neon.accentSoft),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: neon.accent,
        thumbColor: neon.accent,
        inactiveTrackColor: neon.divider,
        overlayColor: neon.accent.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? neon.accent
              : neon.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? neon.accent.withValues(alpha: 0.35)
              : neon.divider,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: neon.surface,
          border: Border.all(color: neon.accentSoft),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall,
      ),
    );
  }
}
