# Flutter 架构选型研究报告（霓虹指令生成器）

> **目标环境**：Flutter 3.47.5 stable / Dart 3.13.4（本机 `flutter --version` 实测）
> **目标平台**：Web + 桌面 + 移动端 ｜ **约束**：依赖最小化、`flutter analyze` 零问题、真实单元 + widget 测试
> **调研日期**：2026-10-02。全部版本号 / likes / pub points / 发布日期均当日从 pub.dev 实时抓取。

## 00. 与仓库现状的差异（先读这一节）

调研时发现本仓库**已经存在一套可运行的实现**（`lib/main.dart`、`lib/core/`、`lib/data/`、`lib/domain/`、`lib/features/`、`lib/state/`、`lib/l10n/`，以及 `test/domain/`、`test/widget_test.dart`）。经逐项核对，**现有实现已独立落到本报告的绝大多数结论上**。因此本报告对本仓库而言，**主要是"确认与理由补充"，而非"改造方案"**。

### 已完全一致（无需任何改动）

| 项 | 现状 | 本报告结论 |
|---|---|---|
| **持久化 API** | `core/storage/shared_preferences_store.dart` 用 **`SharedPreferencesAsync`**，并在注释里明确对比了旧的 `getInstance()` | §2.3 完全一致 —— 已避开过时 API |
| **可测试存储抽象** | `core/storage/key_value_store.dart` 定义 `KeyValueStore` 接口；`in_memory_store.dart` 内存实现；`core/services/test_doubles.dart` | §2.3 / §6.3 完全一致 —— **无需任何 mock 框架或插件 mock** |
| **状态管理** | `state/settings_controller.dart` 与 `prescription_controller.dart` 都是纯 `ChangeNotifier`，**刻意不引入状态管理依赖**，因此可在纯 Dart 中测试；`state/app_scope.dart` 用手写 `InheritedWidget` 做 DI | §1 的 (a) 方案 —— 见下方"唯一的可选项" |
| **本地化** | `l10n.yaml` 已含 `arb-dir` / `template-arb-file` / `output-localization-file` / `output-class` / `output-dir` / **`nullable-getter: false`**；已有 `lib/l10n/app_localizations.dart` + `_en` + `_zh` | §3 完全一致（`nullable-getter: false` 正是推荐值，省掉每处 `!`） |
| **`intl` 直接依赖** | `intl: ^0.20.3` 已在 `dependencies` | §3.1 完全一致 —— 已避开 `implicit_depend_on_referenced_packages` 警告 |
| **Lint** | `flutter_lints: ^6.0.0` | §7.3 结论一致 —— 未引入 `very_good_analysis` |
| **字体** | 本地 Inter + 霞鹜文楷，配 `tools/subset_fonts.py` 裁剪 | **比 §11 所排除的 `google_fonts` 更优** —— 避免运行时下载字体在离线/内网失败 |
| **包名/版本** | `environment.sdk: ^3.13.4` | 与本机 Dart 3.13.4 精确匹配 |

### 唯一的可选项：是否引入 Riverpod

这是本报告与现状**唯一的分歧点**。现有方案是 §1 的 **(a) 纯 `ChangeNotifier` + 手写 `InheritedWidget`**：

- **不引入（推荐保持现状）**：现有 controller 已是纯 `ChangeNotifier` 且**可纯 Dart 测试**，说明 §1 中「Riverpod 的主要卖点（脱离 widget 测试）」**已经被手写方案以更低的代价实现了**。`AppScope` 的注释也说明其设计目标是"让谁订阅了谁在代码里一目了然"。对一个约 5 份状态的应用，这是恰当选择。
- **引入 `flutter_riverpod: ^3.4.3` 的收益**：仅当出现以下**实际**痛点时才值得 —— ① 多个 controller 需要互相监听/派生状态；② 需要 `AsyncValue` 式的 loading/error 统一建模；③ `AppScope` 的继承样板开始显著膨胀。此外需承担 §0-A 的 Web/WASM 标记争议（虽是误报，但要在 CI 真跑 `flutter build web` 验证）。
- **结论**：**当前不建议改动**。§1.3 的代码示例保留作为"若将来迁移"的目标形态参考。

### 其它可选增量（均非必需）

| 项 | 说明 |
|---|---|
| `go_router: ^18.0.2` | 现有实现未使用路由包。**只有**在需要「Web 浏览器后退键语义化」「设置/历史页 URL 直达可分享」「深链接」时才值得引入（§4）。若产品定位是单屏工具，维持现状即可 |
| `flutter_web_plugins` + `usePathUrlStrategy()` | 仅当决定放弃默认 hash URL、改用干净 path URL 时才需要（§4.2）。**注意必须先配好静态托管的 rewrite**，否则刷新 404 |
| `cupertino_icons: ^1.0.8` → `^2.0.0` | 最新 2.0.0（2026-09-29，`sdk: ^3.12.0`）。低优先级 |
| `analysis_options.yaml` 加严 | 现有仅 `include: package:flutter_lints/flutter.yaml`。若「零问题」是硬指标，建议补上 §7.2 的 20 条规则（尤其 `unawaited_futures`、`depend_on_referenced_packages`、`require_trailing_commas`） |
| 金图测试 | 现有 `test/` 尚无 golden。若需要，用内置 `matchesGoldenFile()`，**不要**用已废弃的 `golden_toolkit`（§6.3） |

### 与现状的目录命名差异（无需对齐）

§7.1 提议的 `lib/` 树中 `core/storage/`、`core/services/`、`data/models/`、`domain/`、`l10n/` **均已存在**，仅命名与我的提议略有出入（现用 `state/` 与顶层 `domain/`，我提议 `features/*/application/` 与 `features/*/domain/`）。现有布局已按职责清晰分层且自带 `test/` 对应结构，**保留既有约定优先，不必为对齐本报告搬动文件**。

## 0. 三个必须先知道的坑

