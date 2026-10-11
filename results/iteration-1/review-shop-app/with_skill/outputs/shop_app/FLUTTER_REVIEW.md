# Shop App — Review Report

## Summary
The app is small and the feature-first layout (`lib/features/auth|cart|profile`) is a good start, but it has several problems that will cause visible bugs or crashes, and one security problem that needs fixing today. **The most urgent issue is the live secret key (`DEMO_SECRET_KEY…`) hard-coded in `lib/main.dart` and sent over plain `http://`.** Anyone can pull it out of the APK/IPA or read it off the network, so revoke it now. Next come the cart (adding items never updates the UI, and checkout pops the only route) and a few crash paths: login with no error handling, a missing iOS camera permission string, and an AnimationController that is never disposed.
**Verdict:** ❌ Not ready to ship. Fix the Critical and High items first.

How this was checked: I read every file and ran `flutter analyze` on a copy (Flutter 3.44.4). It printed *"No issues found"*, but only because **there is no `analysis_options.yaml`**, so `flutter_lints` is installed and never turned on. With the lints enabled, analyze reports 12 issues, including `use_build_context_synchronously` and `avoid_print`. Also, `dart format` would reformat 3 files.

---

## 🔴 Critical

### 1. Live secret API key hard-coded in the app
**Where:** `lib/main.dart:6`, used in `lib/features/cart/view/cart_page.dart:12` (Both)
**Problem:** `const apiKey = 'DEMO_SECRET_KEY…'` is compiled into the app binary. Anyone can recover it with `strings` on the APK/IPA. On top of that, it goes into a **query string** over **plain HTTP**, so proxies, Wi-Fi snoopers and server logs all see it. A `DEMO_SECRET_KEY…` key usually grants full server-side access (payments, for example), and you can't keep any secret safe inside a mobile app.
**Fix:**
1. **Revoke/rotate this key now.** It has to be treated as leaked, and it stays in git history.
2. Move the call that needs the key to your backend. The app authenticates with the *user's* token, and the server adds the secret.
```dart
// before
http.get(Uri.parse('$baseUrl/recommend?key=$apiKey'));
// after — no secret in the app; user's token in a header
http.get(Uri.parse('$baseUrl/recommend'),
    headers: {'Authorization': 'Bearer $userToken'});
```
3. For non-secret config (base URL, flavors), use `--dart-define-from-file=config/prod.json` and `String.fromEnvironment('BASE_URL')`.

### 2. All traffic (including passwords) goes over cleartext HTTP
**Where:** `lib/main.dart:7`, `android/app/src/main/AndroidManifest.xml:6`, `ios/Runner/Info.plist:13-17` (Both)
**Problem:** `baseUrl` is `http://`, and both platforms' protections are switched off to allow it (`usesCleartextTraffic="true"`, `NSAllowsArbitraryLoads=true`). The login request sends the email and password in clear text. On iOS, `NSAllowsArbitraryLoads` also needs a justification at App Review.
**Fix:** Serve the API over HTTPS, then remove both overrides.
```dart
const baseUrl = 'https://api.myshop.in/v1';
```
```xml
<!-- AndroidManifest.xml: delete android:usesCleartextTraffic="true" -->
<!-- Info.plist: delete the whole NSAppTransportSecurity dict -->
```

### 3. iOS crashes when the user taps the avatar (missing camera usage string)
**Where:** `ios/Runner/Info.plist` (missing key), triggered from `lib/features/profile/profile_page.dart:22` (iOS)
**Problem:** `ImagePicker().pickImage(source: ImageSource.camera)` needs `NSCameraUsageDescription`. Without it, iOS **kills the app** the moment the camera opens, and App Store review rejects the build.
**Fix:**
```xml
<key>NSCameraUsageDescription</key>
<string>Take a photo for your profile picture.</string>
<!-- add this too if you later allow gallery picks -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose a photo for your profile picture.</string>
```

### 4. Login crashes or hangs on any failed request
**Where:** `lib/features/auth/login_page.dart:18-28` (Both)
**Problem:** Nothing is checked or caught:
- Wrong password / 401 / 500 → `data['token']` is `null` → `prefs.setString(..., null)` throws a type error.
- No network → `http.post` throws `ClientException`/`SocketException`.
- The server returns an HTML error page → `jsonDecode` throws `FormatException`.

