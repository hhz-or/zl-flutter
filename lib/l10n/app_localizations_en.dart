// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Instruction';

  @override
  String get generateButton => 'Get Instruction';

  @override
  String get instructionPrefix => 'To: ';

  @override
  String get footerWarning =>
      'Warning: failure to complete the instruction will result in a Proselyte being dispatched to your location.';

  @override
  String get footerDisclaimer =>
      'A fan-made Project Moon tribute. Every instruction is randomly generated fiction — please do not act on it.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get settingsGlow => 'Neon glow';

  @override
  String get settingsGlowHint =>
      'Glow is the most expensive thing to draw every frame — lower it if the animation stutters';

  @override
  String percentValue(int percent) {
    return '$percent%';
  }

  @override
  String get settingsMotion => 'Motion';

  @override
  String get settingsReduceMotion => 'Reduce motion';

  @override
  String get settingsReduceMotionHint =>
      'Reveal the instruction instantly instead of unscrambling it';

  @override
  String get settingsAnimationSpeed => 'Animation speed';

  @override
  String get settingsAnimationSpeedHint => '1.00× is the original speed';

  @override
  String settingsAnimationSpeedValue(String value) {
    return '$value×';
  }

  @override
  String get settingsGeneration => 'Generation';

  @override
  String get settingsEasterEgg => 'Enable easter eggs';

  @override
  String get settingsEasterEggHint =>
      'The original always draws with a 15% chance';

  @override
  String get settingsEasterEggRate => 'Easter egg chance';

  @override
  String get settingsEasterEggRateHint => '15% is the original value';

  @override
  String get settingsStrategy => 'Draw strategy';

  @override
  String get strategyPureRandom => 'Pure random (original)';

  @override
  String get strategyShuffleBag => 'Shuffle bag (no repeats)';

  @override
  String get settingsReset => 'Restore defaults';

  @override
  String get closeAction => 'Close';
}
