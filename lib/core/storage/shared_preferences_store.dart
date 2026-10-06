import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// 生产实现，基于 `shared_preferences` 的新异步 API（`SharedPreferencesAsync`）。
///
/// 相比旧的 `SharedPreferences.getInstance()`：
/// * 不缓存整份数据，读操作不会阻塞启动；
/// * Web 直接读写 localStorage，没有额外的镜像缓存；
/// * 每个键独立读写，避免一次 setXxx 触发全量落盘。
class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore({SharedPreferencesAsync? preferences})
    : _prefs = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> readString(String key) => _prefs.getString(key);

  @override
  Future<void> writeString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);

  @override
  Future<Set<String>> keys() async {
    final keys = await _prefs.getKeys();
    return keys.toSet();
  }
}
