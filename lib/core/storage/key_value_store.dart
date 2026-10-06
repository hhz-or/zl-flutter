/// 极简键值存储抽象。
///
/// 存在的意义：让「持久化」成为可替换的细节——生产环境用
/// `SharedPreferencesStore`（Web 上落到 localStorage），测试用
/// `InMemoryStore`，两者都不需要任何平台通道。
abstract interface class KeyValueStore {
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);

  Future<void> remove(String key);

  Future<Set<String>> keys();
}

/// 存储键集中管理，避免散落在各处拼字符串。
abstract final class StorageKeys {
  /// 只有设置需要持久化——原版没有历史/收藏之类的状态。
  static const String settings = 'flutter_zl.settings.v1';
}