| # | 问题 | 影响 | 处置 |
|---|---|---|---|
| **A** | `flutter_riverpod` 3.x 把 `flutter_test` 写进**运行时** `dependencies`（2.x 没有）。pub.dev 因此标记 Web/WASM 不支持，评分 **140/160** | 触及「Web 支持 + 零 analyze 问题」验收 | **仍可用**。维护者确认 `flutter_test` 仅服务 `ProviderContainer.test`，Web 构建时被 tree-shake（[issue #4312](https://github.com/rrousselGit/riverpod/issues/4312)）。须写入风险登记并在 CI 真跑 `flutter build web` |
| **B** | `flutter_adaptive_scaffold` 已 **discontinued**（2025-05-06 后停更），见 [flutter/flutter#162965](https://github.com/flutter/flutter/issues/162965) | 网上多数「Flutter 自适应布局」教程都推它 | **不要用**，改用内置 `LayoutBuilder` + 自定义断点（§8） |
| **C** | `isar` 稳定版 `3.1.0+1` 发布于 **2023-04-25**，`environment.sdk` = `>=2.17.0 <3.0.0`；`hive` 为 `>=2.12.0 <3.0.0`（2022-06-30） | **Dart 3.13.4 下 `pub get` 直接解析失败** | **绝对不要用**（§2） |

## 1. 状态管理

### 1.1 候选（2026-10-02 抓取）

| 方案 | 最新版 | Dart SDK | 发布日 | likes | points |
|---|---|---|---|---|---|
| `provider` | 6.1.5+1 | `>=2.12.0 <4.0.0` | 2025-08-19 | 11008 | 150/160 |
| `flutter_riverpod` | 3.4.3 | `^3.12.0` | 2026-09-03 | 2910 | **140/160** |
| `riverpod`（纯 Dart） | 3.4.3 | `^3.12.0` | 2026-09-03 | 4033 | 160/160 |
| `flutter_bloc` | 9.1.1 | `>=2.14.0 <4.0.0` | 2025-05-02 | 8082 | 160/160 |
| `signals` | 7.1.0 | `^3.5.0` | 2026-05-29 | 710 | 160/160 |

- **(a) 裸 `ChangeNotifier`/`ValueNotifier`/`InheritedNotifier`** — 零依赖（均在 `flutter/foundation`）。缺点：DI 需手写 `InheritedWidget` 样板，跨 widget 读取靠 `BuildContext`，`dispose` 易漏。
- **(b) `provider` 6.1.5+1** — 13 个月未更新，但它是 `flutter_bloc` 的传递依赖、likes 过万、API 面极小，属「事实冻结」而非废弃。只想加一个包时最省心。
- **(c) `flutter_riverpod` 3.x** — 编译期安全 DI、`AsyncValue` 自动处理 loading/error、`ProviderContainer.test`、可脱离 `BuildContext` 读取。代价：概念多，且有 §0-A 的 web 标记。
- **(d) `signals` 7.1.0** — 细粒度响应式优雅，但生态与文档体量远小于 Riverpod，协作风险高。
- **(e) `flutter_bloc` 9.1.1** — 严谨，但对「点按钮生成一句话」是明显过度设计。

### 1.2 推荐：`flutter_riverpod: ^3.4.3`，**不用代码生成**

1. 本项目真正需要的是 **DI + 可独立测试的 Notifier**。`ProviderContainer` 让「纯 Dart 单测中 new Notifier 并注入假仓储」成为一行代码；`provider` 需 `pumpWidget` 才能做到。
2. 历史 / 收藏 / 主题 / 语言 / 设置共 5 份状态共享同一持久化层，Riverpod 的依赖图天然解决；`provider` 需嵌套 `ProxyProvider`。
3. 省掉 `riverpod_generator` + `riverpod_annotation` + `build_runner` 三个依赖与整套 codegen 步骤。Riverpod 3 **完整支持手写 provider**，codegen 是可选路径（[官方 Getting started](https://riverpod.dev/docs/introduction/getting_started) 把 `flutter pub add flutter_riverpod` 列为独立选项）。
4. 若最终要上 codegen：`riverpod_generator` 4.0.9 + `riverpod_annotation` 4.0.7 + `build_runner` 2.16.1；前两者 pub points 仅 130/160。**本项目规模不建议**。

### 1.3 推荐模式（含 DI 与测试）

```dart
// lib/features/generator/application/generator_controller.dart
// 1) 仓储抽象通过 provider 注入；未 override 即抛错，防止忘记注入
final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => throw UnimplementedError('必须在 ProviderScope 中 override'),
);
final instructionEngineProvider = Provider<InstructionEngine>(
  (ref) => InstructionEngine(random: SeededRandom(DateTime.now().microsecondsSinceEpoch)),
);

class GeneratorState {
  const GeneratorState({required this.current, this.favorites = const {}});
  final Instruction? current;
  final Set<String> favorites;
  GeneratorState copyWith({Instruction? current, Set<String>? favorites}) =>
      GeneratorState(current: current ?? this.current, favorites: favorites ?? this.favorites);
}

class GeneratorController extends Notifier<GeneratorState> {
  @override
  GeneratorState build() => const GeneratorState();

  void generate() {
    final next = ref.read(instructionEngineProvider).next();
    state = state.copyWith(current: next);
    unawaited(ref.read(historyRepositoryProvider).push(next)); // 显式 unawaited
  }
}

final generatorControllerProvider =
    NotifierProvider<GeneratorController, GeneratorState>(GeneratorController.new);
```

```dart
// lib/main.dart —— 真实实现只出现在组合根一次
runApp(UncontrolledProviderScope(
  container: ProviderContainer(overrides: [
    historyRepositoryProvider.overrideWithValue(SharedPrefsHistoryRepository(store)),
  ]),
  child: const App(),
));
```

**隔离测试**（不 override 时会抛异常 —— 这正是我们要的防线）：

```dart
void main() {
  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer(overrides: [
      instructionEngineProvider.overrideWithValue(
        InstructionEngine(random: SeededRandom(42)),      // 固定种子 → 可断言
      ),
      historyRepositoryProvider.overrideWithValue(FakeHistoryRepository()),
    ]);
  });
  tearDown(() => container.dispose());

  test('generate 更新 current 并写入历史', () {
    container.read(generatorControllerProvider.notifier).generate();
    expect(container.read(generatorControllerProvider).current, isNotNull);
    expect(container.read(historyRepositoryProvider).pushedCount, 1);
  });
}
```

Riverpod 3 另提供 `ProviderContainer.test()`（自动 dispose）与 widget 测试中的 `tester.container()`，见 [What's new in Riverpod 3.0](https://riverpod.dev/docs/whats_new)。

## 2. 持久化

### 2.1 候选

| 包 | 最新版 | Dart SDK | 发布日 | discontinued | likes | points | Web |
|---|---|---|---|---|---|---|---|
| `shared_preferences` | **2.5.5** | `^3.9.0` (Flutter ≥3.35) | 2026-03-25 | 否 | 10576 | **160/160** | ✅ WASM |
| `hive_ce` | 2.20.1 | `^3.4.0` | 2026-09-27 | 否 | 570 | 160/160 | ✅ |
| `drift` | 2.35.1 | `>=3.10.0 <4.0.0` | 2026-09-30 | 否 | 2478 | 160/160 | ✅ |
| `sembast` | 3.8.11 | `^3.12.0` | 2026-09-20 | 否 | 1197 | 160/160 | ✅（需 `sembast_web`） |
| `isar` | 3.1.0+1 | **`>=2.17.0 <3.0.0`** | **2023-04-25** | 否（事实停更） | 2448 | 130/160 | ❌ |
| `hive`（原版） | 2.2.3 | **`>=2.12.0 <3.0.0`** | **2022-06-30** | 否（事实停更） | 6260 | 120/160 | ✅ |

**必须避开**：❌ `isar`（SDK 上限 `<3.0.0`，Dart 3.13.4 **解不出依赖**；4.x 一直 `dev` 预发布，止于 `4.0.0-dev.14`/2023-08；社区分支 `isar_community` 仅 161 likes）。❌ `hive` 原版（同因，已由 `hive_ce` 接替）。❌ `golden_toolkit`（`isDiscontinued: true`，§6）。⚠️ `flutter_adaptive_scaffold`（discontinued，§8）。

### 2.2 推荐：`shared_preferences: ^2.5.5`

200 条 × 约 200 字节 JSON ≈ **40 KB**，远低于 localStorage 的 ~5 MiB 上限。官方一方包、160/160、6 平台 + WASM-ready、零 codegen、零 native 库。

> **Web 实现要点**：`shared_preferences_web` 2.4.3 的 `SharedPreferencesAsyncWeb` 把每个值 `json.encode` 后写入 `html.window.localStorage`（源码 `lib/shared_preferences_web.dart:204`）。因此**单条历史必须整体序列化成一个 JSON 字符串**；不要用 `setStringList` 传 200 个元素（那是 200 个 storage item，体积与读取成本更差）。

`hive_ce` 健康但用不上其二级索引与二进制性能；`drift` 对 40 KB 数据属功能过剩且 Web 需 `sqlite3.wasm`。

### 2.3 `getInstance()` 已过时 —— 用异步 API

`shared_preferences` 2.5.5 同时导出两套 API（`lib/shared_preferences.dart` 仅做 re-export）：
`src/shared_preferences_async.dart`（新：`SharedPreferencesAsync`）与 `src/shared_preferences_legacy.dart`（旧：`SharedPreferences.getInstance()`）。

| | 旧 Legacy | **新（推荐）** |
|---|---|---|
| 入口 | `SharedPreferences.getInstance()` | `SharedPreferencesAsync()` |
| 缓存 | 有（一次性读完整个 map） | 无，每次读平台 |
| 同步读 | 可以 | ❌ 全 `Future`；需同步用 `SharedPreferencesWithCache` |

**推荐：定义自己的窄接口，把插件关在 data 层，测试换内存实现（根本不 mock 插件）。**

```dart
// lib/data/sources/key_value_store.dart
abstract interface class KeyValueStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPrefsKeyValueStore implements KeyValueStore {
  SharedPrefsKeyValueStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _prefs;
  @override Future<String?> getString(String key) => _prefs.getString(key);
  @override Future<void> setString(String key, String value) => _prefs.setString(key, value);
  @override Future<void> remove(String key) => _prefs.remove(key);
}

/// 测试用：无插件、无 mock 框架
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};
  @override Future<String?> getString(String key) async => _data[key];
  @override Future<void> setString(String key, String value) async => _data[key] = value;
  @override Future<void> remove(String key) async => _data.remove(key);
}
```

历史仓储（单键 JSON，损坏数据不崩溃）：

```dart
class HistoryRepository {
  HistoryRepository(this._store, {this.maxEntries = 200});
  static const _key = 'history.v1';
  final KeyValueStore _store;
  final int maxEntries;

  Future<List<Instruction>> load() async {
    final raw = await _store.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => Instruction.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException {
      await _store.remove(_key);   // 防御性回滚
      return const [];
    }
  }

  Future<void> push(Instruction item) async {
    final next = [item, ...await load()].take(maxEntries).toList(growable: false);
    await _store.setString(_key, jsonEncode(next.map((e) => e.toJson()).toList()));
  }
}
```

**若要 mock 插件本身**（API 经阅读包源码核实）：
- 旧 API：`SharedPreferences.setMockInitialValues(<String, Object>{...})`（`shared_preferences_legacy.dart:272`）
- 新 API：换平台实例，即官方示例 `shared_preferences-2.5.5/example/test/example_app_test.dart` 的做法：

```dart
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
tearDown(() => SharedPreferencesAsyncPlatform.instance = null); // 必须清理，否则污染后续测试
```

另有 `InMemorySharedPreferencesAsync.withData(Map<String, Object>)` 预置数据。

## 3. 本地化

### 3.1 结论与 `intl` 的直接依赖要求

用 **`flutter_localizations` + ARB + `gen-l10n`** —— Flutter 官方唯一推荐路径（[官方文档](https://docs.flutter.dev/ui/internationalization)）。不引入 `easy_localization` / `intl_utils` / `slang`。

`flutter_localizations` 自身依赖 `intl: ^0.20.3`（依据 [packages/flutter_localizations/pubspec.yaml](https://github.com/flutter/flutter/blob/master/packages/flutter_localizations/pubspec.yaml)），而 `gen-l10n` 生成的代码会 `import 'package:intl/intl.dart'`。Dart 的 `implicit_depend_on_referenced_packages` lint 要求**直接 import 的包必须直接声明** —— 只靠传递依赖能编译，但会产生 analyzer 警告，在你的「零问题」要求下属硬性失败。故 `intl` **必须是直接依赖**（同时开启 `depend_on_referenced_packages` 规则来强制它）。当前 `intl` 最新 **0.20.3**（2026-06-25，6108 likes，160/160，Flutter Favorite），与 SDK 约束一致，无需 `dependency_overrides`。

### 3.2 `l10n.yaml`

选项名经阅读 `flutter_tools/lib/src/localizations/localizations_utils.dart` 与 `commands/generate_localizations.dart` 核实。**`synthetic-package` 已废弃**，其 help 文本现为 `'DEPRECATED. This flag cannot be enabled and should be removed.'` —— 不要再写。

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
output-dir: lib/l10n/generated    # → import 'package:<app>/l10n/generated/app_localizations.dart'
nullable-getter: false            # of(context) 返回非空，省掉每处 !
untranslated-messages-file: build/untranslated.json   # CI 卡口
```

```bash
flutter gen-l10n     # 手动生成（新工具链在 pub get 时也会自动跑）
```

### 3.3 中文 `zh` / `zh_Hans` 与 `MaterialApp` 装配

用 **`app_zh.arb`**（`zh`）即可覆盖简体与繁体；需要区分时再拆 `app_zh_Hans.arb` / `app_zh_Hant.arb` 并在 `supportedLocales` 同时列出。`supportedLocales` 的**第一个**是回退目标，建议 `en` 兜底。

```dart
MaterialApp.router(
  onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('en'), Locale('zh')],   // en 放首位作兜底
  // locale: const Locale('zh'),                          // 调试时强制中文
)
```

`AppLocalizations.localizationsDelegates` 展开即：`AppLocalizations.delegate`、`GlobalMaterialLocalizations.delegate`（Material 内置文案）、`GlobalWidgetsLocalizations.delegate`（文字方向）、`GlobalCupertinoLocalizations.delegate`。

### 3.4 ARB 样例（ICU plural / select）

```jsonc
// lib/l10n/app_en.arb
{
  "@@locale": "en",
  "appTitle": "Neon Directive",
  "generateButton": "Generate",
  "copySuccess": "Copied to clipboard",
  "historyCount": "{count, plural, =0{No entries} =1{1 entry} other{{count} entries}}",
  "@historyCount": { "placeholders": { "count": { "type": "int" } } },
  "accentLabel": "{accent, select, magenta{Magenta} cyan{Cyan} lime{Lime} other{Unknown}}",
  "@accentLabel": { "placeholders": { "accent": { "type": "String" } } },
  "lastGeneratedAt": "Last generated: {time}",
  "@lastGeneratedAt": {
    "placeholders": { "time": { "type": "DateTime", "format": "yMMMd" } }
  }
}
```

```jsonc
// lib/l10n/app_zh.arb
{
  "@@locale": "zh",
  "appTitle": "霓虹指令生成器",
  "generateButton": "生成",
  "copySuccess": "已复制到剪贴板",
  "historyCount": "{count, plural, =0{暂无记录} other{{count} 条记录}}",
  "@historyCount": { "placeholders": { "count": { "type": "int" } } },
  "accentLabel": "{accent, select, magenta{洋红} cyan{青色} lime{青柠} other{未知}}",
  "@accentLabel": { "placeholders": { "accent": { "type": "String" } } },
  "lastGeneratedAt": "最后生成于：{time}",
  "@lastGeneratedAt": {
    "placeholders": { "time": { "type": "DateTime", "format": "yMMMd" } } }
}
```

> **中文 plural**：中文只有 `other` 一类。`=0{...}` 是精确匹配、任何语言都生效，可安全使用；但**不要**写 `one{...}`，中文下永不命中。

调用：`AppLocalizations.of(context).historyCount(history.length)`（`nullable-getter: false` 时返回非空）。

## 4. 路由

| 包 | 版本 | Dart SDK | Flutter | 发布日 | likes | points |
|---|---|---|---|---|---|---|
| `go_router` | **18.0.2** | `^3.12.0` | `>=3.44.0` | 2026-09-28 | 5787 | 150/160 |

官方一方（`flutter.dev`）Flutter Favorite。**推荐使用**，因为存在三个真实需求：Web 后退键应回到上一语义位置；设置/历史/收藏页需 URL 直达（可分享、刷新保状态）；深链接 `/i/<id>`。用裸 `Navigator` 这三条都难做好，而增量成本仅 1 个依赖。

> 其分数为 150/160，因包内 `lib/src/builder.dart:467` 仍用已废弃的 `onPopPage`（不影响你的 analyze）。

### 4.1 最小配置

```dart
// lib/app/router.dart
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (c, s) => const HomePage(), routes: [
      GoRoute(path: 'history',  builder: (c, s) => const HistoryPage()),
      GoRoute(path: 'settings', builder: (c, s) => const SettingsPage()),
      GoRoute(path: 'i/:id',    builder: (c, s) => InstructionDetailPage(id: s.pathParameters['id']!)),
    ]),
  ],
  errorBuilder: (c, s) => NotFoundPage(location: s.uri.toString()),
);

// 装配：MaterialApp.router(routerConfig: router, ...)
// 导航：context.go('/history') ／ context.push('/i/${id}') ／ context.pop()
```

### 4.2 ⚠️ Web URL 策略：hash vs path（最大部署陷阱）

Flutter Web 默认 **hash** 策略（`/#/history`）。要干净的 `/history`，必须在 `runApp` **之前**：

```dart
import 'package:flutter_web_plugins/url_strategy.dart'; // pubspec 需声明 flutter_web_plugins: {sdk: flutter}

void main() {
  usePathUrlStrategy();   // 必须早于 runApp
  runApp(const App());
}
```

**源码依据**（`flutter_web_plugins/lib/src/navigation/url_strategy.dart`）：`usePathUrlStrategy()` 构造 `PathUrlStrategy`，其构造函数调用 `checkBaseHref(platformLocation.getBaseHref())`，由此产生两条硬性要求：

1. `web/index.html` 必须有 `<base href="/">`，且 **`href` 必须以 `/` 结尾**；否则运行时抛 `Exception('The base href has to end with a "/" to work correctly')`。
2. **静态托管必须配置 rewrite，把所有路径回落到 `index.html`。** 否则用户直接访问 `/history` 或按 F5，服务器返回 404（磁盘上并无 `history` 文件）。这正是你说的 known footgun。

| 托管 | 做法 |
|---|---|
| **GitHub Pages** | 子路径部署时 `<base href="/<repo>/">`；**GH Pages 不支持服务端 rewrite**。通用 workaround：把 `build/web/404.html` 复制为 `index.html` 的副本（GH Pages 以 404.html 作兜底内容返回，Flutter 仍能启动并读出 `location.pathname`）。更稳妥是改用 Cloudflare Pages / Netlify / Vercel |
| **Cloudflare Pages / Netlify** | `_redirects`：`/*  /index.html  200` |
| **Vercel** | `vercel.json`：`{"rewrites":[{"source":"/(.*)","destination":"/index.html"}]}` |
| **nginx** | `try_files $uri $uri/ /index.html;` |

> **保守替代（推荐先用）**：不折腾 rewrite，就**保持默认 hash 策略**（不调 `usePathUrlStrategy()`）。URL 是 `/#/history`，丑但任何静态托管开箱即用、刷新不 404。对本项目「小工具」定位完全可接受 —— **建议先用 hash 上线，确需干净 URL 时再切 path 并配好 rewrite。**

## 5. 剪贴板与分享

**复制**用第一方 `Clipboard.setData`（`flutter/services`，零依赖；Web 走 `navigator.clipboard.writeText`，需 HTTPS/localhost 安全上下文）：

```dart
await Clipboard.setData(ClipboardData(text: text));
```

测试时替换平台通道，无需真实浏览器：

```dart
testWidgets('复制写入剪贴板', (tester) async {
  final log = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') log.add(call);
      return null;
    });
  await tester.pumpWidget(const App());
  await tester.tap(find.byIcon(Icons.copy));
  await tester.pump();
  expect(log.single.arguments['text'], contains('NEON'));
});
```

**分享**用 `share_plus` **13.3.1**（`>=3.10.0 <4.0.0`，Flutter ≥3.38.1，2026-10-01，4028 likes，150/160，未废弃）。**没有第一方替代** —— Flutter 团队未提供官方 share 插件，`share_plus` 由 `fluttercommunity.dev`（verified publisher）维护、是事实标准。

> **Web 限制（重要）**：pub.dev 明确标注 `Package not compatible with runtime wasm`，原因是 `share_plus_web.dart` → `share_plus_platform_interface` → `path_provider` → `dart:io`。所以 ✅ 可 `flutter build web`（JS）并正常使用；❌ **不能** `flutter build web --wasm`。
> Web 上底层调用 **Web Share API**（`navigator.share`），仅部分浏览器可用（移动 Chrome/Safari 可用；桌面 Firefox 普遍不支持），且需安全上下文。**必须优雅降级到剪贴板**：

```dart
class ShareService {
  const ShareService();

  /// true = 调起系统分享面板；false = 已降级为复制
  Future<bool> shareText(String text, {String? subject}) async {
    try {
      final r = await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      return r.status == ShareResultStatus.success;
    } on UnimplementedError {          // 平台未实现 Web Share API
      await Clipboard.setData(ClipboardData(text: text));
      return false;
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      return false;
    }
  }
}
```

UI 依返回值给不同提示（`l10n.shareOpened` / `l10n.copySuccess`）。

> 附注：`share_plus` 13.3.1 的 `cross_file` 约束为 `^0.3.5+2`，而 `cross_file` 已发布 0.4.0 —— 不影响你的项目，但说明其传递依赖更新略滞后。

## 6. 测试策略

### 6.1 目录结构

```
test/
├── unit/                     # 纯 Dart 逻辑，无 widget，最快
│   ├── engine/instruction_engine_test.dart    # 加权随机
│   ├── engine/shuffle_bag_test.dart           # 袋内不重复 + 袋空后重填
│   ├── repositories/history_repository_test.dart  # 用 InMemoryKeyValueStore
│   └── controllers/generator_controller_test.dart # ProviderContainer 隔离
├── widget/
│   ├── home_page_test.dart
│   ├── settings_page_test.dart
│   └── reduce_motion_test.dart
├── golden/theme_golden_test.dart  +  golden/goldens/   # 基准 PNG 提交仓库
├── helpers/pump_app.dart          # 统一挂载：Router + l10n + container
├── helpers/fakes.dart
└── flutter_test_config.dart       # 全局 setUp
```

### 6.2 确定性 pump 动画

霓虹主题大量使用 `AnimatedContainer` / `AnimationController`，**有无限循环动画（持续脉冲光晕）时 `pumpAndSettle()` 会超时失败**。三种手段：

```dart
// 1) 固定时长精确推进，不用 pumpAndSettle
await tester.tap(find.text('生成'));
await tester.pump();                                   // 触发 setState
await tester.pump(const Duration(milliseconds: 300));  // 中间态
await tester.pump(const Duration(milliseconds: 300));  // 结束态

// 2) 无限动画：外面包 TickerMode
await tester.pumpWidget(TickerMode(enabled: false, child: const App()));

// 3) 让「减少动态效果」真实生效
await tester.pumpWidget(MediaQuery(
  data: const MediaQueryData(disableAnimations: true), child: const App()));
```

> **可测性设计建议**：把「动画速度」与「reduce motion」做成**注入的纯数据** `MotionTokens(durationFast, durationSlow, curve)`，动画组件只消费 token。测试里注入 `MotionTokens.reduced()`（时长为 0）后连精确计时都不需要 —— 这是本项目最省事的设计。`fake_async` 1.3.3 可用于纯 Dart 定时逻辑。

### 6.3 金图测试

- ❌ **`golden_toolkit` 已 discontinued**（`isDiscontinued: true`，最新 0.15.0 / **2023-02-21**，SDK `<3.0.0`）—— Dart 3.13.4 下**无法解析**。**不要用**。
- ✅ `alchemist` 0.14.0（2026-03-13，`sdk: >=3.8.0 <4.0.0`，`flutter: >=3.32.0`，224 likes，150/160，Very Good Ventures 维护）是 `golden_toolkit` 的事实继任者，自动处理字体加载与多平台 golden 命名。
- ✅ **或零依赖**：用内置 `matchesGoldenFile()` + `flutter test --update-goldens`。

本项目建议**先用内置 `matchesGoldenFile()` 做少量主题快照**（每种霓虹强调色 1 张），不引第三方包 —— 金图对字体/平台敏感，CI 差异易 flaky，收益成本比一般。

### 6.4 让测试与语言环境无关

1. **断言用 key，不断言文案**：`expect(find.byKey(const Key('generate_button')), findsOneWidget);`
2. **需断言文案时从 `AppLocalizations` 取**，不硬编码：`final l10n = await AppLocalizations.delegate.load(const Locale('en'));`
3. **固定 locale**，避免 CI 机器语言不同导致漂移 —— 统一 helper：

```dart
// test/helpers/pump_app.dart
extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget child, {Locale locale = const Locale('en')}) =>
      pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ));
}
```

> 测响应式时用 `tester.view.physicalSize` / `devicePixelRatio`，**务必 `addTearDown(tester.view.reset)`**，否则污染同文件后续测试。

### 6.5 命令

```bash
flutter analyze                        # 必须 0 issue
flutter test                           # 全部测试
flutter test --coverage                # → coverage/lcov.info
flutter test test/unit                 # 只跑单测，迭代快
flutter test --update-goldens          # 更新金图基准
flutter gen-l10n                       # 重新生成 AppLocalizations
genhtml coverage/lcov.info -o coverage/html    # 覆盖率报告
flutter gen-l10n && test ! -s build/untranslated.json   # CI 卡口：缺翻译即失败
```

## 7. 项目结构与 Lint

### 7.1 推荐 **feature-first**

本项目约 5 个功能域、预计 3–5 千行：layer-first（`lib/models`/`views`/`controllers`）改一个功能要横跨 3 个目录、删一个功能要翻遍全项目；feature-first 让**生成引擎**（唯一含复杂算法的核心资产）自包含且可独立单测。Flutter [官方架构指南](https://docs.flutter.dev/app-architecture)本身也推荐按 UI / Data 分层并在其下按 feature 切分。

```
lib/
├── main.dart                    # 组合根：runApp + usePathUrlStrategy + ProviderScope overrides
├── app/
│   ├── app.dart                 # MaterialApp.router 装配
│   ├── router.dart              # GoRouter 配置
│   └── theme/
│       ├── neon_theme.dart          # ThemeData 工厂（light/dark × 强调色）
│       ├── accent_colors.dart       # 霓虹强调色枚举 → ColorScheme
│       └── motion_tokens.dart       # 动画时长/曲线 token（含 reduced）
├── core/                        # 跨 feature 基础设施，不含业务
│   ├── platform/clipboard_service.dart
│   ├── platform/share_service.dart
│   ├── random/seeded_random.dart             # 可注入种子的 Random 抽象
│   ├── layout/breakpoints.dart
│   ├── layout/centered_content.dart          # 320px→2560px 居中内容列
│   └── widgets/neon_button.dart, neon_panel.dart
├── data/
│   ├── sources/key_value_store.dart          # 抽象 + SharedPrefs/InMemory 实现
│   └── repositories/history_repository.dart, favorites_repository.dart, settings_repository.dart
├── features/
│   ├── generator/
│   │   ├── domain/instruction.dart, instruction_template.dart,
│   │   │        shuffle_bag.dart, instruction_engine.dart   # 纯逻辑，重点单测
│   │   ├── application/generator_controller.dart            # Notifier
│   │   └── presentation/generator_page.dart, widgets/instruction_card.dart
│   ├── history/application/history_controller.dart + presentation/history_page.dart
│   ├── favorites/application/favorites_controller.dart + presentation/favorites_page.dart
│   └── settings/domain/app_settings.dart
│                application/settings_controller.dart
│                presentation/settings_page.dart
└── l10n/app_en.arb, app_zh.arb, generated/   # generated/ 提交到仓库
```

`data/` 与 `core/` 提到顶层（而非塞进某个 feature）是因为**三个 feature 共用同一份历史/设置存储**；硬塞进 `features/history/data/` 会让 `favorites` 跨 feature import，破坏封装。

**依赖方向规则**（建议写进 CONTRIBUTING）：`presentation → application → domain`，`data` 只经抽象接口被注入。
- `domain/` **不得** import `flutter/material.dart`、不得 import `data/`（保证引擎可纯 Dart 单测）；
- `presentation/` **不得**直接 import `data/`，只能经 provider 拿 controller。

### 7.2 `analysis_options.yaml`

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language: { strict-casts: true, strict-inference: true, strict-raw-types: true }
  errors:
    missing_required_param: error
    missing_return: error
    todo: ignore
    deprecated_member_use_from_same_package: warning
  exclude:
    - "**/*.g.dart"
    - "lib/l10n/generated/**"      # 生成代码不参与 lint

linter:
  rules:
    # 你点名的四条
    prefer_const_constructors: true
    require_trailing_commas: true
    always_declare_return_types: true
    unawaited_futures: true
    # 强烈建议一并开启
    prefer_const_constructors_in_immutables: true
    prefer_const_declarations: true
    prefer_const_literals_to_create_immutables: true
    prefer_final_locals: true
    prefer_final_in_for_each: true
    avoid_print: true
    use_super_parameters: true
    sort_pub_dependencies: true
    depend_on_referenced_packages: true     # 强制 §3.1 的 intl 直接依赖
    avoid_redundant_argument_values: true
    unnecessary_lambdas: true
    use_colored_box: true
    use_decorated_box: true
    discarded_futures: true
```

`flutter_lints` 当前 **6.0.0**（2025-05-27，1339 likes，160/160，依赖 `lints: ^6.0.0`）。

### 7.3 `very_good_analysis` 值得吗？

当前 **11.0.0**（2026-09-03，771 likes，160/160，`sdk: ^3.13.0` —— 与本机 Dart 3.13.4 完全匹配）。

| | `flutter_lints` 6.0.0 | `very_good_analysis` 11.0.0 |
|---|---|---|
| 规则数 | 约 100（宽松） | 约 300（含 `public_member_api_docs`、`lines_longer_than_80_chars`） |
| 维护方 | Flutter 官方 | Very Good Ventures（商业公司） |

**建议 `flutter_lints` + §7.2 的显式加严。** VGV 最有价值的两条对应用型项目是负担：`public_member_api_docs` 会强迫你为每个私有小组件写文档注释；`lines_longer_than_80_chars` 与 Flutter 嵌套 widget 的 `dart format` 结果直接冲突（formatter 产出的行超 80 列，lint 与 formatter 互相打架）。而它真正的严格性用上面 20 行配置即可覆盖。若团队已有 VGV 经验且接受初期清理成本，11.0.0 完全可用 —— 这不是错误选择，只是性价比问题。

## 8. 响应式 / 自适应

### 8.1 ⚠️ 不要用 `flutter_adaptive_scaffold`

该包已被官方标记 **discontinued**：`isDiscontinued: true`，最新 0.3.3+1 发布于 **2025-05-06**，其 pub.dev README 首行即写 *"**This project has been discontinued**, and will not receive further updates. For community discussion of alternative packages, see [this issue](https://github.com/flutter/flutter/issues/162965)."*（952 likes / 150 points，评分已冻结）。

**替代**：Flutter 内置 `LayoutBuilder` + `MediaQuery` + 自定义断点。对单屏工具 app，`AdaptiveScaffold` 的 `SlotLayout`/`Breakpoint` 机制本就越重。社区 fork（`adaptive_scaffold_plus`、`adaptive_scaffold_router`）likes 极低、维护者不明，**不建议**。

### 8.2 `LayoutBuilder` vs `MediaQuery`

**默认用 `LayoutBuilder`**（反映父级给该 widget 的约束，支持嵌套/多栏各自判断）；仅在需要「整个窗口」信息（安全区、屏幕方向、`disableAnimations`）时用 `MediaQuery`。

```dart
// lib/core/layout/breakpoints.dart
enum WindowSize { compact, medium, expanded, large, extraLarge }

abstract final class Breakpoints {
  static const double medium = 600, expanded = 840, large = 1200, extraLarge = 1600;
  static WindowSize of(BuildContext c) => fromWidth(MediaQuery.sizeOf(c).width);
  static WindowSize fromWidth(double w) {
    if (w < medium) return WindowSize.compact;
    if (w < expanded) return WindowSize.medium;
    if (w < large) return WindowSize.expanded;
    if (w < extraLarge) return WindowSize.large;
    return WindowSize.extraLarge;
  }
}
```

（断点取值参考 Material 3 window size class：compact < 600 ≤ medium < 840 ≤ expanded < 1200 ≤ large < 1600 ≤ extraLarge。）

### 8.3 320px → 2560px 都好看的居中内容列

关键：**内容列有最大宽度，背景铺满**；左右留白随屏幕增大而增大。

```dart
// lib/core/layout/centered_content.dart
class CenteredContent extends StatelessWidget {
  const CenteredContent({required this.child, this.maxWidth = 720,
      this.wideMaxWidth = 960, super.key});
  final Widget child;
  final double maxWidth, wideMaxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final size = Breakpoints.fromWidth(c.maxWidth);   // 用父级约束，嵌在分栏里也对
    final cap = switch (size) {
      WindowSize.compact || WindowSize.medium => c.maxWidth,
      _ => wideMaxWidth,
    };
    final horizontal = switch (size) {                // 16 → 48
      WindowSize.compact => 16.0,  WindowSize.medium => 24.0,
      WindowSize.expanded => 32.0, _ => 48.0,
    };
    return Center(child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: cap),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: horizontal), child: child),
    ));
  });
}
```

```dart
Scaffold(body: SafeArea(child: Scrollbar(child: SingleChildScrollView(
  primary: true,                       // ← 关键：让 Scrollbar 绑定到它
  child: CenteredContent(child: Column(children: [/* ... */])),
))));
```

### 8.4 安全区

- **必须**用 `SafeArea` 包裹自己画的贴边内容（刘海/挖孔屏会遮挡；桌面窗口化也受益）；但**不要**无脑全局包裹 —— `AppBar`、`BottomNavigationBar` 已自行处理。移动端底部按钮尤其易被手势条遮挡，用 `SafeArea(top: false, child: ...)`。
- 细粒度用 `MediaQuery.paddingOf(context)`（而非 `.of`，避免无关重建）；软键盘用 `MediaQuery.viewInsetsOf(context)`。

### 8.5 Web / 桌面滚动条与滚轮

1. **`Scrollbar` 不会自动出现** —— `SingleChildScrollView` / `ListView` 需显式包 `Scrollbar`，或依赖自定义 `ScrollBehavior`。
2. Web/桌面默认「手指式拖拽」滚动，不符合鼠标习惯，应自定义 `ScrollBehavior`：

```dart
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch, PointerDeviceKind.mouse,   // ← 允许鼠标拖动
    PointerDeviceKind.trackpad, PointerDeviceKind.stylus,
  };
  @override
  Widget buildScrollbar(BuildContext c, Widget child, ScrollableDetails d) =>
      axisDirectionToAxis(d.direction) == Axis.vertical
          ? Scrollbar(controller: d.controller, child: child)   // 桌面/Web 常驻可见
          : child;
}
// MaterialApp.router(scrollBehavior: const AppScrollBehavior(), ...)
```

3. **滚轮**由框架处理，一般无需干预；**嵌套滚动**（历史列表嵌在页面滚动里）易「滚轮卡住」，给内层 `NeverScrollableScrollPhysics` 或改单一 `CustomScrollView` + slivers。
4. `PrimaryScrollController` 冲突是常见坑（同页多个 `ListView` 都想要 primary 会报错）：显式传 `primary: false` + 自己的 `ScrollController`。

## 9. 键盘快捷键

> ⚠️ 更正一个常见说法：**`CallbackShortcuts` 已不在 `flutter/widgets` 中**，其正式位置是 `package:flutter/material.dart`；widget 层的通用方案是 `Shortcuts` + `Actions` + `Intent`。

### 9.1 推荐：`CallbackShortcuts`（单动作场景）

「Space / Enter = 生成」这类**单动作、无参数、无需菜单显示快捷键提示**的需求最省代码：

```dart
CallbackShortcuts(
  bindings: <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.space): controller.generate,
    const SingleActivator(LogicalKeyboardKey.enter): controller.generate,
    const SingleActivator(LogicalKeyboardKey.numpadEnter): controller.generate,
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => _copy(context),
    const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () => _copy(context),  // macOS
  },
  child: Focus(autofocus: true, child: Scaffold(/* ... */)),   // ← 顺序关键，见 9.3
)
```

### 9.2 何时升级到 `Shortcuts` + `Actions` + `Intent`

当快捷键需出现在 `MenuBar` / `MenuItemButton` 提示中，或需 `enabled` 状态、需按焦点区域区分行为时：

```dart
class GenerateInstructionIntent extends Intent { const GenerateInstructionIntent(); }

