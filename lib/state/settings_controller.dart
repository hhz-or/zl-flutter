import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/key_value_store.dart';
import '../core/theme/neon_palette.dart';
import '../data/models/app_settings.dart';

/// 设置控制器：内存中的唯一事实来源 + 防抖落盘。
///
/// 纯 [ChangeNotifier]（没有引入任何状态管理依赖），因此可以在纯 Dart
/// 测试里直接构造与断言。
class SettingsController extends ChangeNotifier {
  SettingsController({
    required KeyValueStore store,
    AppSettings initial = AppSettings.defaults,
  }) : _store = store,
       _value = initial;

  final KeyValueStore _store;

  AppSettings _value;
  bool _loaded = false;
  Object? _lastError;

  /// 当前设置。
  AppSettings get value => _value;

  /// 是否已经完成首次读取。
  bool get isLoaded => _loaded;

  /// 最近一次持久化/读取失败的原因，成功时清空。
  Object? get lastError => _lastError;

  /// 从存储读取设置。任何异常都会回退到默认值，绝不阻断启动。
  Future<void> load() async {
    try {
      final raw = await _store.readString(StorageKeys.settings);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) {
          _value = normalize(AppSettings.fromJson(decoded));
        } else if (decoded is Map) {
          _value = normalize(
            AppSettings.fromJson(decoded.cast<String, Object?>()),
          );
        }
      }
      _lastError = null;
    } on Object catch (error) {
      _lastError = error;
      _value = AppSettings.defaults;
    }
    _loaded = true;
    notifyListeners();
  }

  /// 用 [transform] 派生新设置并立即落盘。
  Future<void> update(AppSettings Function(AppSettings current) transform) =>
      save(transform(_value));

  /// 直接写入一份新设置。
  Future<void> save(AppSettings next) async {
    if (next == _value) {
      return;
    }
    _value = next;
    notifyListeners();
    await _persist();
  }

  /// 恢复默认值。
  Future<void> reset() => save(AppSettings.defaults);

  /// 把明显非法的取值收敛到合法值。
  ///
  /// 目前只有色板 id：模型层不认识色板列表（那是 `core/theme` 的事），
  /// 所以「不在白名单就回退默认」放在这里做，避免脏值一直被写回存储。
  @visibleForTesting
  static AppSettings normalize(AppSettings settings) {
    final palette = NeonPalette.byId(settings.paletteId);
    return palette.id == settings.paletteId
        ? settings
        : settings.copyWith(paletteId: palette.id);
  }

  Future<void> _persist() async {
    try {
      await _store.writeString(StorageKeys.settings, jsonEncode(_value.toJson()));
      _lastError = null;
    } on Object catch (error) {
      _lastError = error;
      debugPrint('SettingsController: 保存失败 ($error)');
    }
  }
}
