# Flutter Web 部署 / 渲染器 / PWA / CJK 字体策略 调研报告

- **背景**：用 Flutter 复刻静态霓虹赛博朋克站点（黑底 + 霓虹蓝发光文字 + 自定义字体：Inter 可变字体 0.83 MiB、霞鹜文楷 LXGW WenKai Regular 24.31 MiB），部署到 GitHub Pages / Cloudflare Pages，需可安装 PWA 与正确离线行为。
- **环境**：Flutter 3.47.5 (stable, engine `ab59836`, 2026-09-17) / Dart 3.13.4 / Windows。日期 **2026-10-02**。
- **方法**：官方文档（`*.md` 原文）+ **本机 SDK 源码逐条核对**（`C:\Users\Administrator\flutter\...`）+ **真实字体子集化实测**（fontTools 4.63.0 / Pillow / ffmpeg）。所有体积数字为实测值。
- **参考源文件**：`指令/index.html`、`指令/script.js`（句子池 + 彩蛋池 + 乱码锁定动画）、`指令/main.css`、`指令/instruction.png`（186×230）、`指令/.github/workflows/static.yml`。

## 0. 执行摘要（TL;DR）

1. **`--web-renderer` 在 3.47.5 已不存在**（本机 `--help -v` 无此 flag）；只剩 `canvaskit`（JS 默认）与 `skwasm`（`--wasm` 默认），见 §2。文档站 "Web renderers" 页已下线（404/重定向）。
2. **`flutter build web --wasm` 可用于生产**：同时产出 JS(canvaskit) 与 Wasm(skwasm)，运行时按 WasmGC/WebGL 选择并自动回退；只有 Wasm *deferred loading* 仍实验（官方称 3.50 GA）。
3. **3.41（2026-02）起 Flutter 不再自带缓存 SW**：`flutter_service_worker.js` 变成"自清理 stub"（skipWaiting → unregister → 让 clients 重载）。离线要自写 SW；`--pwa-strategy` 仍在但已隐藏且 deprecated。
4. **字体是最大风险**：引擎在初始化时**并行下载 `FontManifest.json` 里声明的全部字体**（非懒加载，[flutter#108660](https://github.com/flutter/flutter/issues/108660) 仍 open）。24.31 MiB 直上会让首屏被字体绑架。
5. **实测子集化收益**（本项目全部文案 = 784 去重字符 / 610 汉字）：**TTF 286.0 KiB、WOFF 186.1 KiB、WOFF2 151.3 KiB**（原始 24.31 MiB）。
6. **WOFF2 在 3.47 可用**：引擎自己把 Roboto / Noto 兜底字体以 `.woff2` 下载后交给 Skia（`canvaskit/fonts.dart:15`、`font_fallback_service.dart:483-499`、`font_fallback_data.dart` 有 724 条 `.woff2`）。3.10–3.24 曾损坏，[engine#55908](https://github.com/flutter/engine/pull/55908) 已修；文档"不支持 woff/woff2"只针对桌面。
7. **缺字会自动去 Google CDN 下 Noto Sans SC**（3.47 新增 Font fallback service）→ 离线失效 + 隐私 + 文字重排。必须 100% 覆盖 + CI 守门（§4.6/§4.7）。
8. **离线必须加 `--no-web-resources-cdn`**，否则 `canvaskit.wasm`（本机 6.95 MiB）默认从 `www.gstatic.com/flutter-canvaskit/<engineRevision>/` 拉取。
9. **GitHub Pages 无法设置响应头** → skwasm 多线程（需 COOP/COEP）不可用（退化为单线程，仅性能损失）；**Cloudflare Pages 可用 `_headers` 设置**，这是选它的首要技术理由。
10. **平台硬限**：CF Pages 单文件 **25 MiB**（24.31 MiB 字体贴限，绝不能这样上线）、20k 文件、`_headers` ≤100 条；GH Pages 站点 ≤1 GB、部署 10 分钟超时、软带宽 100 GB/月。
11. **最终推荐**（§7）：`--release --base-href /<repo>/ --no-web-resources-cdn --wasm`；字体 = 文楷子集 **TTF 286 KiB**（保守）/ **WOFF2 151 KiB**（冒烟后）+ Inter 拉丁子集 43.5 KiB；PWA = 自写 SWR SW + 自定义 `flutter_bootstrap.js`；**主站 Cloudflare Pages，GH Pages 作镜像**。

## 1. 构建与部署

### 1.1 构建命令与 3.47.5 真实存在的 flag（本机 `flutter build web --help -v`）

```bash
flutter build web --release --base-href "/flutter-zl/" --no-web-resources-cdn --wasm
```

| flag | 说明 |
|---|---|
| `--base-href` | 覆盖 `web/index.html` 中 `<base>` 的 href，**必须以 `/` 开头和结尾** |
| `--no-web-resources-cdn` | 把 canvaskit 等打进 `build/web/`，**离线/PWA 必开** |
| `--static-assets-url` | 静态资源独立域名时替换 `$FLUTTER_STATIC_ASSETS_URL`，须以 `/` 结尾 |
| `-O / --optimization-level` | `0..4`，Dart→JS/Wasm 优化级别 |
| `-o / --output`、`-t / --target` | 输出目录 / 入口文件 |
| `--source-maps` | 产出 `.map`；**官方警告不要公开部署**，只上传给 Sentry 类服务 |
| `--csp` | 禁止动态生成代码，满足 CSP |
| `--[no-]tree-shake-icons` | 默认 on（裁剪图标字体） |
| `--wasm` / `--[no-]strip-wasm` | wasm 构建 / 默认 on（`--no-strip-wasm` 体积约 +47%，仅 staging） |
| `--web-define=K=V` | 3.47 新能力：向 `web/index.html`、`web/flutter_bootstrap.js` 注入 `{{K}}` 模板变量 |
| `--pwa-strategy` | **已隐藏且 deprecated**，勿用 |

来源：[Build and release a web app](https://docs.flutter.dev/deployment/web)、本机 help 输出、`flutter_tools/lib/src/commands/build_web.dart`。

### 1.2 `web/index.html`：`$FLUTTER_BASE_HREF` 仍存在，viewport 由引擎接管

3.47.5 模板（`flutter_tools/templates/app/web/index.html.tmpl`）关键行：`<base href="$FLUTTER_BASE_HREF">`、`{{description}}`、`mobile-web-app-capable`、`apple-mobile-web-app-status-bar-style/title`、`apple-touch-icon`、`favicon.png`、`<title>{{projectName}}</title>`、`<link rel="manifest" href="manifest.json">`、`<script src="flutter_bootstrap.js" async></script>`。要点：

- `{{projectName}}`/`{{description}}` 来自 pubspec；`--web-define` 可加自定义变量（[初始化文档](https://docs.flutter.dev/platform-integration/web/initialization)）。
- **不要自己写 viewport**：full-page 模式下引擎会删掉页面已有 `meta[name=viewport]` 并注入自己的（并打印 "Found an existing `<meta name="viewport">` tag. Flutter Web uses its own viewport…"）——`_engine/.../full_page_embedding_strategy.dart:66-96`；同时注入 `<meta name="generator" content="Flutter">`（`initialization.dart:184`）。
- **`theme-color` 会被 Dart 覆盖**：调用 `SystemChrome.setSystemUIOverlayStyle(...)` 时引擎写入/更新 `meta[name=theme-color]`（`util.dart:662-676`、`platform_dispatcher.dart:525-531`）。首屏仍需在 HTML 写死。
- 项目页必须 `--base-href /<repo>/`；用户页/自定义域用 `/`（[URL 策略](https://docs.flutter.dev/ui/navigation/url-strategies)）。

推荐 `web/index.html`（在模板基础上补社交卡片、主题色、中文 lang、首屏占位；官方建议 splash 直接写在 index.html）：

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta name="description" content="食指指令生成器">
  <meta name="theme-color" content="#000000">
  <meta name="color-scheme" content="dark">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="指令">
  <meta property="og:type" content="website">
  <meta property="og:title" content="指令">
  <meta property="og:description" content="食指指令生成器">
  <meta property="og:image" content="icons/Icon-512.png">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="manifest" href="manifest.json">
  <title>指令</title>
  <style>html,body{margin:0;background:#000;height:100%}
    #boot{position:fixed;inset:0;display:grid;place-items:center;color:#39d7ff;letter-spacing:.4em;
          text-shadow:0 0 8px #39d7ff,0 0 24px #0af;font-family:system-ui,sans-serif;animation:p 1.6s infinite}
    @keyframes p{50%{opacity:.35}}</style>
</head>
<body>
  <div id="boot">指令加载中</div>
  <script src="flutter_bootstrap.js" async></script>
  <script>addEventListener('flutter-first-frame',()=>document.getElementById('boot')?.remove());</script>
</body>
</html>
```

### 1.3 GitHub Actions → Pages（2026-10 版本号，已核对 Releases API）

[checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) · [configure-pages v6.0.0](https://github.com/actions/configure-pages/releases/tag/v6.0.0) · [upload-pages-artifact v5.0.0](https://github.com/actions/upload-pages-artifact/releases/tag/v5.0.0) · [deploy-pages v5.0.1](https://github.com/actions/deploy-pages/releases/tag/v5.0.1) · [flutter-action v2.23.0](https://github.com/subosito/flutter-action/releases/tag/v2.23.0)

```yaml
# .github/workflows/deploy-pages.yml
name: Deploy Flutter Web to GitHub Pages
on:
  push: { branches: [main] }
  workflow_dispatch:
permissions: { contents: read, pages: write, id-token: write }   # deploy-pages 需 OIDC
concurrency: { group: pages, cancel-in-progress: false }          # 不打断进行中的生产部署
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with: { flutter-version: 3.47.5, channel: stable, cache: true }
      - run: flutter pub get
      - run: >
          flutter build web --release
          --base-href "/${{ github.event.repository.name }}/"
          --no-web-resources-cdn --wasm
      - run: cp build/web/index.html build/web/404.html   # path URL strategy 的 SPA 回退
      - run: find build/web -name '*.map' -delete         # 防止 source map 泄漏
      - uses: actions/configure-pages@v6
      - uses: actions/upload-pages-artifact@v5
        with: { path: build/web }
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment: { name: github-pages, url: "${{ steps.deployment.outputs.page_url }}" }
    steps:
      - id: deployment
        uses: actions/deploy-pages@v5
```

- **SPA 回退**：path 策略下深链会 404，GH Pages 的通用解法是 `index.html` → `404.html`（[自定义 404 文档](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-custom-404-page-for-your-github-pages-site)）。用 Actions artifact 部署不跑 Jekyll，无需 `.nojekyll`。
- **响应头不可配**：GH Pages 没有配置 `Cache-Control`/`COOP`/`COEP` 的机制；要跨源隔离只能上 SW 垫片（社区方案 [coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker)，被大量 wasm 项目用于 GH Pages），否则接受 skwasm 单线程。
- **限制**：站点 ≤1 GB、部署 10 分钟超时、软带宽 100 GB/月、软限 10 构建/小时（自定义 Actions 工作流不受该条限制）（[Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)）。
- **缓存**：Flutter 不会自动给资源加 build id，部署后用户可能吃到旧版；官方建议入口 `no-cache`、无 hash 产物 `max-age=0`（[Web FAQ](https://docs.flutter.dev/platform-integration/web/faq)）。

### 1.4 Cloudflare Pages（推荐主站）

Pages 构建镜像只预装 Node/Python/Ruby/Go/PHP/Bun/Swift 等，**不含 Flutter**（[Build image](https://developers.cloudflare.com/pages/configuration/build-image/)），所以推荐"CI 构建 + Direct Upload"而不是 Pages 的 Git 构建：

```bash
npx wrangler pages deploy build/web --project-name=flutter-zl   # 需 CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN
```

```yaml
      - uses: subosito/flutter-action@v2
        with: { flutter-version: 3.47.5, channel: stable, cache: true }
      - run: flutter build web --release --base-href / --no-web-resources-cdn --wasm
      - run: cp build/web/index.html build/web/404.html
      - uses: cloudflare/wrangler-action@v4
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: pages deploy build/web --project-name=flutter-zl
```

（[Direct Upload with CI](https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/)；限制见 [Pages limits](https://developers.cloudflare.com/pages/platform/limits/)：单文件 25 MiB、20k 文件、`_headers` ≤100 条规则 / 单行 ≤2000 字符。）

```
# build/web/_headers        （语法见 developers.cloudflare.com/pages/configuration/headers/）
/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: credentialless
  X-Content-Type-Options: nosniff
/index.html
  Cache-Control: no-cache
/flutter_bootstrap.js
  Cache-Control: no-cache
/flutter_service_worker.js
  Cache-Control: no-cache
/manifest.json
  Cache-Control: no-cache
/assets/*
  Cache-Control: public, max-age=0, s-maxage=604800
/canvaskit/*
  Cache-Control: public, max-age=31536000, immutable
```

```
# build/web/_redirects      （SPA 回退，替代 404.html 技巧）
/*  /index.html  200
```

## 2. 渲染器：canvaskit / skwasm / `--wasm`

### 2.1 `--web-renderer` 已移除

- 本机 `flutter build web --help -v` 与 `flutter run --help` **都没有**该 flag；`/platform-integration/web/renderers.md` 返回 404（页面重定向到 "Web support for Flutter"）。
- 源码只剩两个值且默认写死（`flutter_tools/lib/src/web/compile.dart:186-209`）：`enum WebRendererMode { canvaskit, skwasm }`、`defaultForJs = canvaskit`、`defaultForWasm = skwasm`；唯一（内部）开关是 dart-define `FLUTTER_WEB_USE_SKIA` / `FLUTTER_WEB_USE_SKWASM`。
- 运行时 `config.renderer` 只是断言：与构建不符时 `flutter.js` 抛 `The application is configured to use the "X" renderer; this build targets "Y".` 并因找不到可用构建而失败。

### 2.2 `--wasm` 现状与体积

`--wasm` 同时产出 `dart2wasm`+skwasm 与 `dart2js`+canvaskit 两套 `_flutter.buildConfig.builds`，`flutter.js` 运行时按 `supportsWasmGC` / `webGLVersion` / `wasmAllowList` 选择，选不到回退 JS（[Wasm 文档](https://docs.flutter.dev/platform-integration/web/wasm)）。是否真跑在 wasm：`bool.fromEnvironment('dart.tool.dart2wasm')`。

- 限制：iOS 上所有浏览器都是 WebKit，WasmGC 有阻塞 bug → iOS 实际跑 JS 回退；Firefox/Safari 同类问题；**不允许 `dart:html`/`package:js`**（须 `package:web` + `dart:js_interop`），兼容性 dry-run 警告在 JS 构建时也会打印。
- 本机 SDK 实测未压缩体积：`canvaskit.wasm` **6.95 MiB**、`skwasm.wasm` **3.43 MiB**、`skwasm_heavy.wasm` 4.97 MiB。wasm 会被浏览器缓存已编译代码，冷启动更快。
- **CJK 渲染无差别**：两个渲染器底层同为 Skia，文字造型同一条路径，字形质量一致；差别只在启动体积、多线程能力、CPU fallback（`canvasKitForceCpuOnly`）。

### 2.3 运行时/构建时控制

`_flutter.loader.load({config: {...}})`（[初始化文档](https://docs.flutter.dev/platform-integration/web/initialization)）常用键：`canvasKitBaseUrl`、`canvasKitVariant`(`auto|full|chromium`)、`forceSingleThreadedSkwasm`、`suppressMultithreadingWarning`、**`fontFallbackBaseUrl`**（默认 `https://fonts.gstatic.com/s/`，可改自托管）、`wasmAllowList`、`verboseBuildSelection`、`assetBase`。构建时对应 `--no-web-resources-cdn`（本地化 canvaskit，离线必需）。

### 2.4 COOP/COEP

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless    # 或 require-corp
```

没有这两个头时 skwasm 仍可用但**退化为单线程**并打印警告（`flutter.js` 原文：`Skwasm uses multi-threading and web workers for better performance, but your page needs to be cross-origin isolated…`）。设置方式：CF Pages → `_headers`（§1.4）；Firebase → `firebase.json` headers；**GH Pages → 无解，只能接受单线程或用 SW 垫片**。

## 3. PWA

### 3.1 `manifest.json`

由 `web/manifest.json` 原样拷贝（模板 `templates/app/web/manifest.json.tmpl`，含 192/512 与两个 `purpose: "maskable"` 图标、`start_url: "."`、`display: "standalone"`、`orientation: "portrait-primary"`）。本项目改为：`name/short_name: "指令"`、`id/start_url/scope`、`display_override: ["window-controls-overlay","standalone"]`、`background_color/theme_color: "#000000"`、`description: "食指指令生成器"`、图标保留 192/512 + maskable 两个（主视觉放中心 ~80% 安全区）。

### 3.2 Service Worker：3.41 起是"自清理 stub"

`build/web/flutter_service_worker.js` 仍会生成，内容即（本机 SDK `flutter_tools/lib/src/web/file_generators/js/flutter_service_worker.js` 全文）：

```js
'use strict';
self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (event) => { event.waitUntil((async () => {
  try { await self.registration.unregister(); } catch (e) { console.warn('Failed to unregister the service worker:', e); }
  try { (await self.clients.matchAll({type:'window'})).forEach((c) => { if (c.url && 'navigate' in c) c.navigate(c.url); }); }
  catch (e) { console.warn('Failed to navigate some service worker clients:', e); }
})()); });
```

- **它不缓存任何东西**，只注销自己并让页面重载（清理 3.41 之前遗留的 worker）。官方 FAQ：Flutter 不再生成/管理缓存 SW，离线请自建或使用 Workbox（[Web FAQ](https://docs.flutter.dev/platform-integration/web/faq#how-do-i-configure-a-service-worker)）。
- 默认 loader 只在**检测到旧 worker** 时才注册它；全新访客拿不到任何 SW。
- 走 Flutter 自带 SW 路径已废弃：`flutter.js` 会打印 `Loading the service worker using Flutter bootstrap is deprecated… See: https://github.com/flutter/flutter/issues/156910`。**不要**给 `_flutter.loader.load()` 传 `serviceWorkerSettings`。
- `{{flutter_service_worker_version}}` token 仍可用于自定义 SW 场景；`--pwa-strategy=none` 仍可用但已隐藏+deprecated。时间线/社区分析见 [Practical Flutter Web Caching in 3.41](https://www.krootl.com/blog/practical-flutter-web-caching-in-3-41)。

### 3.3 真离线：构建后写入自己的 SWR worker + 自定义 bootstrap

必须**构建后**改写 `build/web/flutter_service_worker.js`（提交到 `web/` 会被覆盖，且需要构建后才知道 hash），并由自定义 `web/flutter_bootstrap.js` 注册：

```js
// web/flutter_bootstrap.js  —— 必须包含这两个 token 并调用 load()
{{flutter_js}}
{{flutter_build_config}}
if ('serviceWorker' in navigator) {
  const reg = () => navigator.serviceWorker.register('flutter_service_worker.js', { scope: './' });
  document.readyState === 'complete' ? reg() : addEventListener('load', reg);
}
_flutter.loader.load();     // 不要传 serviceWorkerSettings
```

```js
// tool/sw.js → 构建后复制为 build/web/flutter_service_worker.js（最小 SWR）
const CORE = ['./','./index.html','./flutter_bootstrap.js','./manifest.json',
              './assets/FontManifest.json','./assets/assets/fonts/LXGWWenKai-subset.ttf'];
addEventListener('install', (e) => e.waitUntil(caches.open('v1').then(c => c.addAll(CORE))));
addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
addEventListener('fetch', (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;
  e.respondWith((async () => {
    const cache = await caches.open('v1');
    const hit = await cache.match(e.request, { ignoreSearch: true });
    const net = fetch(e.request).then(r => { if (r.ok) cache.put(e.request, r.clone()); return r; }).catch(() => hit);
    return hit || net;                       // stale-while-revalidate
  })());
});
```

配套缓存策略：入口文件 `no-cache`、无 hash 产物 `max-age=0` + 长 `s-maxage`；**禁用 `no-store`**（会同时废掉 HTTP 缓存与 SW 的 SWR）。

### 3.4 2026 可安装性清单（[MDN](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)）

HTTPS/localhost ✅ · `<link rel="manifest">` 且 JSON 合法可抓 ✅ · `name` 或 `short_name` ✅ · `icons` 含 **192 与 512** ✅ · `start_url` ✅ · `display` 或 `display_override` ✅ · `prefer_related_applications: false` ✅ · SW **不再强制**（但离线必须要）· 可选 `beforeinstallprompt` 自定义安装按钮（iOS 只能引导"添加到主屏幕"）· 可选 `id`/`screenshots`/`shortcuts`。

## 4. 字体策略（最关键）

### 4.1 pubspec → FontManifest.json → **Web 启动时全量下载**

```yaml
flutter:
  fonts:
    - family: LXGW WenKai
      fonts: [ { asset: assets/fonts/LXGWWenKai-subset.ttf } ]
    - family: Inter
      fonts: [ { asset: assets/fonts/Inter-subset.woff2 } ]
```

引擎读 `assets/FontManifest.json`（`_engine/engine/fonts.dart:29-79`）后（`_engine/engine/canvaskit/fonts.dart:114-137`）：

```dart
for (final family in manifest.families)
  for (final a in family.fontAssets) pendingDownloads.add(_downloadFont(a.asset, url, family.name));
if (!loadedRoboto) pendingDownloads.add(_downloadFont('Roboto', _robotoUrl, 'Roboto'));
await Future.wait(pendingDownloads);      // 启动阶段全部并行下载并等待
```

结论：① **每个声明文件都会在启动阶段下载**，无按需机制；② 未声明名为 `Roboto` 的 family 时，引擎会额外从 `fonts.gstatic.com/s/roboto/v32/…woff2` 下载 Roboto（离线必然失败，仅打警告）；③ 字体必须控制在几百 KiB 量级。

### 4.2 实测体积（语料 = 项目全部文案，784 去重字符 / 610 汉字；`--no-hinting` + 默认 `--layout-features`）

| 产物 | 体积 |
|---|---|
| 原始 `LXGWWenKai-Regular.ttf` | **24.31 MiB** |
| 子集 **TTF**（推荐基线） | **286.0 KiB** |
| 子集 TTF（`--layout-features='*'`） | 320.5 KiB |
| 子集 WOFF | 186.1 KiB |
| 子集 **WOFF2** | **151.3 KiB** |
| 子集 WOFF2（全特性 / 仅 `kern,liga`） | 162.2 KiB / 146.9 KiB |
| GB2312 全部 6763 汉字 → TTF / WOFF2 | 3.19 MiB / 1.47 MiB |
| Inter 原始 / 拉丁子集 WOFF2（保留可变轴） / 静态 w700 子集 | 0.83 MiB / **43.5 KiB** / 12.5 KiB |

（Inter 轴：`opsz` 14–32、`wght` 100–900。）自检：子集 family 名保留 `LXGW WenKai`、992 glyph、784 字符 **0 缺失**、CanvasKit 能建出 typeface。

### 4.3 可复制的 `pyftsubset` 命令

```bash
# 依赖：pip install "fonttools[woff]" brotli
python tool/make_corpus.py                     # 见 §4.7 → tool/corpus.txt

# 文楷子集（TTF，保守基线）
python -m fontTools.subset fonts/LXGWWenKai-Regular.ttf \
  --text-file=tool/corpus.txt --output-file=assets/fonts/LXGWWenKai-subset.ttf \
  --no-hinting --desubroutinize --drop-tables+=DSIG --notdef-outline \
  --name-IDs='*' --name-languages='*' --recalc-bounds \
  --no-ignore-missing-unicodes          # 缺字直接失败 = CI 守门

# 想再省 47%：换 WOFF2（151.3 KiB）
python -m fontTools.subset fonts/LXGWWenKai-Regular.ttf \
  --text-file=tool/corpus.txt --output-file=assets/fonts/LXGWWenKai-subset.woff2 \
  --flavor=woff2 --no-hinting --desubroutinize --name-IDs='*' --name-languages='*'

# Inter 拉丁子集（保留可变轴）
python -m fontTools.subset fonts/Inter-VariableFont_opsz,wght.ttf \
  --text-file=tool/corpus-latin.txt --output-file=assets/fonts/Inter-subset.woff2 \
  --flavor=woff2 --no-hinting
```

参数语义（[fontTools subset 文档](https://fonttools.readthedocs.io/en/latest/subset/)）：`--text-file`/`--text`/`--unicodes=U+4E00-9FFF`/`--unicodes-file` 任选并可叠加；**`--layout-features` 不写即默认集**（`calt,ccmp,clig,curs,dnom,frac,kern,liga,locl,mark,mkmk,numr,rclt,rlig,rvrn` + 脚本必需）——CJK 项目保持默认，`='*'` 多 11~34 KiB，`='kern,liga'` 会丢 `locl/ccmp`；`--flavor=woff2` 需 brotli；`--no-hinting` 官方称最多省 ~30%（实测 TTF 320.5→286.0 KiB）；`--no-ignore-missing-unicodes` 让缺字报错（默认静默忽略，最易踩）。

### 4.4 Flutter Web 直接支持 WOFF2 吗？

**支持（3.47）**，证据：① 引擎把 Roboto 兜底字体硬编码为 `.woff2` 并直接交给 Skia（`canvaskit/fonts.dart:14-15,130-133`）；② Noto 兜底表 `font_fallback_data.dart` 有 **724** 条 `.woff2`，下载后走 `Typeface.MakeFreeTypeFaceFromData`（`font_fallback_service.dart:483-499`）；③ 历史损坏（3.10–3.24，[flutter#128485](https://github.com/flutter/flutter/issues/128485)）已由 [engine#55908](https://github.com/flutter/engine/pull/55908) 修复；④ 文档那句"不支持 woff/woff2"限定于**桌面平台**（[Use a custom font](https://docs.flutter.dev/cookbook/design/fonts)）。结论：TTF 最稳（286 KiB 已足够小），WOFF2 更小（151 KiB）但上线前在 Chrome/Safari/Firefox 各冒烟一次（关注控制台 `Verify that … contains a valid font`）。

### 4.5 `font-display` / `FontLoader` / 懒加载

- **`font-display` 对 Flutter asset 字体无效**：它在浏览器渲染 CSS `@font-face` 时生效，而 Flutter 是 fetch 字节后交 Skia（仅当自己在 HTML 里写 `@font-face` 给 DOM 使用时才有意义）。
- **懒加载**：`FontLoader`（`package:flutter/services.dart`）可把下载推迟到首帧之后：

```dart
void main() {
  runApp(const App());                                  // 首帧不阻塞
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final loader = FontLoader('LXGW WenKai')
      ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-subset.ttf'));
    await loader.load();
    cjkReady.value = true;                              // 触发重排/淡入
  });
}
```

  纯 Dart 侧等价物是 `dart:ui` 的 `loadFontFromList(bytes, fontFamily: 'LXGW WenKai')`（不传 family 时用字体内部名）。注意它只是"延后"，不是浏览器 `unicode-range` 那种分片按需；字体生效后引擎会 relayout，**要预留空间或用过渡动画**避免文字跳动。建议：子集只有 151~286 KiB → **启动即加载**，仅在字体 >1 MiB 时才做懒加载。

### 4.6 CJK 兜底陷阱

1. **缺字 → 自动下 Noto**：3.47 新增 Font fallback service（release notes "[web] Add font fallback service"，[PR #185314](https://github.com/flutter/flutter/pull/185314)），按 Unicode block 从 `fontFallbackBaseUrl`（默认 `fonts.gstatic.com`）下载 `notosanssc/…woff2`（`zh/zh-Hans/zh-CN` 优先 `Noto Sans SC`）。后果：离线失效、隐私外泄、字体到位后重排。失败时打印 `Could not find a set of Noto fonts to display all missing characters. Please add a font asset for the missing characters.` 对策：语料 100% 覆盖 + CI 校验（推荐）；`fontFallbackBaseUrl` 指向自托管 Noto 子集；`fontFamilyFallback` 显式指定但那些字体同样会被启动时下载。
2. **`fontFamilyFallback` 是 per-style 的**，不会全局生效，漏写就走 Noto 兜底。
3. **豆腐块**只在"连兜底都失败"时出现（`.notdef`）；pyftsubset 默认 `--no-notdef-outline` 会去掉其轮廓，此时显示空白而非方框，更难排查 → 给 CJK 子集加 `--notdef-outline`。
4. **乱码字符集**（`scrambleChars` 里的 `± $#@&*%?!<>-_\/[]{}—=+^`）必须在语料内；Emoji 会触发 `Noto Color Emoji`（可能多个分片）。
5. **Flutter Web 没有"系统中文字体"这层**（Skia 不走 CSS 字体栈）：没声明就是没有。

### 4.7 语料生成 + CI 守门

```python
# tool/make_corpus.py
import pathlib
chars = set(open('tool/base-chars.txt', encoding='utf-8').read())   # ASCII+中英标点+全角+数字
for p in pathlib.Path('lib').rglob('*.dart'): chars |= set(p.read_text(encoding='utf-8'))
chars -= set('\n\r\t')
pathlib.Path('tool/corpus.txt').write_text(''.join(sorted(chars)), encoding='utf-8')
# tool/check_font_coverage.py —— 语料每个字符都必须在子集 cmap 中
from fontTools.ttLib import TTFont; import pathlib, sys
cmap = TTFont('assets/fonts/LXGWWenKai-subset.ttf').getBestCmap()
miss = [c for c in pathlib.Path('tool/corpus.txt').read_text(encoding='utf-8') if ord(c) not in cmap]
if miss: sys.exit('MISSING GLYPHS: ' + ''.join(miss[:50]))
print('font coverage OK')
```

CI 顺序必须是 `make_corpus.py` → `pyftsubset` → `check_font_coverage.py` → `flutter build web`；句子池要作为 Dart 常量（唯一事实来源），改文案后忘重新子集化就会在线上触发 Noto 下载。

## 5. 资源优化

实测：`instruction.png` = **70,902 B，186×230，RGBA**；Pillow/ffmpeg 转 **WebP q80 = 18.2 / 18.0 KiB（−74%）**，q90 = 21.5 KiB，而 `Pillow optimize=True` 的 PNG 只到 69.2 KiB（无损收益极小）。

```bash
oxipng -o max --strip safe assets/logo.png                                   # 无损（本机需自行安装）
pngquant --quality=65-85 --speed 1 --strip --force --output assets/logo.png assets/logo.png
cwebp -q 82 -m 6 -metadata none assets/logo.png -o assets/logo.webp
ffmpeg -y -i assets/logo.png -c:v libwebp -quality 82 -compression_level 6 assets/logo.webp   # 本机可用
```

Flutter Web 支持 WebP/AVIF（引擎格式枚举 `png, gif, jpeg, webp, bmp, avif`，含 animated webp 探测，`_engine/engine/image_format_detector.dart`）；官方博客也建议先"按需分辨率"再换格式（示例 319 KB PNG → 38 KB WebP → 10 KB AVIF），并给出 `<link rel="preload">` 与 index.html splash 的做法（[官方性能博客](https://flutter.dev/blog/best-practices-for-optimizing-flutter-web-loading-speed)）。**分辨率变体**：`assets/logo.webp` + `assets/2.0x/logo.webp` + `assets/3.0x/logo.webp`，`AssetImage` 按 DPR 自动选择，pubspec 只声明主资源即可（[Assets and images](https://docs.flutter.dev/ui/assets/assets-and-images)）。本项目 logo 显示 186×230 → 提供 186×230 / 372×460 / 558×690 三档 WebP；霓虹发光用 `BoxShadow`/`ImageFiltered` 实现，不要烘焙进图片。

## 6. 其它 Web 细节

**6.1 `shared_preferences`**：Web 后端就是 **localStorage**（新旧 API 相同）；Web Storage 每源 **5 MiB**（合计 10 MiB），超限抛 `QuotaExceededError`（[MDN](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)）；只支持 `int/double/bool/String/List<String>`；旧 API 默认 key 前缀 `flutter.`；插件自述"must not be used for storing critical data"（[pub.dev](https://pub.dev/packages/shared_preferences)）。新项目用 `SharedPreferencesAsync`。**换域名 = 换 origin = 换存储**（GH Pages 与 CF Pages 数据互不可见）；需要抗清缓存用 `navigator.storage.persist()`。

**6.2 后退键 / 深链 / `go_router`**：默认是 hash 策略；要干净路径用 `usePathUrlStrategy()`（`flutter_web_plugins`，须在 `runApp` 前调用），并**必须让服务器把未知路径 rewrite 到 index.html**：GH Pages → `404.html`；CF Pages → `_redirects: /* /index.html 200`（[URL 策略](https://docs.flutter.dev/ui/navigation/url-strategies)）。`go_router`（18.0.2）基于 Router API，浏览器前进/后退与地址栏输入自动映射为路由变化（[package](https://pub.dev/packages/go_router)、[Web topic](https://pub.dev/documentation/go_router/latest/topics/Web-topic.html)）；嵌套 `ShellRoute`/内层 Navigator 要用 [`NavigatorPopHandler`](https://api.flutter.dev/flutter/widgets/NavigatorPopHandler-class.html) 包住，否则后退会直接弹掉整个 shell；`--base-href` 与部署路径不一致会让深链解析错。

**6.3 `Space` / `Enter`**：用现代 API（`RawKeyboardListener` 已废弃）：

```dart
Focus(autofocus: true, child: Shortcuts(
  shortcuts: const { SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                     SingleActivator(LogicalKeyboardKey.enter): ActivateIntent() },
  child: Actions(
    actions: { ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { generate(); return null; }) },
    child: const Body())));
```

局部监听可用 `Focus(onKeyEvent: ...)` 返回 `KeyEventResult.handled/ignored`；全局用 `HardwareKeyboard.instance.addHandler(...)`（记得移除）。**Web 特有坑**：按键只在 Flutter 视图持有 DOM 焦点时到达——首访未点击时可能被浏览器/其它 DOM 吃掉，需根节点 `autofocus: true` + 指针事件后 `FocusScope.of(context).requestFocus()` 兜底；页面内嵌第三方 DOM（如 giscus iframe）抢焦点后按键会失效。测试用 `tester.sendKeyEvent(LogicalKeyboardKey.space)`（[Actions & shortcuts](https://docs.flutter.dev/ui/interactivity/actions-and-shortcuts)、[Keyboard focus](https://docs.flutter.dev/ui/interactivity/focus)）。

## 7. 本项目的推荐决策

| 决策点 | 推荐 | 理由 |
|---|---|---|
| 部署平台 | **Cloudflare Pages 主站 + GitHub Pages 镜像** | CF 可设 COOP/COEP、Cache-Control、`_redirects`；GH Pages 不能设任何响应头 |
| 构建命令 | `flutter build web --release --base-href /<repo>/ --no-web-resources-cdn --wasm` | `--no-web-resources-cdn` 是离线前提；`--wasm` 保留 JS 回退 |
| 渲染器 | 不指定（wasm⇒skwasm，JS⇒canvaskit），不碰 `FLUTTER_WEB_USE_*` | `--web-renderer` 已删除；两渲染器 CJK 造型一致 |
| 多线程 wasm | CF 配 COOP/COEP；GH 接受单线程（或 coi-serviceworker） | 单线程仅性能损失 |
| 中文字体 | 子集 **TTF 286 KiB**（保守）/ **WOFF2 151 KiB**（三浏览器冒烟后） | 24.31 MiB 不可接受，也贴 CF 单文件 25 MiB 上限 |
| 语料策略 | Dart 常量句子池 → `make_corpus.py` → `pyftsubset --no-ignore-missing-unicodes` → `check_font_coverage.py` 守门 | 杜绝线上触发 Noto 兜底下载（离线/隐私/重排） |
| Inter | 保留可变轴的拉丁子集（43.5 KiB），用 `fontWeight` 驱动 `wght` | 3.41 起 `FontWeight` 会写入 `wght` 轴（[breaking change](https://docs.flutter.dev/release/breaking-changes/font-weight-variation)）；`opsz` 用 `FontVariation('opsz', n)` |
| 额外 Roboto 请求 | 接受（离线时仅警告）；若要消除，就在 pubspec 里声明一个名为 `Roboto` 的 family 指向自己的拉丁子集 | 引擎逻辑 `canvaskit/fonts.dart:130-133`：无 `Roboto` 家族必下载 |
| 字体加载时机 | 启动即加载；仅 >1 MiB 才用 `FontLoader` 延后 | 简单且无首帧重排 |
| 离线 | 自写 SWR SW（构建后写入）+ 自定义 `flutter_bootstrap.js` 注册；不传 `serviceWorkerSettings` | 3.41 起默认 SW 是自清理 stub，注册它会强制刷新 |
| PWA 元数据 | `display: standalone`、`theme_color/background_color: #000000`、192/512 + maskable、`lang="zh-CN"` | 匹配黑底霓虹风格并满足 2026 清单 |
| Logo | 三档 WebP（q≈82，~18 KiB 级别）+ `2.0x`/`3.0x` 目录 | 实测 PNG→WebP 省 74% |
| 状态存储 | `SharedPreferencesAsync` 只存小数据（≪5 MiB） | Web 上即 localStorage，超限抛 `QuotaExceededError` |
| 路由 | `usePathUrlStrategy()` + `go_router` + `404.html`/`_redirects`；嵌套导航加 `NavigatorPopHandler` | 干净深链 + 正确后退键 |
| 键盘 | 根 `Focus(autofocus: true)` + `Shortcuts/Actions`（Space/Enter → 生成指令） | Web 按键依赖 DOM 焦点 |
| 产物卫生 | CI 删除 `*.map`；`--source-maps` 仅在需符号化时开 | 官方警告：公开 map 暴露源码结构 |

## 附录：一次性验证（可复现）

```bash
flutter --version                                   # 3.47.5 / Dart 3.13.4
flutter build web --help -v                         # 确认无 --web-renderer、--pwa-strategy 已隐藏
python -c "import fontTools,brotli;print(fontTools.version)"        # 4.63.0 / brotli OK
# 语料 → 子集 → 体积（§4.2/§4.3），cmap 校验 0 缺失；PNG 186x230 → WebP q80 18.2 KiB
```
