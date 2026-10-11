# Review mode

Goal: find the issues that actually hurt users or slow the team down, and show how to fix each one. Work through the areas below roughly in order of impact. You don't need to report on every area — only where you found something.

## 1. Crashes and correctness (usually Critical/High)

- **`BuildContext` across async gaps.** After any `await` in a widget, check `if (!context.mounted) return;` (or `if (!mounted) return;` in State) before using `context` (Navigator, ScaffoldMessenger, Theme, showDialog). Without it: "Looking up a deactivated widget's ancestor is unsafe" or a crash when the user navigates away mid-request.
- **`setState` after dispose** — same cause; guard with `mounted`.
- **Null-safety escapes:** `!` on values that can really be null (API fields, `ModalRoute.of(context)!.settings.arguments`), `late` fields that may never be initialised, `as` casts on JSON (`json['id'] as int` when the API sends a string).
- **Unhandled futures and errors:** `async` calls without try/catch in blocs, `FutureBuilder`/`StreamBuilder` that ignore `snapshot.hasError`, missing `FlutterError.onError` / `PlatformDispatcher.instance.onError` for crash reporting.
- **Futures created in `build()`:** `FutureBuilder(future: api.fetch())` refetches on every rebuild. Create the future in `initState` or move it into a cubit.
- **Lists:** missing `key`s on reorderable/animated lists, index-based keys on lists whose items move.

## 2. BLoC usage (High/Medium)

Compare against `build-bloc.md`. The common problems:
- **Mutable state / missing equality:** state classes without `Equatable` (or freezed) → `BlocBuilder` doesn't rebuild, or rebuilds constantly. Mutating a list inside state then emitting the same instance → UI doesn't update (`state.items.add(x); emit(state)` is a bug — emit a new list).
- **Emitting after close:** `emit` after an `await` in a Cubit that may have been closed → "Cannot emit new states after calling close". Check `if (isClosed) return;` in long-running cubits.
- **Business logic in widgets:** HTTP/DB calls inside `onPressed` or `initState` instead of a bloc/cubit + repository.
- **Bloc created in the wrong place:** `BlocProvider(create: ...)` inside `build` of a frequently rebuilt widget, or `BlocProvider.value` used to *create* a bloc (leaks — `.value` doesn't close it).
- **Over-broad rebuilds:** a single `BlocBuilder` wrapping the whole screen. Suggest `buildWhen`, `BlocSelector`, or `context.select`.
- **Side effects in builder:** navigation/snackbars inside `BlocBuilder.builder` — belong in `BlocListener` (`listenWhen`).
- **Bloc-to-bloc coupling:** a bloc holding a reference to another bloc. Prefer sharing a repository stream, or reacting in the presentation layer.
- **Event transformers:** search-as-you-type without `debounce`/`restartable()` (bloc_concurrency) → racing requests, stale results.

## 3. Memory and resource leaks (High)

Every one of these must be disposed/closed in `dispose()` (or the cubit's `close()`):
`TextEditingController`, `ScrollController`, `AnimationController`, `PageController`, `TabController`, `FocusNode`, `StreamSubscription`, `Timer`, `ChangeNotifier`s you created, `VideoPlayerController`, camera controllers. Blocs created with `BlocProvider(create:)` are closed automatically; ones created manually are not.

## 4. Performance (Medium, High if user-visible jank)

- `ListView(children: [...])` / `Column` in `SingleChildScrollView` with many items → use `ListView.builder` / `SliverList`.
- Missing `const` constructors on static widgets (lint `prefer_const_constructors`).
- Heavy work on the UI isolate: large JSON decode, image processing, sorting thousands of items → `compute()` / `Isolate.run`.
- `Opacity` animating / `ClipRRect`/`saveLayer` in scrolling lists, `shrinkWrap: true` on long lists, `IntrinsicHeight` in lists.
- Images: `Image.network` without `cacheWidth/cacheHeight` for thumbnails (decodes full-res), no caching (`cached_network_image`).
- `MediaQuery.of(context)` rebuilds on every inset change; prefer `MediaQuery.sizeOf(context)` etc.

## 5. Security (Critical if secrets/tokens leak)

- API keys, secrets, or tokens hard-coded in Dart — they are trivially extracted from the APK/IPA. Real secrets belong on a server; for config use `--dart-define-from-file` and accept that client-side values are public.
- Auth tokens in `SharedPreferences` → use `flutter_secure_storage` (Keychain / Keystore).
- `http://` URLs (blocked by default on iOS ATS and Android 9+ cleartext policy), disabled certificate checks (`badCertificateCallback => true`).
- Logging tokens/PII with `print`/`debugPrint` in release builds.

## 6. Architecture and maintainability (Medium/Low)

- Layers: UI → Bloc/Cubit → Repository → Data source (API/DB). Widgets shouldn't import `http`/`dio` directly.
- Giant widget files (500+ lines) — split into smaller widgets (classes, not `_buildX()` methods, so Flutter can skip rebuilding them).
- Hard-coded strings/colors/sizes scattered around → `ThemeData`/`ColorScheme`/`TextTheme`, `l10n` (ARB) if the app is or will be multilingual.
- Tests: blocs/cubits should have `bloc_test` tests; flag their absence once, as Medium, with an example test.

## 7. Platform & accessibility (Medium)

See the "Platform mindset" section in SKILL.md, plus:
- Tap targets < 48×48 dp, icon buttons without `tooltip`/`Semantics`.
- Text that overflows at large font scale or with long translations (fixed-height containers around `Text`).
- Hard-coded `TextStyle(color: Colors.black)` that breaks dark mode.

## Before writing the report

Re-read each finding and ask: is this real (did I see the code), is the severity right, and is the fix correct and minimal? Remove anything that fails. Then write the report in the format from SKILL.md.
