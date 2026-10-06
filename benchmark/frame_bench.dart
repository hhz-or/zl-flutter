// 帧时间基准（不属于应用本身，只在需要量化卡顿时手动运行）。
//
// 用法：
//   flutter build windows --profile -t benchmark/frame_bench.dart
//   ./build/windows/x64/runner/Profile/flutter_zl.exe
//
// 它会启动真实的应用外壳，按固定节奏不断生成新指令（也就是不断重播乱码动画），
// 用 `SchedulerBinding.addTimingsCallback` 采集每帧的 build / raster 耗时，
// 打到 stdout 后自行退出。
//
// 关注 raster p50/p90：这是发光文字逐帧重绘的主要成本所在。

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_zl/app.dart';
import 'package:flutter_zl/core/storage/in_memory_store.dart';
import 'package:flutter_zl/state/app_scope.dart';
import 'package:flutter_zl/state/prescription_controller.dart';
import 'package:flutter_zl/state/settings_controller.dart';

/// 每个用例持续多久（毫秒）。
const int _kDurationMs = 24000;

/// 每隔多久生成一条新指令（毫秒）。略大于一次动画的时长。
const int _kGenerateEveryMs = 2600;

/// 前 3 秒是启动与首帧，不计入统计。
const int _kWarmupMs = 3000;

class _Stats {
  _Stats(this.label, this.samples);

  final String label;
  final List<double> samples;

  double _p(double q) {
    if (samples.isEmpty) {
      return 0;
    }
    final sorted = List<double>.from(samples)..sort();
    final index = ((sorted.length - 1) * q).round();
    return sorted[index];
  }

  @override
  String toString() {
    if (samples.isEmpty) {
      return '$label: 无样本';
    }
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    return '$label  n=${samples.length}  '
        'mean=${mean.toStringAsFixed(2)}ms  '
        'p50=${_p(0.5).toStringAsFixed(2)}ms  '
        'p90=${_p(0.9).toStringAsFixed(2)}ms  '
        'p99=${_p(0.99).toStringAsFixed(2)}ms  '
        'max=${_p(1).toStringAsFixed(2)}ms';
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controllers = AppControllers(
    settings: SettingsController(store: InMemoryStore()),
    prescriptions: PrescriptionController(random: Random(20261004)),
  );
  await controllers.settings.load();
  controllers.prescriptions.applySettings(controllers.settings.value);

  final builds = <double>[];
  final rasters = <double>[];
  final totals = <double>[];
  final started = DateTime.now();

  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    if (elapsed < _kWarmupMs) {
      return;
    }
    for (final timing in timings) {
      builds.add(timing.buildDuration.inMicroseconds / 1000);
      rasters.add(timing.rasterDuration.inMicroseconds / 1000);
      totals.add(timing.totalSpan.inMicroseconds / 1000);
    }
  });

  Timer.periodic(const Duration(milliseconds: _kGenerateEveryMs), (_) {
    controllers.prescriptions.generate();
  });

  runApp(InstructionApp(controllers: controllers));

  await Future<void>.delayed(const Duration(milliseconds: _kDurationMs));

  stdout.writeln('');
  stdout.writeln('=== frame bench (${Platform.operatingSystem}, '
      '${_kDurationMs ~/ 1000}s) ===');
  stdout.writeln(_Stats('build ', builds));
  stdout.writeln(_Stats('raster', rasters));
  stdout.writeln(_Stats('total ', totals));
  final budget = 1000 / 60;
  final over = rasters.where((value) => value > budget).length;
  stdout.writeln('raster > ${budget.toStringAsFixed(2)}ms (60fps 预算): '
      '$over / ${rasters.length} 帧');
  stdout.writeln('');
  exit(0);
}
