import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';

/// 打开设置弹窗（右上角齿轮按钮的唯一入口）。
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const SettingsDialog(),
  );
}

/// 设置弹窗。
///
/// 分三组：外观 / 动效 / 生成。**所有默认值都等于原版网页的行为**——
/// 不动任何一项时，应用与原站逐像素一致。
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final neon = context.neon;
    final controller = AppScope.of(context).settings;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.value;
        return AlertDialog(
          backgroundColor: neon.surface,
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
          title: Text(
            l10n.settingsTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              letterSpacing: 4,
              fontWeight: FontWeight.w600,
              shadows: neon.softGlow,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              // 弹窗最多占屏幕高度的 70%，其余部分滚动。
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SectionLabel(l10n.settingsAppearance),

                    _ColorPickerRow(
                      color: Color(settings.accentColor),
                      onChanged: (color) => controller.update(
                        (s) => s.copyWith(accentColor: color.toARGB32()),
                      ),
                      onReset: () => controller.update(
                        (s) => s.copyWith(
                          accentColor: AppSettings.defaultAccentColor,
                        ),
                      ),
                    ),

                    _ChoiceRow<AppLanguage>(
                      id: 'language',
                      label: l10n.settingsLanguage,
                      value: settings.language,
                      options: <_Choice<AppLanguage>>[
                        _Choice(
                          id: 'system',
                          value: AppLanguage.system,
                          label: l10n.languageSystem,
                        ),
                        _Choice(
                          id: 'zh',
                          value: AppLanguage.zh,
                          label: l10n.languageZh,
                        ),
                        _Choice(
                          id: 'en',
                          value: AppLanguage.en,
                          label: l10n.languageEn,
                        ),
                      ],
                      onSelected: (value) =>
                          controller.update((s) => s.copyWith(language: value)),
                    ),

                    _SliderRow(
                      key: const Key('settings-glow'),
                      label: l10n.settingsGlow,
                      hint: l10n.settingsGlowHint,
                      valueLabel: l10n.percentValue(
                        (settings.glowStrength * 100).round(),
                      ),
                      value: settings.glowStrength,
                      min: 0,
                      max: 1,
                      onChanged: (value) => controller.update(
                        (s) => s.copyWith(glowStrength: value),
                      ),
                    ),

                    const SizedBox(height: 8),
                    _SectionLabel(l10n.settingsMotion),

                    _SwitchRow(
                      key: const Key('settings-reduce-motion'),
                      label: l10n.settingsReduceMotion,
                      hint: l10n.settingsReduceMotionHint,
                      value: settings.reduceMotion,
                      onChanged: (value) => controller.update(
                        (s) => s.copyWith(reduceMotion: value),
                      ),
                    ),

                    _SliderRow(
                      key: const Key('settings-animation-speed'),
                      label: l10n.settingsAnimationSpeed,
                      hint: l10n.settingsAnimationSpeedHint,
                      valueLabel: l10n.settingsAnimationSpeedValue(
                        settings.animationSpeed.toStringAsFixed(2),
                      ),
                      value: settings.animationSpeed,
                      min: 0.25,
                      max: 3,
                      onChanged: (value) => controller.update(
                        (s) => s.copyWith(animationSpeed: value),
                      ),
                    ),

                    const SizedBox(height: 8),
                    _SectionLabel(l10n.settingsGeneration),

                    _SwitchRow(
                      key: const Key('settings-easter-egg'),
                      label: l10n.settingsEasterEgg,
                      hint: l10n.settingsEasterEggHint,
                      value: settings.easterEggEnabled,
                      onChanged: (value) => controller.update(
                        (s) => s.copyWith(easterEggEnabled: value),
                      ),
                    ),

                    _SliderRow(
                      key: const Key('settings-easter-egg-rate'),
                      label: l10n.settingsEasterEggRate,
                      hint: l10n.settingsEasterEggRateHint,
                      valueLabel: l10n.percentValue(
                        (settings.easterEggRate * 100).round(),
                      ),
                      value: settings.easterEggRate,
                      min: 0,
                      max: 1,
                      enabled: settings.easterEggEnabled,
                      onChanged: (value) => controller.update(
                        (s) => s.copyWith(easterEggRate: value),
                      ),
                    ),

                    _ChoiceRow<GenerationStrategy>(
                      id: 'strategy',
                      label: l10n.settingsStrategy,
                      value: settings.strategy,
                      options: <_Choice<GenerationStrategy>>[
                        _Choice(
                          id: 'pure_random',
                          value: GenerationStrategy.pureRandom,
                          label: l10n.strategyPureRandom,
                        ),
                        _Choice(
                          id: 'shuffle_bag',
                          value: GenerationStrategy.shuffleBag,
                          label: l10n.strategyShuffleBag,
                        ),
                      ],
                      onSelected: (value) =>
                          controller.update((s) => s.copyWith(strategy: value)),
                    ),

                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('settings-reset'),
                        onPressed: settings == AppSettings.defaults
                            ? null
                            : controller.reset,
                        style: TextButton.styleFrom(
                          foregroundColor: neon.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                          l10n.settingsReset,
                          style: const TextStyle(letterSpacing: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: <Widget>[
            TextButton(
              key: const Key('settings-close'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: neon.accent),
              child: Text(
                l10n.closeAction,
                style: const TextStyle(letterSpacing: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 分组标题。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 13,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: neon.accent,
              borderRadius: BorderRadius.circular(2),
              boxShadow: neon.glowStrength > 0
                  ? <BoxShadow>[
                      BoxShadow(
                        color: neon.accent.withValues(
                          alpha: neon.glowStrength,
                        ),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: neon.textMuted,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 主题色：可自由调节（HSV 三个滑条）+ 一键恢复默认蓝。
///
/// 主色是整套视觉的唯一色相来源（文字辉光、按钮、描边、控件都取自它），
/// 所以这里放开成任意颜色，而不是给几个预设。
class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.color,
    required this.onChanged,
    required this.onReset,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final l10n = AppLocalizations.of(context);
    final hsv = HSVColor.fromColor(color);
    final isDefault = color.toARGB32() == AppSettings.defaultAccentColor;

    void update({double? hue, double? saturation, double? value}) {
      onChanged(
        hsv
            .withHue(hue ?? hsv.hue)
            .withSaturation(saturation ?? hsv.saturation)
            .withValue(value ?? hsv.value)
            .toColor(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 用 Wrap 而不是 Row：英文的「Accent colour / Reset to blue」比中文长，
        // 窄弹窗里必须能换行，不能硬撑出 overflow。
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            Text(
              l10n.settingsThemeColor,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  key: const Key('settings-color-preview'),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: neon.textPrimary, width: 1.5),
                    boxShadow: neon.glowStrength > 0
                        ? <BoxShadow>[
                            BoxShadow(
                              color: color.withValues(
                                alpha: 0.7 * neon.glowStrength,
                              ),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _hex(color),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: neon.textMuted,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            TextButton(
              key: const Key('settings-color-reset'),
              onPressed: isDefault ? null : onReset,
              style: TextButton.styleFrom(
                foregroundColor: neon.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.settingsAccentReset),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _HueSlider(
          value: hsv.hue,
          onChanged: (h) => update(hue: h),
        ),
        _SliderRow(
          id: 'color-saturation',
          label: l10n.colorSaturation,
          valueLabel: '${(hsv.saturation * 100).round()}%',
          value: hsv.saturation,
          min: 0,
          max: 1,
          onChanged: (v) => update(saturation: v),
        ),
        _SliderRow(
          id: 'color-brightness',
          label: l10n.colorBrightness,
          valueLabel: '${(hsv.value * 100).round()}%',
          value: hsv.value,
          min: 0,
          max: 1,
          onChanged: (v) => update(value: v),
        ),
      ],
    );
  }
}

/// 色相滑条：轨道直接画成彩虹，滑块照旧由 [Slider] 提供。
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static final List<Color> _spectrum = <Color>[
    for (int h = 0; h <= 360; h += 30)
      HSVColor.fromAHSV(1, h.toDouble() % 360, 1, 1).toColor(),
  ];

  @override
  Widget build(BuildContext context) {
    return _SliderRow(
      id: 'color-hue',
      label: AppLocalizations.of(context).colorHue,
      valueLabel: '${value.round()}°',
      value: value,
      min: 0,
      max: 360,
      onChanged: onChanged,
      // 轨道本身由下面的渐变条提供，Slider 自己的轨道透明化。
      track: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(colors: _spectrum),
        ),
      ),
    );
  }
}

class _Choice<T> {
  const _Choice({required this.id, required this.value, required this.label});

  /// 用于测试定位的稳定 id（`settings-<rowId>-<id>`）。
  final String id;

  final T value;
  final String label;
}

/// 一行单选（语言 / 抽取策略）。
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.id,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String id;
  final String label;
  final T value;
  final List<_Choice<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final option in options)
                _ChoiceChip(
                  key: Key('settings-$id-${option.id}'),
                  label: option.label,
                  selected: option.value == value,
                  onTap: () => onSelected(option.value),
                  accent: neon.accent,
                  glowStrength: neon.glowStrength,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.glowStrength,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final double glowStrength;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? accent : neon.divider),
          boxShadow: selected && glowStrength > 0
              ? <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35 * glowStrength),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: selected ? accent : neon.textMuted,
          ),
        ),
      ),
    );
  }
}

/// 一行「标题 + 说明 + 开关」。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: textTheme.bodyLarge),
                  if (hint.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: textTheme.bodySmall?.copyWith(
                        color: neon.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// 一行「标题 + 当前值 + 滑杆」。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    super.key,
    this.id,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint = '',
    this.enabled = true,
    this.track,
  });

  /// 用于测试定位的稳定 id（`settings-<id>`）。为空则不挂 Key。
  final String? id;
  final String label;
  final String hint;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  /// 自定义轨道外观（色相滑条用它铺彩虹渐变）。给了就把 Slider 自带轨道
  /// 设为透明，只留滑块。
  final Widget? track;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final textTheme = Theme.of(context).textTheme;
    final effective = enabled ? neon.accent : neon.textMuted;
    Widget slider = Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      onChanged: enabled ? onChanged : null,
    );
    if (track != null) {
      slider = SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 12,
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // 必须是 Positioned.fill + width: infinity：Stack 的非定位子节点
            // 拿到的是松约束，只写 height 的 SizedBox 宽度会是 0（彩虹条消失）。
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: SizedBox(
                    height: 12,
                    width: double.infinity,
                    child: track,
                  ),
                ),
              ),
            ),
            slider,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyLarge?.copyWith(
                    color: enabled ? null : neon.textMuted,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: textTheme.bodySmall?.copyWith(color: effective),
              ),
            ],
          ),
          if (hint.isNotEmpty)
            Text(
              hint,
              style: textTheme.bodySmall?.copyWith(color: neon.textMuted),
            ),
          if (id == null) slider else KeyedSubtree(key: Key('settings-$id'), child: slider),
        ],
      ),
    );
  }
}
