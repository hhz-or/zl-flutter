import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/neon_palette.dart';
import 'data/models/app_settings.dart';
import 'features/generator/generator_page.dart';
import 'features/settings/settings_dialog.dart';
import 'l10n/app_localizations.dart';
import 'state/app_scope.dart';

/// 支持的语言。列表顺序即回退顺序：无法匹配系统语言时使用简体中文
/// （原版网页只有中文）。
const List<Locale> kSupportedLocales = <Locale>[Locale('zh'), Locale('en')];

/// 应用根组件。
///
/// 页面是原版 `index.html` 的 1:1 复刻，另外在右上角加了设置按钮。
class InstructionApp extends StatefulWidget {
  const InstructionApp({super.key, required this.controllers});

  final AppControllers controllers;

  @override
  State<InstructionApp> createState() => _InstructionAppState();
}

class _InstructionAppState extends State<InstructionApp> {
  @override
  void initState() {
    super.initState();
    // 设置变化 → 同步给生成器（彩蛋开关/概率、抽取策略）。
    widget.controllers.settings.addListener(_applySettings);
    _applySettings();
  }

  @override
  void dispose() {
    widget.controllers.settings.removeListener(_applySettings);
    super.dispose();
  }

  void _applySettings() {
    widget.controllers.prescriptions.applySettings(
      widget.controllers.settings.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controllers.settings,
      builder: (context, _) {
        final settings = widget.controllers.settings.value;
        return AppScope(
          controllers: widget.controllers,
          child: MaterialApp(
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            // 只有一种主题：原版的纯黑霓虹，可换色板与发光强度。
            theme: AppTheme.build(
              palette: NeonPalette.byId(settings.paletteId),
              glowStrength: settings.glowStrength,
            ),
            locale: _localeFor(settings.language),
            localeResolutionCallback: _resolveLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: const HomePage(),
            builder: (context, child) => _MotionOverride(
              reduceMotion: settings.reduceMotion,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  static Locale? _localeFor(AppLanguage language) => switch (language) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.en => const Locale('en'),
  };

  static Locale _resolveLocale(Locale? locale, Iterable<Locale> supported) {
    if (locale?.languageCode == 'en') {
      return const Locale('en');
    }
    return const Locale('zh');
  }
}

/// 主页：原版页面 + 右上角设置按钮。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    return Scaffold(
      backgroundColor: neon.background,
      body: const Stack(
        children: <Widget>[
          Positioned.fill(child: GeneratorPage()),
          _SettingsButton(),
        ],
      ),
    );
  }
}

/// 右上角的设置按钮——本应用相对原版**唯一**新增的控件。
class _SettingsButton extends StatefulWidget {
  const _SettingsButton();

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final neon = context.neon;
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Tooltip(
            message: l10n.settingsTitle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: IconButton(
                key: const Key('settings-button'),
                onPressed: () => showSettingsDialog(context),
                iconSize: 20,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                icon: Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: _hovered ? neon.accent : neon.textMuted,
                  shadows: _hovered ? neon.softGlow : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 把「设置里手动开启的减少动效」注入 [MediaQuery]，这样连 Flutter 内置的
/// 隐式动画（弹窗过渡、`AnimatedContainer` 等）也会一并关闭。
class _MotionOverride extends StatelessWidget {
  const _MotionOverride({required this.reduceMotion, required this.child});

  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!reduceMotion || media.disableAnimations) {
      return child;
    }
    return MediaQuery(
      data: media.copyWith(disableAnimations: true),
      child: child,
    );
  }
}
