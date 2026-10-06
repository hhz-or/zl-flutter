// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '指令';

  @override
  String get generateButton => '获取指令';

  @override
  String get instructionPrefix => '致：';

  @override
  String get footerWarning => '警告：如未完成指令，将立刻派出代行者前往你的位置绞杀';

  @override
  String get footerDisclaimer => '本应用为 Project Moon 同人二创，所有指令均为随机拼装的虚构内容，请勿照做。';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsLanguage => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get settingsGlow => '霓虹发光';

  @override
  String get settingsGlowHint => '发光是逐帧重绘里最贵的一项，动画卡顿时可以调低';

  @override
  String percentValue(int percent) {
    return '$percent%';
  }

  @override
  String get settingsMotion => '动效';

  @override
  String get settingsReduceMotion => '减少动效';

  @override
  String get settingsReduceMotionHint => '直接显示指令，不播放乱码动画';

  @override
  String get settingsAnimationSpeed => '动画速度';

  @override
  String get settingsAnimationSpeedHint => '1.00× 即原版速度';

  @override
  String settingsAnimationSpeedValue(String value) {
    return '$value×';
  }

  @override
  String get settingsGeneration => '生成';

  @override
  String get settingsEasterEgg => '启用彩蛋';

  @override
  String get settingsEasterEggHint => '原版固定按 15% 概率抽取';

  @override
  String get settingsEasterEggRate => '彩蛋概率';

  @override
  String get settingsEasterEggRateHint => '15% 即原版数值';

  @override
  String get settingsStrategy => '抽取策略';

  @override
  String get strategyPureRandom => '纯随机（与原版一致）';

  @override
  String get strategyShuffleBag => '洗牌袋（不重复）';

  @override
  String get settingsReset => '恢复默认';

  @override
  String get closeAction => '关闭';
}
