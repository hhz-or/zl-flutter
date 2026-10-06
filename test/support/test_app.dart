import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zl/core/storage/in_memory_store.dart';
import 'package:flutter_zl/core/theme/app_theme.dart';
import 'package:flutter_zl/data/instruction_corpus_data.dart';
import 'package:flutter_zl/data/models/app_settings.dart';
import 'package:flutter_zl/domain/instruction_corpus.dart';
import 'package:flutter_zl/l10n/app_localizations.dart';
import 'package:flutter_zl/state/app_scope.dart';
import 'package:flutter_zl/state/prescription_controller.dart';
import 'package:flutter_zl/state/settings_controller.dart';

/// 测试用控制器集合。
class TestHarness {
  TestHarness({
    InMemoryStore? store,
    AppSettings settings = AppSettings.defaults,
    Random? random,
    InstructionCorpus corpus = kBuiltinCorpus,
  }) : store = store ?? InMemoryStore() {
    settingsController = SettingsController(
      store: this.store,
      initial: settings,
    );
    prescriptions = PrescriptionController(
      corpus: corpus,
      random: random ?? Random(20261004),
      settings: settings,
    );
    controllers = AppControllers(
      settings: settingsController,
      prescriptions: prescriptions,
    );
  }

  final InMemoryStore store;

  late final SettingsController settingsController;
  late final PrescriptionController prescriptions;
  late final AppControllers controllers;

  Future<void> loadAll() async {
    await settingsController.load();
    prescriptions.applySettings(settingsController.value);
  }

  void dispose() => controllers.dispose();
}

/// 把被测组件包进最小可用的应用外壳（主题 + 本地化 + 依赖注入）。
Widget wrapWithApp(Widget child, {required AppControllers controllers}) {
  return AppScope(
    controllers: controllers,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// 构造 harness → 载入设置 → 挂载。
Future<TestHarness> pumpWithApp(
  WidgetTester tester,
  Widget child, {
  TestHarness? harness,
  AppSettings settings = AppSettings.defaults,
  bool load = true,
}) async {
  final resolved = harness ?? TestHarness(settings: settings);
  if (load) {
    await resolved.loadAll();
  }
  await tester.pumpWidget(
    wrapWithApp(child, controllers: resolved.controllers),
  );
  await tester.pump();
  return resolved;
}

/// 取某语言的文案对象（默认简体中文）。
Future<AppLocalizations> loadL10n([
  Locale locale = const Locale('zh'),
]) => AppLocalizations.delegate.load(locale);

/// 固定测试环境的「系统语言」（`flutter_test` 默认是 `en_US`）。
void pinPlatformLocale(
  WidgetTester tester, [
  Locale locale = const Locale('zh'),
]) {
  tester.platformDispatcher.localesTestValue = <Locale>[locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}
