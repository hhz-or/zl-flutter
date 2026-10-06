import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Page title; the original site uses <title>指令</title>
  ///
  /// In en, this message translates to:
  /// **'Instruction'**
  String get appTitle;

  /// Original: <button id="trigger-btn">获取指令</button>
  ///
  /// In en, this message translates to:
  /// **'Get Instruction'**
  String get generateButton;

  /// Prefix of every instruction; original hard-codes 致：
  ///
  /// In en, this message translates to:
  /// **'To: '**
  String get instructionPrefix;

  /// Original .footer-note text
  ///
  /// In en, this message translates to:
  /// **'Warning: failure to complete the instruction will result in a Proselyte being dispatched to your location.'**
  String get footerWarning;

  /// Second footer line, below the original warning
  ///
  /// In en, this message translates to:
  /// **'For entertainment only — please do not act on it.'**
  String get footerDisclaimer;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// Label of the free-form colour picker
  ///
  /// In en, this message translates to:
  /// **'Accent colour'**
  String get settingsThemeColor;

  /// One-tap restore of the original #00d2ff
  ///
  /// In en, this message translates to:
  /// **'Reset to blue'**
  String get settingsAccentReset;

  /// No description provided for @colorHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get colorHue;

  /// No description provided for @colorSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get colorSaturation;

  /// No description provided for @colorBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get colorBrightness;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @settingsGlow.
  ///
  /// In en, this message translates to:
  /// **'Neon glow'**
  String get settingsGlow;

  /// No description provided for @settingsGlowHint.
  ///
  /// In en, this message translates to:
  /// **'Glow is the most expensive thing to draw every frame — lower it if the animation stutters'**
  String get settingsGlowHint;

  /// No description provided for @percentValue.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String percentValue(int percent);

  /// No description provided for @settingsMotion.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get settingsMotion;

  /// No description provided for @settingsReduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsReduceMotion;

  /// No description provided for @settingsReduceMotionHint.
  ///
  /// In en, this message translates to:
  /// **'Reveal the instruction instantly instead of unscrambling it'**
  String get settingsReduceMotionHint;

  /// No description provided for @settingsAnimationSpeed.
  ///
  /// In en, this message translates to:
  /// **'Animation speed'**
  String get settingsAnimationSpeed;

  /// No description provided for @settingsAnimationSpeedHint.
  ///
  /// In en, this message translates to:
  /// **'1.00× is the original speed'**
  String get settingsAnimationSpeedHint;

  /// No description provided for @settingsAnimationSpeedValue.
  ///
  /// In en, this message translates to:
  /// **'{value}×'**
  String settingsAnimationSpeedValue(String value);

  /// No description provided for @settingsGeneration.
  ///
  /// In en, this message translates to:
  /// **'Generation'**
  String get settingsGeneration;

  /// No description provided for @settingsEasterEgg.
  ///
  /// In en, this message translates to:
  /// **'Enable easter eggs'**
  String get settingsEasterEgg;

  /// No description provided for @settingsEasterEggHint.
  ///
  /// In en, this message translates to:
  /// **'The original always draws with a 15% chance'**
  String get settingsEasterEggHint;

  /// No description provided for @settingsEasterEggRate.
  ///
  /// In en, this message translates to:
  /// **'Easter egg chance'**
  String get settingsEasterEggRate;

  /// No description provided for @settingsEasterEggRateHint.
  ///
  /// In en, this message translates to:
  /// **'15% is the original value'**
  String get settingsEasterEggRateHint;

  /// No description provided for @settingsStrategy.
  ///
  /// In en, this message translates to:
  /// **'Draw strategy'**
  String get settingsStrategy;

  /// No description provided for @strategyPureRandom.
  ///
  /// In en, this message translates to:
  /// **'Pure random (original)'**
  String get strategyPureRandom;

  /// No description provided for @strategyShuffleBag.
  ///
  /// In en, this message translates to:
  /// **'Shuffle bag (no repeats)'**
  String get strategyShuffleBag;

  /// No description provided for @settingsReset.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults'**
  String get settingsReset;

  /// No description provided for @closeAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
