# Review: shop_app

I read every file in `shop_app/`: 5 Dart files, `pubspec.yaml`, `Info.plist`, `build.gradle` and `AndroidManifest.xml`. I didn't build or run the app, so everything below comes from reading the code.

In short: **the cart doesn't work.** Adding an item never updates the screen, and checking out ends on a black screen or throws an error. The app also has serious security problems you need to fix before release, starting with a live secret key in the code. Below, the issues are grouped by how urgent they are.

---

## Fix right away: security

### 1. A live secret API key is in the app (`lib/main.dart:6`)
```dart
const apiKey = 'DEMO_SECRET_KEY_NOT_REAL_123456';
```
- Anything compiled into a Flutter app can be pulled back out of the APK or IPA with `strings`, so you can't keep this key secret. The `DEMO_SECRET_KEY…` prefix looks like a Stripe-style **live secret** key, which should never be on a phone at all.
- It's also sent in the URL (`cart_page.dart:12`, `?key=$apiKey`), so it ends up in server and proxy logs.
- **What to do:** treat the key as leaked and **rotate it now**. If this folder is in git, the old key is still in the history, so rotating is the only real fix. Move the calls that need the key to your backend. The app should only send the user's session token, in an `Authorization` header.

### 2. Passwords are sent unencrypted
- `baseUrl = 'http://api.myshop.in/v1'` uses plain HTTP, and the login sends the email and password to it.
- Both platforms have been set to allow this:
  - **iOS** (`Info.plist`): `NSAllowsArbitraryLoads = true` turns off App Transport Security for the whole app. Expect questions about it in App Review.
  - **Android** (`AndroidManifest.xml`): `android:usesCleartextTraffic="true"`.
- **What to do:** switch to `https://`, delete both of those settings, and let the platform defaults block plain HTTP.

### 3. The auth token is stored and logged as plain text (`login_page.dart:23-25`)
- `print('login response: $data')` writes the full response, token included, to the device log. Any attached debugger or logcat can read it, and on older Android versions other apps could too.
- `SharedPreferences` stores data as plain text (an XML file on Android, a plist on iOS). Put tokens in `flutter_secure_storage`, which uses the Keychain and Keystore.
- Remove `print`, or use `debugPrint` inside `if (kDebugMode)`. `flutter_lints` already flags it as `avoid_print`.

### 4. Release builds are signed with the debug key (`android/app/build.gradle:21`)
`signingConfig signingConfigs.debug` will be rejected by Play, and anyone with the debug key could sign an "update". Set up a real release keystore and keep `key.properties` out of git.

---

## Bugs that break the app

### 5. The cart never updates (`cart_cubit.dart:20-23`), and this is the main bug
```dart
void add(Product p) {
  state.items.add(p);  // changes the current state object
  emit(state);         // emits the same object
}
```
`emit` does nothing when the new state equals the current one, and here it's literally the same object. `BlocBuilder` never rebuilds, so the item is added in memory but never appears on screen. Bloc only works if each change creates a **new state object**:

```dart
class CartState {
  const CartState({this.items = const [], this.status = CartStatus.idle});
  final List<Product> items;
  final CartStatus status;
  double get total => items.fold(0, (s, p) => s + p.price);

  CartState copyWith({List<Product>? items, CartStatus? status}) =>
      CartState(items: items ?? this.items, status: status ?? this.status);
}

enum CartStatus { idle, checkingOut, success, failure }

void add(Product p) => emit(state.copyWith(items: [...state.items, p]));
```
Also make `checkoutDone` `final`, since a mutable field in a state class causes the same problem. Add `equatable`, or `==`/`hashCode`, to `CartState` and `Product` so equality checks work.

### 6. Calling `Navigator.pop` inside `BlocBuilder.builder` (`cart_page.dart:22-24`)
- `builder` runs while the widget is being built and can run many times. Navigating from there throws "setState() or markNeedsBuild() called during build" and can pop more than once.
- `CartPage` arrived through `pushReplacement` and is the only route on the stack, so popping it leaves a **black screen**.
- `checkoutDone` also stays `true`, so every later rebuild tries to pop again.
- **What to do:** put one-time actions like navigation or snackbars in a `BlocListener` (or `BlocConsumer`) with a `listenWhen`, and decide where the user should go after checkout, such as a confirmation page.

### 7. A new cubit is created on every rebuild, and none are ever closed (`main.dart:18-19`)
`BlocProvider.value(value: CartCubit())` is wrong here. `.value` is for passing on a cubit that **already exists**. Writing `CartCubit()` inside `build` makes a new cubit, and an empty cart, every time `ShopApp` rebuilds (theme or locale changes, hot reload), and `.value` never calls `close()`. Use:
```dart
BlocProvider(create: (_) => CartCubit(), child: MaterialApp(...))
```

### 8. The login spinner can get stuck, or the app can crash (`login_page.dart:18-28`)
- There's no `try/catch`. A network error, a non-200 response or a non-JSON body throws, and `loading` stays `true` forever.
- `data['token']` can be `null`, for example on a wrong password, and `setString(..., null)` fails the null-safety check and throws.
- `res.statusCode` is never checked, so a 401 is handled like a successful login.
- `setState` and `Navigator.of(context)` are used after `await` without checking `if (!mounted) return;`. Lints warn about `use_build_context_synchronously`.
- `emailController` and `passwordController` are never `dispose`d.

### 9. Recommendations are re-fetched on every rebuild and can spin forever (`cart_page.dart:29-34`)
- `future: _recommendations()` creates a new Future on every build, which is every time the cart changes. Each one fires a new HTTP request and resets the list to the loading spinner.
- On error, `snap.hasData` is false forever, so it spins forever. Check `snap.hasError` as well.
- `r['name']` is `dynamic`, so a missing key or a non-string value crashes. Parse it into a model.
- **What to do:** load this data once, in a cubit (`RecommendationsCubit`) or a repository called from `initState`, not in `build`.

