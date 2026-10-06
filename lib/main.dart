import 'package:flutter/material.dart';

import 'app.dart';
import 'core/storage/shared_preferences_store.dart';
import 'state/app_scope.dart';
import 'state/prescription_controller.dart';
import 'state/settings_controller.dart';

/// 启动流程：
/// 1. 建好存储与控制器的依赖图（纯 Dart，测试里可整体替换）；
/// 2. 读取设置（失败会兜底，不阻塞启动）；
/// 3. 把设置同步给生成器，然后 `runApp`。
///
/// 注意：刻意没有调用 `usePathUrlStrategy()`。默认的 hash 路由策略在任何静态
/// 托管（GitHub Pages / Cloudflare Pages）上刷新都不会 404。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controllers = AppControllers(
    settings: SettingsController(store: SharedPreferencesStore()),
    prescriptions: PrescriptionController(),
  );
  await controllers.settings.load();
  controllers.prescriptions.applySettings(controllers.settings.value);

  runApp(InstructionApp(controllers: controllers));
}
