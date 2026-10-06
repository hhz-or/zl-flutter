import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zl/core/storage/in_memory_store.dart';
import 'package:flutter_zl/core/storage/key_value_store.dart';
import 'package:flutter_zl/data/models/app_settings.dart';
import 'package:flutter_zl/state/settings_controller.dart';

void main() {
  group('SettingsController.load', () {
    test('空存储时使用默认值并标记为已加载', () async {
      final controller = SettingsController(store: InMemoryStore());
      expect(controller.isLoaded, isFalse);

      await controller.load();

      expect(controller.isLoaded, isTrue);
      expect(controller.value, AppSettings.defaults);
      expect(controller.lastError, isNull);
    });

    test('默认值就是原版网页的行为', () {
      const settings = AppSettings.defaults;
      expect(settings.reduceMotion, isFalse);
      expect(settings.animationSpeed, 1);
      expect(settings.easterEggEnabled, isTrue);
      expect(
        settings.easterEggRate,
        AppSettings.originalEasterEggRate,
        reason: '原版 script.js 硬编码 Math.random() < 0.15',
      );
      expect(AppSettings.originalEasterEggRate, 0.15);
    });

    test('读取已持久化的设置', () async {
      final store = InMemoryStore(<String, String>{
        StorageKeys.settings: jsonEncode(
          const AppSettings(
            reduceMotion: true,
            animationSpeed: 2,
            easterEggEnabled: false,
            easterEggRate: 0.5,
          ).toJson(),
        ),
      });

      final controller = SettingsController(store: store);
      await controller.load();

      expect(controller.value.reduceMotion, isTrue);
      expect(controller.value.animationSpeed, 2);
      expect(controller.value.easterEggEnabled, isFalse);
      expect(controller.value.easterEggRate, 0.5);
    });

    test('损坏的 JSON 回退到默认值并记录错误，不抛异常', () async {
      final store = InMemoryStore(<String, String>{
        StorageKeys.settings: '{ this is not json',
      });
      final controller = SettingsController(store: store);

      await controller.load();

      expect(controller.value, AppSettings.defaults);
      expect(controller.lastError, isNotNull);
      expect(controller.isLoaded, isTrue);
    });

    test('JSON 合法但不是对象时同样回退', () async {
      final store = InMemoryStore(<String, String>{
        StorageKeys.settings: '[1,2,3]',
      });
      final controller = SettingsController(store: store);

      await controller.load();

      expect(controller.value, AppSettings.defaults);
    });

    test('1e400 之类的超范围数字只影响单个字段，不会丢掉整份设置', () async {      // `1e400` 是合法 JSON，`jsonDecode` 会得到 `Infinity`；
      // 不检查 `isFinite` 的话 `clamp` 会抛 `UnsupportedError`。
      final store = InMemoryStore(<String, String>{
        StorageKeys.settings:
            '{"reduceMotion":true,"animationSpeed":1e400,'
            '"easterEggRate":-1e400,"easterEggEnabled":false}',
      });
      final controller = SettingsController(store: store);

      await controller.load();

      expect(controller.lastError, isNull);
      expect(controller.value.reduceMotion, isTrue, reason: '正常字段必须保留');
      expect(controller.value.easterEggEnabled, isFalse);
      expect(
        controller.value.animationSpeed,
        AppSettings.defaults.animationSpeed,
        reason: '越界字段单独回退',
      );
      expect(
        controller.value.easterEggRate,
        AppSettings.defaults.easterEggRate,
      );
    });
    test('白名单外的色板 id 在读取时被收敛回默认', () async {
      final store = InMemoryStore(<String, String>{
        StorageKeys.settings:
            '{"paletteId":"not_a_real_palette","reduceMotion":true}',
      });
      final controller = SettingsController(store: store);

      await controller.load();

      expect(controller.value.paletteId, AppSettings.defaults.paletteId);
      expect(controller.value.reduceMotion, isTrue, reason: '其它字段不受影响');
    });

    test('合法色板 id 原样保留', () {
      expect(
        SettingsController.normalize(
          const AppSettings(paletteId: 'mist_red'),
        ).paletteId,
        'mist_red',
      );
      expect(
        SettingsController.normalize(
          const AppSettings(paletteId: 'index_blue'),
        ).paletteId,
        'index_blue',
      );
    });
  });

  group('AppSettings 序列化', () {
    test('toJson/fromJson 往返一致', () {
      const settings = AppSettings(
        reduceMotion: true,
        animationSpeed: 1.75,
        easterEggEnabled: false,
        easterEggRate: 0.42,
      );
      expect(AppSettings.fromJson(settings.toJson()), settings);
    });

    test('fromJson({}) 等于默认值', () {
      expect(AppSettings.fromJson(<String, Object?>{}), AppSettings.defaults);
    });

    test('多余字段被忽略', () {
      final parsed = AppSettings.fromJson(<String, Object?>{
        'reduceMotion': true,
        'paletteId': 'mist_red',
        'historyLimit': 42,
      });
      expect(parsed.reduceMotion, isTrue);
      expect(parsed.animationSpeed, AppSettings.defaults.animationSpeed);
    });

    test('数值被夹取到合法区间', () {
      final parsed = AppSettings.fromJson(<String, Object?>{
        'animationSpeed': 99,
        'easterEggRate': -3,
      });
      expect(parsed.animationSpeed, 3);
      expect(parsed.easterEggRate, 0);
    });

    test('类型不对的字段回退到默认值', () {
      final parsed = AppSettings.fromJson(<String, Object?>{
        'reduceMotion': 'yes',
        'animationSpeed': 'fast',
        'easterEggEnabled': 1,
        'easterEggRate': null,
      });
      expect(parsed, AppSettings.defaults);
    });
  });

  group('SettingsController.save', () {
    test('写入后落盘并通知监听者', () async {
      final store = InMemoryStore();
      final controller = SettingsController(store: store);
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.update((s) => s.copyWith(animationSpeed: 2));

      expect(controller.value.animationSpeed, 2);
      expect(notified, 1);

      final persisted =
          jsonDecode(store.snapshot[StorageKeys.settings]!)
              as Map<String, Object?>;
      expect(persisted['animationSpeed'], 2);
    });

    test('保存相同的值不会重复通知或写入', () async {
      final store = InMemoryStore();
      final controller = SettingsController(
        store: store,
        initial: const AppSettings(reduceMotion: true),
      );
      await controller.save(AppSettings.defaults);
      expect(store.snapshot, hasLength(1));

      var notified = 0;
      controller.addListener(() => notified++);
      await controller.save(AppSettings.defaults);

      expect(notified, 0);
      expect(store.snapshot, hasLength(1));
    });

    test('reset 恢复默认值并落盘', () async {
      final store = InMemoryStore();
      final controller = SettingsController(
        store: store,
        initial: const AppSettings(animationSpeed: 3),
      );

      await controller.reset();

      expect(controller.value, AppSettings.defaults);
      final persisted =
          jsonDecode(store.snapshot[StorageKeys.settings]!)
              as Map<String, Object?>;
      expect(persisted['animationSpeed'], 1);
    });

    test('写入失败时记录错误但不抛出', () async {
      final store = InMemoryStore()..throwOnWrite = true;
      final controller = SettingsController(store: store);

      await controller.update((s) => s.copyWith(reduceMotion: true));

      expect(controller.value.reduceMotion, isTrue);
      expect(controller.lastError, isNotNull);
    });
  });
}