Shortcuts(
  shortcuts: const <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.space): GenerateInstructionIntent(),
    SingleActivator(LogicalKeyboardKey.enter): GenerateInstructionIntent(),
  },
  child: Actions(
    actions: <Type, Action<Intent>>{
      GenerateInstructionIntent: CallbackAction<GenerateInstructionIntent>(
        onInvoke: (i) => ref.read(generatorControllerProvider.notifier).generate()),
    },
    child: Focus(autofocus: true, child: const GeneratorView()),
  ),
)
```

好处：`MenuItemButton(shortcut: ...)` 能自动读同一套映射显示提示文字，`Action` 也可被 `ActionDispatcher` 拦截/禁用。**本项目选择**：主生成用 `CallbackShortcuts`，若后续加「菜单栏 + 快捷键提示」再升级；两者可在同一棵树共存。

### 9.3 ⚠️ Flutter Web 的焦点陷阱

CanvasKit / skwasm 渲染下，键盘事件依赖浏览器把焦点交给 Flutter 的 canvas 宿主元素。**若用户从未点击过页面（尤其经带 `#` 的深链接直接进入），document 焦点可能仍在 `<body>` 或地址栏，按键完全不触发。** 对策（按有效性排序）：

1. **`Focus(autofocus: true)`** —— 首帧后主动请求焦点。注意它只在 `FocusScope` 内生效，且页面上的 `TextField` 会抢走焦点。
2. **在首次用户手势里请求焦点** —— 浏览器通常不允许无用户交互的 `focus()`：

