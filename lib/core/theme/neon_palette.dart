import 'package:flutter/material.dart';

/// 霓虹配色方案。
///
/// 原版网页只有一种主色（`--neon-blue: #00d2ff`）。这里把它做成可切换的色板，
/// **默认值与原版完全一致**。
@immutable
class NeonPalette {
  const NeonPalette({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.accent,
  });

  /// 持久化用的稳定标识，改动会导致旧设置回退到默认色板。
  final String id;

  final String labelZh;
  final String labelEn;

  /// 霓虹主色。
  final Color accent;

  /// 原版配色：`--neon-blue: #00d2ff`。
  static const NeonPalette indexBlue = NeonPalette(
    id: 'index_blue',
    labelZh: '食指蓝',
    labelEn: 'Index Blue',
    accent: Color(0xFF00D2FF),
  );

  static const NeonPalette prescriptionViolet = NeonPalette(
    id: 'prescription_violet',
    labelZh: '指令紫',
    labelEn: 'Prescript Violet',
    accent: Color(0xFFA45BFF),
  );

  static const NeonPalette mistRed = NeonPalette(
    id: 'mist_red',
    labelZh: '血雾红',
    labelEn: 'Mist Red',
    accent: Color(0xFFFF3B5C),
  );

  static const NeonPalette egoGreen = NeonPalette(
    id: 'ego_green',
    labelZh: '自我绿',
    labelEn: 'EGO Green',
    accent: Color(0xFF2BE98B),
  );

  static const NeonPalette amberGold = NeonPalette(
    id: 'amber_gold',
    labelZh: '琥珀金',
    labelEn: 'Amber Gold',
    accent: Color(0xFFFFB020),
  );

  static const NeonPalette sakuraPink = NeonPalette(
    id: 'sakura_pink',
    labelZh: '樱花粉',
    labelEn: 'Sakura Pink',
    accent: Color(0xFFFF6EC7),
  );

  static const NeonPalette boneWhite = NeonPalette(
    id: 'bone_white',
    labelZh: '骸骨白',
    labelEn: 'Bone White',
    accent: Color(0xFFE6F1FF),
  );

  static const List<NeonPalette> values = <NeonPalette>[
    indexBlue,
    prescriptionViolet,
    mistRed,
    egoGreen,
    amberGold,
    sakuraPink,
    boneWhite,
  ];

  static NeonPalette byId(String id) {
    for (final palette in values) {
      if (palette.id == id) {
        return palette;
      }
    }
    return indexBlue;
  }

  /// 按当前语言取展示名。
  String labelFor(Locale locale) =>
      locale.languageCode == 'en' ? labelEn : labelZh;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NeonPalette && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NeonPalette($id)';
}