In every case the exception escapes, `loading` stays `true`, and the user sees **a spinner forever** with no message. The method also calls `Navigator.of(context)` after three `await`s with no `mounted` check, so if the user leaves the screen mid-request you get a "deactivated widget's ancestor" error (the `use_build_context_synchronously` lint flags line 27).
**Fix (minimal, inside the widget — see Medium #13 for moving this into a Cubit):**
```dart
Future<void> _login() async {
  setState(() => loading = true);
  try {
    final res = await http.post(Uri.parse('$baseUrl/login'), body: {
      'email': emailController.text.trim(),
      'password': passwordController.text,
    });
    if (res.statusCode != 200) throw Exception('Login failed (${res.statusCode})');
    final token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
    if (token == null) throw Exception('No token in response');
    await const FlutterSecureStorage().write(key: 'auth_token', value: token);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CartPage()),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not log in. Check your details and try again.')),
    );
  } finally {
    if (mounted) setState(() => loading = false);
  }
}
```

### 5. Auth token stored in plain SharedPreferences, and the login response is printed to the log
**Where:** `lib/features/auth/login_page.dart:23-25` (Both)
**Problem:** `SharedPreferences` is a plain XML/plist file. It can be read on rooted/jailbroken devices and it lands in backups. `print('login response: $data')` writes the **token** to logcat / the device console, and that happens in release builds too.
**Fix:** Add `flutter_secure_storage` (Keychain / Android Keystore) and delete the `print`.
```yaml
# pubspec.yaml
dependencies:
  flutter_secure_storage: ^9.2.2
```
```dart
// before
print('login response: $data');
final prefs = await SharedPreferences.getInstance();
await prefs.setString('auth_token', data['token']);
// after
await const FlutterSecureStorage().write(key: 'auth_token', value: token);
```

---

## 🟠 High

### 6. Adding to the cart never updates the UI (mutated state + no equality)
**Where:** `lib/features/cart/cubit/cart_cubit.dart:10-23` (Both)
**Problem:** `add()` mutates the existing list and then calls `emit(state)` with the **same object**. `Cubit.emit` ignores a state that is `==` the current one, so `BlocBuilder` never rebuilds and the cart looks empty until something else triggers a rebuild. `CartState` also has a mutable field (`bool checkoutDone`) and no value equality.
**Fix:** Make state immutable with `Equatable` and always emit a new instance.
```yaml
dependencies:
  equatable: ^2.0.5
```
```dart
class Product extends Equatable {
  const Product(this.id, this.name, this.price);
  final String id;
  final String name;
  final double price;
  @override
  List<Object?> get props => [id, name, price];
}

enum CartStatus { idle, checkingOut, success, failure }

class CartState extends Equatable {
  const CartState({this.items = const [], this.status = CartStatus.idle});
  final List<Product> items;
  final CartStatus status;
  double get total => items.fold(0, (s, p) => s + p.price);

  CartState copyWith({List<Product>? items, CartStatus? status}) =>
      CartState(items: items ?? this.items, status: status ?? this.status);

  @override
  List<Object?> get props => [items, status];
}

class CartCubit extends Cubit<CartState> {
  CartCubit() : super(const CartState());

  void add(Product p) => emit(state.copyWith(items: [...state.items, p]));

  Future<void> checkout() async {
    emit(state.copyWith(status: CartStatus.checkingOut));
    try {
      await Future.delayed(const Duration(seconds: 2)); // replace with repository call
      if (isClosed) return;
      emit(const CartState(status: CartStatus.success));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(status: CartStatus.failure));
    }
  }
}
```

### 7. Checkout navigates from inside `builder`, and pops the only route
**Where:** `lib/features/cart/view/cart_page.dart:22-24` (Both)
**Problem:** Two bugs:
- `builder` can run many times per state, so `Navigator.pop()` runs during build (it can fire repeatedly and trigger "setState() or markNeedsBuild() called during build").
- `CartPage` was opened with `pushReplacement` from login, so it is the **only route**. Popping it leaves a black screen, and on Android it can close the app.

Also, `checkoutDone` is never reset, so if the page is shown again it pops straight away. The button doesn't disable during the 2-second checkout either, so double taps run two checkouts.
**Fix:** Put side effects in a `BlocListener`/`BlocConsumer`, navigate somewhere real, and disable the button while busy.
```dart
body: BlocConsumer<CartCubit, CartState>(
  listenWhen: (prev, curr) => prev.status != curr.status,
  listener: (context, state) {
    if (state.status == CartStatus.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OrderConfirmedPage()),
      );
    } else if (state.status == CartStatus.failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checkout failed, please try again.')),
      );
    }
  },
  builder: (context, state) => /* … */
      ElevatedButton(
        onPressed: state.status == CartStatus.checkingOut || state.items.isEmpty
            ? null
            : () => context.read<CartCubit>().checkout(),
        child: const Text('Checkout'),
      ),
),
```

### 8. `BlocProvider.value` used to create the CartCubit (leak, and state lost on rebuild)
**Where:** `lib/main.dart:18-19` (Both)
**Problem:** `.value` is for handing an *existing* bloc to a new subtree. It never closes the bloc. Here it builds a **new** `CartCubit()` every time `ShopApp.build` runs (hot reload, theme or locale changes, etc.), which throws the cart away and leaks the old cubit.
**Fix:**
```dart
return BlocProvider(
  create: (_) => CartCubit(),
  child: MaterialApp(
    title: 'Shop',
    home: const LoginPage(),
  ),
);
```

### 9. Recommendations are re-fetched on every rebuild and errors spin forever
**Where:** `lib/features/cart/view/cart_page.dart:11-14, 29-35` (Both)
**Problem:** `FutureBuilder(future: _recommendations())` creates a **new HTTP request on every build**. It sits inside the `BlocBuilder`, so each cart change fires another network call and the list flickers back to a spinner. `snap.hasError` is never checked, so a failed request means an endless spinner. `r['name']` is `dynamic`, so if the API sends a non-string or null, `Text` throws at runtime.
**Fix:** Move the loading into a cubit (`RecommendationsCubit` + a repository) and fetch once. If you want to keep the `FutureBuilder` for now, make `CartPage` stateful, store the future in `initState`, and handle errors:
```dart
late final Future<List<String>> _recs = _repo.fetchRecommendations();
// …
FutureBuilder<List<String>>(
  future: _recs,
  builder: (context, snap) {
    if (snap.hasError) return const Text('Couldn’t load recommendations');
    if (!snap.hasData) return const CircularProgressIndicator.adaptive();
    return Column(children: [for (final name in snap.data!) Text(name)]);
  },
),
```

### 10. Controllers are never disposed (and the profile page throws on close)
**Where:** `lib/features/auth/login_page.dart:14-15`, `lib/features/profile/profile_page.dart:12-19` (Both)
**Problem:** The two `TextEditingController`s and the repeating `AnimationController` are never disposed. When `ProfilePage` closes, a ticker that is still running causes the debug-mode assertion *"was disposed with an active Ticker"*, and in release builds it leaks.
**Fix:**
```dart
// _LoginPageState
@override
void dispose() {
  emailController.dispose();
  passwordController.dispose();
  super.dispose();
}

// _ProfilePageState
@override
void dispose() {
  _pulse.dispose();
  super.dispose();
}
```

### 11. Camera picker fails on Android (CAMERA permission declared but never requested), and there's no error handling
**Where:** `android/app/src/main/AndroidManifest.xml:2`, `lib/features/profile/profile_page.dart:21-24` (Android, plus Both for the error handling)
**Problem:** `image_picker` opens the system camera app through an intent, which needs no permission. But **if the manifest declares `CAMERA` and the user hasn't granted it, Android throws a `SecurityException`** when the camera intent starts, so the picker fails with an unhandled `PlatformException`. If the user denies camera access on iOS, that throws too. `setState` after the `await` also has no `mounted` check.
**Fix:** Remove `<uses-permission android:name="android.permission.CAMERA"/>` (image_picker doesn't need it), and guard the call:
```dart
// needs: import 'package:flutter/services.dart'; (PlatformException)
Future<void> _pick() async {
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 512);
    if (x == null || !mounted) return;
    setState(() => _avatar = File(x.path));
  } on PlatformException catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Camera unavailable — check app permissions.')),
    );
  }
}
```

### 12. Store blockers in the Android build config
**Where:** `android/app/build.gradle:8,12,14,21` (Android)
**Problem:**
- `signingConfig signingConfigs.debug` for release: Play Console rejects debug-signed bundles.
- `applicationId "com.example.shop_app"`: Play rejects the `com.example` prefix, and the ID can't be changed after the first upload. The iOS bundle ID will need the same change.
- `targetSdk 33` is hard-coded. Google Play requires a recent target API level, and 33 has been below the minimum since 2024.

**Fix:** Use your own reverse-domain ID, set up a release keystore (see the Flutter "Build and release an Android app" guide, `key.properties`), and let Flutter manage the target SDK:
```groovy
defaultConfig {
    applicationId "in.myshop.app"
    minSdk flutter.minSdkVersion
    targetSdk flutter.targetSdkVersion
    // …
}
buildTypes {
    release { signingConfig signingConfigs.release }
}
```

---

## 🟡 Medium

### 13. Business logic and HTTP calls live in widgets
**Where:** `lib/features/auth/login_page.dart:18-28`, `lib/features/cart/view/cart_page.dart:11-14`
**Problem:** Login and recommendations call `http` straight from widgets, and both import `main.dart` to reach the constants, so every feature depends on the app entry point. That makes the code impossible to unit-test and goes against the BLoC layering you're aiming for.
**Fix:** Use UI → Cubit → Repository → API client. For example, `features/auth/data/auth_repository.dart` (does the HTTP and returns a token or throws), plus `features/auth/cubit/login_cubit.dart` (states: initial / loading / success / failure). Provide it with `RepositoryProvider`. Move `baseUrl` to `lib/core/config.dart` (read it from `--dart-define`). Once that's done, the `LoginPage` widget just dispatches `context.read<LoginCubit>().submit(email, password)` and reacts in a `BlocListener`.

### 14. Lints are installed but not enabled
**Where:** project root (missing `analysis_options.yaml`)
**Problem:** `flutter_lints` is in `dev_dependencies`, but no `analysis_options.yaml` includes it, so `flutter analyze` reports nothing. With it enabled you get 12 issues, two of which (`use_build_context_synchronously`, `avoid_print`) are real bugs covered above.
**Fix:** Create `analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
```
Then run `flutter analyze` and `dart format lib`.

### 15. Cart list isn't scrollable and will overflow
**Where:** `lib/features/cart/view/cart_page.dart:25-40` (Both)
**Problem:** Cart items, recommendations and the button all sit in a plain `Column`. After a handful of items you get the yellow-black "RenderFlex overflowed" stripe and the Checkout button goes off-screen. This gets worse with a large font size.
**Fix:**
```dart
return Column(
  children: [
    Expanded(
      child: ListView.builder(
        itemCount: state.items.length,
        itemBuilder: (_, i) {
          final p = state.items[i];
          return ListTile(key: ValueKey(p.id), title: Text(p.name), trailing: Text(formatInr(p.price)));
        },
      ),
    ),
    // total + checkout pinned at the bottom, wrapped in SafeArea
    SafeArea(top: false, child: /* total + button */),
  ],
);
```

### 16. Money stored as `double` and printed raw
**Where:** `lib/features/cart/cubit/cart_cubit.dart:7,14`, `lib/features/cart/view/cart_page.dart:27-28`
**Problem:** `0.1 + 0.2` gives `0.30000000000000004`, so totals like `₹59.900000000000006` will show up. Prices also show as `₹50.0`.
**Fix:** Store prices as integer paise (`final int pricePaise;`), and format with `intl`'s `NumberFormat.currency(locale: 'en_IN', symbol: '₹')`. At minimum, use `toStringAsFixed(2)`.

### 17. Login "button" is a `GestureDetector` + `Container`
**Where:** `lib/features/auth/login_page.dart:41-49` (Both)
**Problem:** There's no ripple or press feedback, no semantics (screen readers don't announce it as a button), the 36 dp height is below the 48 dp minimum tap target, and the spinner in a 36 px box is squashed. Hard-coded `Colors.blue` ignores the theme.
**Fix:**
```dart
SizedBox(
  width: double.infinity,
  height: 48,
  child: FilledButton(
    onPressed: loading ? null : _login,
    child: loading
        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
        : const Text('Login'),
  ),
),
```
Also add `keyboardType: TextInputType.emailAddress`, `autofillHints: [AutofillHints.email]` / `[AutofillHints.password]` and `textInputAction` to the fields, and wrap the body in `SafeArea` + `SingleChildScrollView` so the keyboard doesn't cover the fields on small phones.

### 18. Pulsing avatar rebuilds through `Opacity` every frame
**Where:** `lib/features/profile/profile_page.dart:31-40`
**Problem:** `AnimatedBuilder` + `Opacity` rebuilds the subtree and uses an offscreen layer 60 times a second, forever, which is wasted battery. The `FileImage` also decodes the full-resolution camera photo.
**Fix:**
```dart
FadeTransition(
  opacity: Tween(begin: 0.5, end: 1.0).animate(_pulse),
  child: GestureDetector(onTap: _pick, child: CircleAvatar(/* … */)),
)
```
Pass `maxWidth: 512` to `pickImage` (shown above) so you don't hold a 12 MP image in memory. Consider whether an endless pulse is needed at all, and respect `MediaQuery.disableAnimationsOf(context)`.

### 19. No tests
**Where:** project (no `test/` folder)
**Problem:** Bug #6 is exactly the kind of thing a 10-line bloc test catches.
**Fix:** Add `bloc_test` and `mocktail` to `dev_dependencies`:
```dart
blocTest<CartCubit, CartState>(
  'add emits a new state containing the product',
  build: CartCubit.new,
  act: (c) => c.add(const Product('1', 'Tea', 50)),
  expect: () => [const CartState(items: [Product('1', 'Tea', 50)])],
);
```

---

## 🟢 Low

- **Hard-coded black text breaks dark mode.** `cart_page.dart:28` uses `TextStyle(color: Colors.black)`, which turns invisible on a dark background once you add a dark theme. Use `Theme.of(context).textTheme.titleMedium` instead.
- **Missing `const` and keys.** `LoginPage` has no `const` constructor or `key` (`login_page.dart:8`), and 9 widget constructions could be `const`. Running `dart fix --apply` handles most of this once lints are on.
- **`debugShowCheckedModeBanner: true`** (`main.dart:21`) is the default and only affects debug builds. Remove it, or set it to `false` for screenshots.
- **`ProfilePage` is unreachable.** Nothing navigates to it. Add a route or entry point (for example an AppBar action on the cart page), or the camera code is dead.
- **No theme.** `MaterialApp` has no `theme`/`darkTheme`. Add `ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: …), useMaterial3: true)` and a matching `darkTheme`.
- **Formatting.** `dart format lib` changes 3 files.

---

## What's good
- **Feature-first folders** (`features/auth`, `features/cart/{cubit,view}`) scale well. Keep adding `data/` (repositories) the same way.
- **You chose Cubit for the cart**, which is the right amount of ceremony for simple add/checkout logic.
- **`const` constructors and `super.key`** are already used on `ShopApp`, `CartPage` and `ProfilePage`.
- **Controllers live in `State`**, not in `build()`, so they just need disposing, not restructuring.
- **Dependencies are current and minimal** (`flutter_bloc` 8, `http` 1.x, Dart 3.5+).

## Next steps
1. **Today:** revoke the `DEMO_SECRET_KEY…` key, take it out of the app, and switch the API to HTTPS (Critical #1, #2).
2. Fix the crash paths: add `NSCameraUsageDescription`, add try/catch + `mounted` checks to login and the picker, dispose controllers, and remove the Android `CAMERA` permission (#3, #4, #10, #11).
3. Rewrite `CartState`/`CartCubit` with Equatable + `copyWith`, switch to `BlocProvider(create:)`, and move checkout navigation into a `BlocListener` (#6, #7, #8).
4. Move login and recommendations into `AuthRepository` + `LoginCubit` and `RecommendationsCubit`, store the token in `flutter_secure_storage`, and add `bloc_test` tests for each cubit (#5, #9, #13, #19).
5. Add `analysis_options.yaml`, run `dart fix --apply` and `dart format lib`, then sort out signing, the application ID and the target SDK before your first store upload (#12, #14).
