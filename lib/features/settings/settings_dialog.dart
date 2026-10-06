import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/neon_palette.dart';
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
    final locale = Localizations.localeOf(context);

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

                    _PaletteRow(
                      selected: NeonPalette.byId(settings.paletteId),
                      locale: locale,
                      onSelected: (palette) => controller.update(
                        (s) => s.copyWith(paletteId: palette.id),
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

/// 主题色：一排圆点 + 当前色名。
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.selected,
    required this.locale,
    required this.onSelected,
  });

  final NeonPalette selected;
  final Locale locale;
  final ValueChanged<NeonPalette> onSelected;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    return Row(
      children: <Widget>[
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final palette in NeonPalette.values)
                Tooltip(
                  message: palette.labelFor(locale),
                  child: InkWell(
                    key: Key('settings-palette-${palette.id}'),
                    onTap: () => onSelected(palette),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette == selected
                              ? neon.textPrimary
                              : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: neon.glowStrength > 0
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: palette.accent.withValues(
                                    alpha: 0.7 * neon.glowStrength,
                                  ),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: palette == selected
                          ? Icon(
                              Icons.check,
                              size: 15,
                              color: ThemeData.estimateBrightnessForColor(
                                        palette.accent,
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          selected.labelFor(locale),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: neon.textMuted),
        ),
      ],
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
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.hint = '',
    this.enabled = true,
  });

  final String label;
  final String hint;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final textTheme = Theme.of(context).textTheme;
    final effective = enabled ? neon.accent : neon.textMuted;
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
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
