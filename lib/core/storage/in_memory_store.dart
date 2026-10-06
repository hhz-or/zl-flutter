import 'key_value_store.dart';

/// 内存实现：测试与兜底场景使用。
class InMemoryStore implements KeyValueStore {
  InMemoryStore([Map<String, String>? seed])
    : _data = <String, String>{...?seed};

  final Map<String, String> _data;

  /// 便于测试断言当前落盘内容。
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);

  /// 模拟写入失败，用于验证控制器的容错路径。
  bool throwOnWrite = false;

  @override
  Future<String?> readString(String key) async => _data[key];

  @override
  Future<void> writeString(String key, String value) async {
    if (throwOnWrite) {
      throw StateError('InMemoryStore: write disabled');
    }
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }

  @override
  Future<Set<String>> keys() async => _data.keys.toSet();
}