### 10. Checkout has no loading state, error handling or double-tap guard (`cart_cubit.dart:25-28`)
Pressing Checkout twice starts two checkouts. There's no failure path. The cubit can `emit` after it's closed if the user leaves during the 2-second delay; add `if (isClosed) return;`. Use the `status` enum from #5 to drive a disabled button and spinner.

### 11. Layout overflow (`cart_page.dart:25`, `login_page.dart:35`)
- The cart is a plain `Column`. With a few items plus recommendations it overflows with the yellow and black stripes. Use a `ListView` or a `CustomScrollView`.
- The login `Column` overflows when the keyboard opens on small phones. Wrap it in `SingleChildScrollView` and `SafeArea`.

### 12. `ProfilePage` leaks its animation and can't be reached (`profile_page.dart`)
- `_pulse` is never disposed, so the ticker keeps running after the page closes. Add `dispose() { _pulse.dispose(); super.dispose(); }`.
- Nothing navigates to `ProfilePage`, so right now it's unused code.
- `pickImage` throws a `PlatformException` when camera permission is denied, and nothing catches it. Pass `maxWidth` and `imageQuality` too, or you'll load a 12 MP photo for a 96 px avatar.
- The pulse loops forever, which wastes battery and ignores reduced-motion settings. Check `MediaQuery.of(context).disableAnimations`, or pulse only while something is loading.

---

## Platform config problems

| Where | Problem | Fix |
|---|---|---|
| `ios/Runner/Info.plist` | **No `NSCameraUsageDescription`.** iOS kills the app as soon as the camera opens. | Add the key with a short explanation of why the app needs the camera. |
| `AndroidManifest.xml` (main) | **No `INTERNET` permission.** Flutter's template only puts it in the debug and profile manifests, so **release builds can't reach the network**. Login fails silently. | Add `<uses-permission android:name="android.permission.INTERNET"/>`. |
| `AndroidManifest.xml` | The `CAMERA` permission is declared, but `image_picker` uses the system camera app through an intent, so it isn't needed. Declaring it actually makes the intent fail unless you request the permission at runtime. | Remove it. |
| `build.gradle` | `targetSdk 33` is hardcoded. Google Play requires a newer target API for new apps and updates (35 since Aug 2025), so uploads will be rejected. | Use `flutter.targetSdkVersion`, or at least the level Play currently requires. |
| `build.gradle` | `applicationId` / `namespace` are still `com.example.*`. Play blocks `com.example`. | Pick your real package ID now, because it can't change after release. |
| `Info.plist` | Portrait-only. iPad multitasking needs all orientations unless you set `UIRequiresFullScreen`. | Add the iPad orientations, or opt out on purpose. |

---

## Architecture and code quality

- **Bloc is only used for the cart.** Login does HTTP, storage and navigation directly in the widget, and the cart page calls HTTP in `build`. Give login an `AuthCubit` / `AuthRepository`, give recommendations a cubit, and keep `http` out of widgets. That also makes the logic testable.
- **Features import from `main.dart`** (`import '../../main.dart'`) to get `baseUrl` and `apiKey`, so the imports go in a circle. Move config to something like `lib/core/config.dart`, read the environment with `--dart-define`, and pass an API client in through `RepositoryProvider`.
- **No auto-login.** The token is saved, but the app always opens on `LoginPage`. Check for the token at startup, or with an `AuthCubit`, and choose the first screen from that. There's also no logout or token expiry handling.
- **Money as `double`.** Use integer paise, or a decimal type, for prices and totals. `'₹${p.price}'` shows `₹99.9` and float-rounding artifacts like `₹300.00000000000006`. Format with `intl`'s `NumberFormat.currency(locale: 'en_IN', symbol: '₹')`.
- **Hardcoded `Colors.black` text** (`cart_page.dart:28`) is invisible in dark mode. Use `Theme.of(context).textTheme`. `MaterialApp` has no `theme` or `darkTheme` either.
- **The login button is a `GestureDetector` around a `Container`.** It has no button semantics for screen readers, no ripple, no keyboard or focus support, and it's 36 px tall, under the 48 dp minimum tap target. The 36 px container also squashes the spinner. Use `FilledButton`/`ElevatedButton` with `onPressed: loading ? null : _login`.
- **Login form polish:** wrap the fields in a `Form` with validators, and add `keyboardType: TextInputType.emailAddress`, `autofillHints` (so password managers work), `textInputAction` and `onSubmitted`.
- **Lint warnings:** `LoginPage` has no `const` constructor or `key`, and `const` is missing on many widgets. Run `flutter analyze`; most of these show up there.
- `debugShowCheckedModeBanner: true` is the default, so the line does nothing. Delete it, or set it to `false` if you meant to hide the banner.
- **There are no tests.** Start with `bloc_test` for `CartCubit`. A single test of `add()` would have caught bug #5.

---

## Suggested order
1. Rotate the leaked key, then move the key-protected calls to your backend (#1).
2. Switch to HTTPS and remove the cleartext exceptions on both platforms (#2).
3. Add the `INTERNET` permission and `NSCameraUsageDescription`, which otherwise break release builds and the camera.
4. Make `CartState` immutable and use `copyWith` (#5), use `BlocProvider(create:)` (#7), and move navigation to a `BlocListener` (#6).
5. Add error handling and `mounted` checks to login (#8), and stop re-fetching recommendations in `build` (#9).
6. Secure token storage, release signing, `targetSdk`, the package ID, then the architecture cleanup.

I can make these fixes for you, starting with the cart cubit and the security items, if you'd like.