```dart
Listener(
  behavior: HitTestBehavior.translucent,
  onPointerDown: (_) => _focusNode.requestFocus(),
  child: Focus(focusNode: _focusNode, autofocus: true, child: child),
)
```

3. **给 `index.html` 宿主元素加 `tabindex`**，让 canvas 可被 Tab 聚焦：`<div id="flutter_target" tabindex="0"></div>`。
4. **不要在 `main()` 里抢焦点** —— `ensureInitialized()` 后立刻 `FocusScope.of(...)` 无效（尚无 context）。
5. **调试技巧**：Web 上按键不响应时，先点一次页面 —— 恢复即是焦点问题；仍不响应则是 `Shortcuts` 未挂在 `Focus` 的祖先链上。
6. **`CallbackShortcuts` 与 `Focus` 的顺序很关键**：前者必须在后者的**上层**，且前者自身内部创建了一个 `Focus` —— 它只负责「按键→回调」映射，不负责「谁拥有焦点」，所以外面再包 `Focus(autofocus: true)` 是必要的。

## 10. 推荐决策表

| 主题 | 选择 | 版本约束 | 为什么 | 被否决的替代 |
|---|---|---|---|---|
| **状态管理** | `flutter_riverpod` | `^3.4.3` | 编译期安全 DI；`ProviderContainer` 让 Notifier 脱离 widget 单测；5 份状态共享仓储天然解决 | `provider` 6.1.5+1（需 `pumpWidget` 才能测、DI 样板多）；`flutter_bloc` 9.1.1（过度设计）；`signals` 7.1.0（生态小）；裸 `ChangeNotifier`（DI 全手写） |
| **代码生成** | **不引入** | — | 省 3 个依赖 + 整套 `build_runner`；Riverpod 3 完整支持手写 provider | `riverpod_generator` 4.0.9 + `riverpod_annotation` 4.0.7 + `build_runner` 2.16.1（前两者仅 130/160） |
| **持久化** | `shared_preferences`（新异步 API） | `^2.5.5` | 官方一方、160/160、6 平台 + WASM；~40 KB 数据远低于 localStorage 上限；零 codegen | `isar`（**SDK `<3.0.0`，Dart 3 无法解析**）；`hive` 2.2.3（同因，已由 `hive_ce` 接替）；`drift` 2.35.1（Web 需 sqlite3.wasm，过重）；`hive_ce` 2.20.1（健康但用不上其能力） |
| **本地化** | `flutter_localizations` + ARB + `gen-l10n` | SDK 内置 | 官方唯一推荐路径；ICU plural/select 开箱可用 | `easy_localization`、`intl_utils`、`slang`（增依赖无收益） |
| **intl** | 直接依赖 | `intl: ^0.20.3` | 生成代码 import 它；`depend_on_referenced_packages` 要求直接声明 | 仅靠传递依赖（触发 analyzer 警告，违反零问题要求） |
| **路由** | `go_router` | `^18.0.2` | 官方一方、Flutter Favorite；Web URL + 前进/后退 + 深链接 | 裸 `Navigator`（Web 后退键与 URL 刷新型态难处理） |
| **Web URL 策略** | **先用默认 hash**；需要时再切 `usePathUrlStrategy()` | SDK 内置 | hash 在任何静态托管开箱即用、刷新不 404；path **必须**配 rewrite，GH Pages 不支持 | `url_strategy` 0.3.0（**已 discontinued**，功能已内置） |
| **复制** | `Clipboard.setData` | SDK 内置 | 零依赖；Web 走 `navigator.clipboard`；测试可 mock 平台通道 | 第三方剪贴板包（无必要） |
| **分享** | `share_plus` | `^13.3.1` | 无第一方替代；事实标准；6 平台 | 手写 Web Share API 平台通道（需自写 3 平台实现） |
| **分享降级** | 捕获异常 → `Clipboard.setData` | — | Web Share API 桌面支持不全；`share_plus` **不兼容 WASM** | 假设分享总可用（桌面 Firefox 静默失败） |
| **自适应布局** | `LayoutBuilder` + 自定义断点 + `MediaQuery` | SDK 内置 | `flutter_adaptive_scaffold` **已 discontinued**；内置方案更轻 | `flutter_adaptive_scaffold` 0.3.3+1（**discontinued**）；`adaptive_scaffold_plus`（fork，likes 极低） |
| **滚动行为** | 自定义 `MaterialScrollBehavior` | SDK 内置 | 桌面/Web 需鼠标拖动 + 常驻滚动条 | 默认 `ScrollBehavior`（桌面端只能拖滚动条） |
| **快捷键** | `CallbackShortcuts` + `Focus(autofocus: true)` | SDK 内置 | 单动作最省代码，无 Intent 样板 | `Shortcuts`/`Actions`/`Intent`（留待需菜单栏提示时升级） |
| **Lint** | `flutter_lints` + 显式加严 20 条 | `^6.0.0` | 官方维护；点名 4 条规则全支持；避开 VGV 的 `public_member_api_docs` 与 formatter 冲突 | `very_good_analysis` 11.0.0（可用且版本兼容，但 300 条规则性价比低） |
| **金图测试** | 内置 `matchesGoldenFile()` | SDK 内置 | 零额外依赖；本项目只需少量主题快照 | `golden_toolkit` 0.15.0（**discontinued + SDK `<3.0.0`**）；`alchemist` 0.14.0（可用，留作升级选项） |
| **测试 mock** | 自写 `InMemoryKeyValueStore` | — | 不依赖插件与 mock 框架；测试最快 | `SharedPreferences.setMockInitialValues`（旧 API 专用）；`mocktail` 1.0.5（额外依赖） |

