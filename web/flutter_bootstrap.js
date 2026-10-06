// Flutter web bootstrap for 指令 · 食指指令生成器.
//
// WHY THIS FILE EXISTS
// --------------------
// `flutter build web` substitutes two template tokens (each written as a name
// wrapped in DOUBLE CURLY BRACES — see the two lines further down that are the
// only place they may appear):
//
//   flutter_js            -> the whole of the engine's flutter.js loader
//   flutter_build_config  -> `_flutter.buildConfig = {...}` for this build
//
// It does that in exactly two places: this file (if `web/flutter_bootstrap.js`
// exists) and `web/index.html`. The substitution is a plain in-place text
// replacement — the tool never extracts an inline block out of the HTML.
//
// Therefore the tokens must live in ONE of the two, never both: each copy of
// flutter.js ends with its own `_flutter.loader.load(...)` call, and the loader
// only guards against re-injecting `main.dart.js` per loader script element, so
// two copies would download and evaluate it twice and mount the app on top of
// itself.
//
// Keeping them here (rather than inline in index.html) means:
//   * `index.html` stays small and cacheable, and the ~12 KB loader keeps its
//     own cache entry,
//   * `web/index.html` can keep the plain `<script src="flutter_bootstrap.js"
//     async></script>` tag that Flutter expects,
//   * the service worker settings below stay wired up.
//
// !! DO NOT WRITE A BRACED TOKEN NAME IN ANY COMMENT IN THIS FILE OR IN
// !! web/index.html. Substitution is textual and unconditional, so a token
// !! quoted inside a `//` comment is expanded too; because the real flutter.js
// !! source spans several lines it escapes the comment and the whole file stops
// !! parsing (`node --check build/web/flutter_bootstrap.js` is the guard).
//
// The customisation deliberately avoids the old `window.addEventListener('load')`
// pattern: the engine is initialised from the `onEntrypointLoaded` callback, and
// the splash screen is dismissed in index.html on the engine's
// `flutter-first-frame` DOM event (fired after the first frame is painted).

{{flutter_js}}
{{flutter_build_config}}

// The service-worker-version token expands to `"<hash>"` when the build was made
// with `--pwa-strategy=offline-first` (Flutter's default) and to `null`
// otherwise. flutter.js registers the worker whenever `serviceWorkerSettings` is
// truthy, so only pass the object when there is a real version to register.
const swVersion = {{flutter_service_worker_version}};

_flutter.loader.load({
  ...(swVersion ? { serviceWorkerSettings: { serviceWorkerVersion: swVersion } } : {}),

  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      // Intentionally empty. The build config already carries the renderer and
      // the CanvasKit base URL, so `--wasm`, `--web-renderer` and
      // `--no-web-resources-cdn` all keep working; pinning any of them here
      // would silently override the build. Available keys, should a real need
      // appear later: canvasKitBaseUrl, canvasKitVariant, renderer,
      // fontFallbackBaseUrl, useColorEmoji, nonce.
    });

    await appRunner.runApp();
  },
});
