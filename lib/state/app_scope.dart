import 'package:flutter/widgets.dart';

import 'prescription_controller.dart';
import 'settings_controller.dart';

/// 应用级控制器集合。
@immutable
class AppControllers {
  const AppControllers({required this.settings, required this.prescriptions});

  final SettingsController settings;
  final PrescriptionController prescriptions;

  /// 释放资源（热重载/测试 teardown 时使用）。
  void dispose() {
    settings.dispose();
    prescriptions.dispose();
  }
}

/// 依赖注入：把控制器挂到 Widget 树上。
///
/// 刻意不使用 `provider`/`riverpod`——本应用只有两个控制器，一个
/// [InheritedWidget] 就够，而且能让「谁订阅了谁」在代码里一目了然
/// （需要重建的地方显式使用 `ListenableBuilder`）。
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.controllers, required super.child});

  final AppControllers controllers;

  static AppControllers of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载：请确认根组件包裹了 AppScope');
    return scope!.controllers;
  }

  static AppControllers? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.controllers;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(oldWidget.controllers, controllers);
}