## 11. 提议的 `pubspec.yaml` 依赖块

> **注意**：本仓库 `pubspec.yaml` 已基本符合下列形态（见 §00）。本节给出**"若从零开始"的完整形态**，并标注与实际现状的差异。

```yaml
# —— 下列形态中，标注 ✅ 的行本仓库 pubspec.yaml 已具备 ——
environment:
  sdk: ^3.13.4              # ✅ 现有（比 ^3.13.0 更紧，等价）

dependencies:
  flutter: {sdk: flutter}
  flutter_localizations: {sdk: flutter}   # ✅ 现有
  flutter_web_plugins: {sdk: flutter}     # ❌ 现有未声明（仅在切 path URL 策略时需要）
  flutter_riverpod: ^3.4.3   # ❌ 现有用手写 AppScope，见 §00（当前建议保持不变）
  go_router: ^18.0.2         # ❌ 现有未用（仅在需要 URL 路由/深链接时需要）
  shared_preferences: ^2.5.5 # ✅ 现有
  share_plus: ^13.3.1        # ✅ 现有
  url_launcher: ^6.3.2       # ✅ 现有（打开外链）
  intl: ^0.20.3              # ✅ 现有；gen-l10n 生成代码直接 import
  cupertino_icons: ^2.0.0    # ⚠️ 现有为 ^1.0.8，最新为 2.0.0

dev_dependencies:
  flutter_test: {sdk: flutter}   # ✅ 现有
  flutter_lints: ^6.0.0          # ✅ 现有

flutter:
  uses-material-design: true     # ✅ 现有
  generate: true                 # ✅ 现有；让 pub get 自动跑 gen-l10n
```

**实际需要改动的只有 4 处，且全部可选**：① `flutter_riverpod`（**当前不建议加**，见 §00）；② `go_router`（仅在需要 URL 路由/深链接时）；③ `flutter_web_plugins`（仅在切 path URL 策略时）；④ `cupertino_icons` 升到 `^2.0.0`。

**刻意排除**：`isar`、`hive`/`hive_generator`、`golden_toolkit`、`flutter_adaptive_scaffold`、`url_strategy`（均已废弃或 Dart 3 无法解析）；`flutter_hooks`（最新 0.21.3+1 的 SDK 约束仍是 `>=2.17.0 <3.0.0`，**Dart 3.13.4 无法解析**）；`riverpod_generator`/`riverpod_annotation`/`build_runner`（本项目不需 codegen）；`flutter_animate` 4.5.2（内置 `AnimationController` 足够，且已 22 个月未更新）；`google_fonts` 9.0.0（运行时下载字体，离线/内网会失败 —— 现有仓库改用本地字体 + `tools/subset_fonts.py` 裁剪，**这是更优的做法**）；`dynamic_color` 2.1.0（与「用户自选霓虹强调色」设定冲突）。

**约束写法**：全部用 `^`。本项目是应用而非库，无需为下游放宽约束；`^` 能收 bug 修复同时避开次版本破坏性变更。

## 12. 参考资料

- Flutter 官方：[国际化指南](https://docs.flutter.dev/ui/internationalization) ｜ [Web URL 策略](https://docs.flutter.dev/ui/navigation/url-strategies) ｜ [App 架构指南](https://docs.flutter.dev/app-architecture)
- [`usePathUrlStrategy` 源码](https://github.com/flutter/flutter/blob/master/packages/flutter_web_plugins/lib/src/navigation/url_strategy.dart)（`checkBaseHref` 的 `base href` 必须以 `/` 结尾）
- [`flutter_localizations/pubspec.yaml`](https://github.com/flutter/flutter/blob/master/packages/flutter_localizations/pubspec.yaml)（`intl: ^0.20.3` 直接依赖依据）
- Riverpod：[3.0 新特性](https://riverpod.dev/docs/whats_new) ｜ [Getting started](https://riverpod.dev/docs/introduction/getting_started) ｜ [issue #4312 Web/WASM 兼容性（维护者确认为工具误报）](https://github.com/rrousselGit/riverpod/issues/4312)
- [flutter/flutter#162965：`flutter_adaptive_scaffold` 替代方案讨论](https://github.com/flutter/flutter/issues/162965)
- pub.dev 各包页面与 [`/api/packages/<name>/score`](https://pub.dev/api/packages/riverpod/score) 端点（likes / pub points / 发布日期 / discontinued / WASM-ready 标记均由此实时抓取）
- `shared_preferences` 2.5.5、`shared_preferences_web` 2.4.3、`shared_preferences_platform_interface` 2.4.2 包源码（本地 pub cache，用于核实 `SharedPreferencesAsync`、`InMemorySharedPreferencesAsync`、localStorage 实现）
