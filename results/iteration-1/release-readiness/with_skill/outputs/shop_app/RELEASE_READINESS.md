# shop_app — Release Readiness Report

## Summary
shop_app is **not ready** for either store yet. Several problems would get the builds rejected outright: the `com.example` package ID, debug signing, and a missing iOS camera permission string. Others break the app on a user's phone: the Android release build has no INTERNET permission, so login can never work, and checkout crashes. **The most urgent fix is the hard-coded `DEMO_SECRET_KEY…` key in `lib/main.dart`.** Anyone can pull it out of the APK/IPA, so treat it as leaked: rotate it and move it to your server. Most fixes are small, so next week is realistic if you start with the Critical list below.

**Verdict: ❌ Not ready.** Blockers: 1–7 under Critical.

How this was checked: I read every file in the project and ran `scripts/flutter_scan.sh`. I also ran `flutter analyze` on Flutter 3.44.4. It says "No issues found", but only because the project has no `analysis_options.yaml`, so the `flutter_lints` rules never run. With the lints turned on it reports 12 issues, including `use_build_context_synchronously` and `avoid_print`. `dart format` would change 3 files. The `ios/` folder has only `Info.plist`, so I couldn't check `project.pbxproj`, the `Podfile`, the app icons, or a privacy manifest. Those items are marked "Verify".

---

## 🔴 Critical — store rejection, crash, or security

### 1. Live secret key hard-coded in the app
**Where:** `lib/main.dart:6`, used in `lib/features/cart/view/cart_page.dart:12` (Both)
**Problem:** `const apiKey = 'DEMO_SECRET_KEY…'` is compiled into the app binary. Anyone can extract it with `strings` on the APK/IPA, even with `--obfuscate`. An `DEMO_SECRET_KEY…` prefix usually means a payment-provider *secret* key, which gives full control of the account. It is also sent in the URL query string (`?key=$apiKey`) over plain HTTP, so it also ends up in proxy and server logs.
**Fix:** Rotate the key now in the provider dashboard, because you should assume it is already exposed. Then move every call that needs it to your own backend. The app should only call your API, using the user's auth token:
```dart
// before
const apiKey = 'DEMO_SECRET_KEY…';
http.get(Uri.parse('$baseUrl/recommend?key=$apiKey'));

// after — no secret in the app; the server adds the key itself
http.get(
  Uri.parse('$baseUrl/recommend'),
  headers: {'Authorization': 'Bearer $userToken'},
);
```

### 2. Release build has no INTERNET permission, so login never works on Android
**Where:** `android/app/src/main/AndroidManifest.xml` (Android)
**Problem:** Flutter adds `INTERNET` only to the debug/profile manifests. Your app works when you run it from the IDE. In the Play Store build, every `http` call fails and nobody can log in.
**Fix:**
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
```

### 3. Package name / bundle ID is still `com.example.shop_app`
**Where:** `android/app/build.gradle:8,12` (Android). Verify `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj` (iOS).
**Problem:** Play Console rejects `com.example.*`. The ID is also permanent once you publish, so choose the final one now.
**Fix:**
```groovy
android {
    namespace "in.myshop.app"
    defaultConfig {
        applicationId "in.myshop.app"
```
Move `MainActivity.kt` to the matching package folder. On iOS, set the same reverse-domain ID in Xcode → Runner → Signing & Capabilities, and register it in App Store Connect.

### 4. Release build is signed with the debug key
**Where:** `android/app/build.gradle:21` (Android)
**Problem:** `signingConfig signingConfigs.debug` produces a debug-signed bundle, and Play Console refuses to accept it.
**Fix:** Create an upload keystore:
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Then load it from `android/key.properties`:
```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```
Add `key.properties` and `*.jks` to `.gitignore`, and back the keystore up somewhere safe. Enrol in Play App Signing so that losing the upload key can be recovered.

### 5. Missing `NSCameraUsageDescription`: crash on iOS and App Review rejection
**Where:** `ios/Runner/Info.plist`. The camera is used in `lib/features/profile/profile_page.dart:22` (iOS)
**Problem:** `ImagePicker().pickImage(source: ImageSource.camera)` needs a usage-description string. Without it, iOS kills the app the moment the avatar is tapped, and App Review rejects the build.
**Fix:**
```xml
<key>NSCameraUsageDescription</key>
<string>Shop App uses the camera so you can take a profile photo.</string>
<!-- add these too if you later allow gallery / video -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Shop App needs access to your photos so you can choose a profile picture.</string>
```

### 6. Cleartext HTTP everywhere (`http://` API, `usesCleartextTraffic`, `NSAllowsArbitraryLoads`)
**Where:** `lib/main.dart:7`, `AndroidManifest.xml:6`, `Info.plist:13-17` (Both)
**Problem:** Email, password, auth token and API key are all sent unencrypted, so anyone on the same café Wi-Fi can read them. On iOS, `NSAllowsArbitraryLoads = true` needs a justification in App Review and is a common reason for rejection. The manifest and plist flags were only added to make plain HTTP work around the platform defaults.
**Fix:** Serve the API over HTTPS (Let's Encrypt or Cloudflare are free), then remove both exceptions:
```dart
const baseUrl = 'https://api.myshop.in/v1';
```
```xml
<!-- AndroidManifest.xml: delete android:usesCleartextTraffic="true" -->
<!-- Info.plist: delete the whole NSAppTransportSecurity dict -->
```

### 7. Checkout crashes and leaves a black screen
**Where:** `lib/features/cart/view/cart_page.dart:22-24` (Both)
**Problem:** `Navigator.pop()` is called inside `BlocBuilder.builder`, which means during a build. Flutter throws "setState() or markNeedsBuild() called during build". There is a second problem: `CartPage` was opened with `pushReplacement`, so it is the only route, and popping it leaves an empty navigator (a black screen). `checkoutDone` also stays `true`, so every rebuild tries to pop again.
**Fix:** Move side effects into a `BlocListener`, and go somewhere real:
```dart
body: BlocListener<CartCubit, CartState>(
  listenWhen: (prev, curr) => !prev.checkoutDone && curr.checkoutDone,
  listener: (context, state) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Order placed!')));
    // e.g. Navigator.of(context).pushReplacement(... OrderSuccessPage ...)
  },
  child: BlocBuilder<CartCubit, CartState>(
    builder: (context, state) { /* UI only, no navigation */ },
  ),
),
```

---

## 🟠 High — real bugs and platform requirements

### 8. `targetSdk 33` is below Google Play's requirement
**Where:** `android/app/build.gradle:14` (Android)
**Problem:** Play blocks new apps and updates whose target is below the current minimum. That minimum has been API 35 since August 2025 and normally moves up each August, so expect **35 or 36**. Check the exact value in Play Console → Policy status before you upload.
**Fix:**
```groovy
targetSdk flutter.targetSdkVersion   // Flutter 3.44 tracks the current Play requirement
// or pin explicitly: targetSdk 35 (or 36 if Play Console asks for it)
```
Re-test on an Android 15/16 device afterwards. Edge-to-edge is enforced, so check that your `SafeArea`s still look right.

### 9. Login: no error handling, no `mounted` check, and the token is printed
**Where:** `lib/features/auth/login_page.dart:18-28` (Both)
**Problem:**
- A wrong password, a 500 response or no signal makes `data['token']` null, or makes `http.post` throw. The exception is unhandled, `loading` stays `true`, and the user is stuck on a spinner forever.
- `Navigator.of(context)` after an `await` crashes if the user left the screen ("Looking up a deactivated widget's ancestor"). `flutter analyze` flags this as `use_build_context_synchronously` once lints are on.
- `print('login response: $data')` writes the auth token to the device log, where other tools can read it.
- The HTTP call sits directly in the widget, which is hard to test.

**Fix (minimal):**
```dart
Future<void> _login() async {
  setState(() => loading = true);
  try {
    final res = await http.post(Uri.parse('$baseUrl/login'),
        body: {'email': emailController.text, 'password': passwordController.text});
    if (res.statusCode != 200) throw Exception('Login failed (${res.statusCode})');
    final token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
    if (token == null) throw Exception('No token in response');
    await const FlutterSecureStorage().write(key: 'auth_token', value: token);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CartPage()));
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log in. Check your details and try again.')));
  } finally {
    if (mounted) setState(() => loading = false);
  }
}
```
Later, move this into an `AuthCubit` + `AuthRepository`, as you already do for the cart.

### 10. Auth token stored in SharedPreferences
**Where:** `lib/features/auth/login_page.dart:24-25` (Both)
**Problem:** SharedPreferences is a plain XML or plist file. It gets included in device backups and is readable on rooted or jailbroken phones.
**Fix:** `flutter pub add flutter_secure_storage` and store the token with it, as shown above. It uses the Keychain on iOS and the Keystore on Android.

### 11. Adding to cart never updates the UI
**Where:** `lib/features/cart/cubit/cart_cubit.dart:20-23` (Both)
**Problem:** `state.items.add(p); emit(state);` emits the *same* object. `Cubit.emit` ignores a state that equals the current one, so `BlocBuilder` never rebuilds and the cart looks empty. `CartState` is also mutable (`bool checkoutDone` isn't final) and has no equality.
**Fix:**
```dart
class CartState extends Equatable {
  const CartState({this.items = const [], this.checkoutDone = false});
  final List<Product> items;
  final bool checkoutDone;
  double get total => items.fold(0, (s, p) => s + p.price);

  CartState copyWith({List<Product>? items, bool? checkoutDone}) => CartState(
      items: items ?? this.items, checkoutDone: checkoutDone ?? this.checkoutDone);

  @override
  List<Object?> get props => [items, checkoutDone];
}

void add(Product p) => emit(state.copyWith(items: [...state.items, p]));

Future<void> checkout() async {
  await Future.delayed(const Duration(seconds: 2));
  if (isClosed) return;
  emit(const CartState(checkoutDone: true));
}
```
(`flutter pub add equatable`, and make `Product` extend `Equatable` too.)

### 12. `AnimationController` never disposed, and camera errors unhandled
**Where:** `lib/features/profile/profile_page.dart:12-24` (Both)
**Problem:** `_pulse` repeats forever and is never disposed, so it leaks a ticker every time the screen is opened (debug builds also assert). If the user denies camera permission, `pickImage` throws a `PlatformException` that nothing catches, and `setState` runs without a `mounted` check.
**Fix:**
```dart
@override
void dispose() {
  _pulse.dispose();
  super.dispose();
}

Future<void> _pick() async {
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.camera);
    if (x == null || !mounted) return;
    setState(() => _avatar = File(x.path));
  } on PlatformException {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera access is needed to take a photo.')));
  }
}
```

### 13. Verify: iOS privacy manifest (`PrivacyInfo.xcprivacy`)
**Where:** `ios/Runner/` (none found) (iOS)
**Problem:** App Store Connect requires reasons for "required-reason APIs". `shared_preferences` uses `UserDefaults`, so a missing declaration produces an ITMS-91053 warning/rejection email.
**Fix:** In Xcode, File → New → App Privacy File, saved as `ios/Runner/PrivacyInfo.xcprivacy` and added to the Runner target. Declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, and list the data you collect (email, user ID). This list must also match your App Store privacy "nutrition label".

### 14. Verify: portrait-only orientation vs. iPad
**Where:** `ios/Runner/Info.plist:18-21` (iOS)
**Problem:** If the app supports iPad (Flutter's default `TARGETED_DEVICE_FAMILY = 1,2`), App Store upload validation requires all four orientations unless you opt out of multitasking.
**Fix:** Either remove iPad from Runner → General → Supported Destinations, or add:
```xml
<key>UIRequiresFullScreen</key>
<true/>
```

---

## 🟡 Medium — performance, robustness, maintainability

### 15. Recommendations refetch on every rebuild and spin forever on error
**Where:** `lib/features/cart/view/cart_page.dart:29-35` (Both)
**Problem:** `future: _recommendations()` creates a new request on every build, so every cart change triggers another network call. On error, `snap.hasData` is never true, so the spinner never stops. `r['name']` also crashes if the API sends a null.
**Fix:** Load recommendations in a `RecommendationsCubit` (or in `initState` of a `StatefulWidget`), and handle `snap.hasError`:
```dart
if (snap.hasError) return const Text('Could not load recommendations');
if (!snap.hasData) return const CircularProgressIndicator.adaptive();
```

### 16. Cart list is a non-scrolling `Column`, so it overflows with many items
**Where:** `lib/features/cart/view/cart_page.dart:25-27` (Both)
**Problem:** Five or six items plus recommendations overflow the screen (yellow/black stripes, and items you can't reach).
**Fix:** Use a `ListView.builder` for the items inside `Expanded`, and keep the total and the Checkout button in a fixed bottom area (`bottomNavigationBar` or a `SafeArea` at the bottom).

### 17. `BlocProvider.value` used to create the cubit
**Where:** `lib/main.dart:18-19` (Both)
**Problem:** `.value` never closes the cubit, and a new `CartCubit` is created whenever `ShopApp` rebuilds, which loses the cart.
**Fix:**
```dart
return BlocProvider(
  create: (_) => CartCubit(),
  child: MaterialApp(...),
);
```

### 18. Lints are not actually running
**Where:** project root (no `analysis_options.yaml`)
**Problem:** `flutter_lints` is in `pubspec.yaml`, but without the config file `flutter analyze` reports "No issues found". With it turned on, the analyzer finds 12 issues, including the async-context bug from #9.
**Fix:** Create `analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
```
Then run `flutter analyze` and `dart format lib` (3 files need formatting).

### 19. No crash reporting
**Where:** `lib/main.dart:9-11` (Both)
**Problem:** After launch, you won't find out about crashes like #7 or #9 unless users write in.
**Fix:** Add Firebase Crashlytics or Sentry, then hook up `FlutterError.onError` and `PlatformDispatcher.instance.onError` in `main()`. Upload the `--split-debug-info` symbols with each release.

### 20. No tests
**Where:** no `test/` folder
**Problem:** The cart bug in #11 would have been caught by a three-line test.
**Fix:** `flutter pub add dev:bloc_test`, then:
```dart
blocTest<CartCubit, CartState>(
  'add puts the product in the cart',
  build: CartCubit.new,
  act: (c) => c.add(Product('1', 'Tea', 50)),
  expect: () => [isA<CartState>().having((s) => s.items.length, 'items', 1)],
);
```

### 21. Login button is a raw `GestureDetector` + `Container`
**Where:** `lib/features/auth/login_page.dart:41-49` (Both)
**Problem:** It is 36 dp tall (the minimum tap target is 48 dp), has no ripple or pressed feedback, and screen readers don't announce it as a button. The `CircularProgressIndicator` also doesn't fit in 36 dp.
**Fix:**
```dart
SizedBox(
  height: 48,
  width: double.infinity,
  child: FilledButton(
    onPressed: loading ? null : _login,
    child: loading
        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
        : const Text('Login'),
  ),
),
```
Also add `keyboardType: TextInputType.emailAddress` and `autofillHints` to the text fields, so password managers work on both platforms.

---

## 🟢 Low — polish

- **App name under the icon is `shop_app`.** In `AndroidManifest.xml:4`, set `android:label="Shop App"` to match iOS `CFBundleDisplayName`.
- **Launcher icon and splash (verify).** Both are most likely the default Flutter logo. Use `flutter_launcher_icons` and `flutter_native_splash`. The iOS 1024 px icon must have no alpha channel.
- **`ITSAppUsesNonExemptEncryption`.** Add `<key>ITSAppUsesNonExemptEncryption</key><false/>` to `Info.plist` (HTTPS only counts as exempt) so App Store Connect stops asking about export compliance on every upload.
- **`debugShowCheckedModeBanner: true`** (`main.dart:21`). The banner never shows in release builds, but set it to `false` so screenshots taken in debug look clean.
- **Hard-coded `TextStyle(color: Colors.black)`** (`cart_page.dart:28`). The total becomes invisible in dark mode. Use `Theme.of(context).textTheme.titleMedium`.
- **Profile pulse uses `Opacity` inside `AnimatedBuilder`** (`profile_page.dart:31-34`). Use `FadeTransition(opacity: Tween(begin: .5, end: 1.0).animate(_pulse))` instead, which is cheaper. `ProfilePage` also isn't reachable from any screen yet.
- **R8 shrinking.** Add `minifyEnabled true` / `shrinkResources true` to the release build type for a smaller download.
- **Version.** `1.0.0+1` is fine for the first upload. Bump the `+N` build number for every later upload to either store.

---

## Store listing items (can't check from code)
- **Privacy policy URL:** required by both stores, especially since you collect email and use the camera.
- **Account deletion:** if users can create accounts (even on your website), both stores require a way to delete the account from inside the app.
- **Demo login for App Review:** Apple will reject the app if reviewers can't get past the login screen.
- **Play Data safety form and App Store privacy label:** both must match what you actually collect.
- **Testing period:** a new *personal* Play developer account must run a closed test with testers for 14 days before production. Check whether this applies to you, because it alone can rule out "next week" on Android.
- **Listing assets:** screenshots for each required device size, plus the content rating questionnaire.

## What's good
- The feature-first `lib/features/<feature>/{cubit,view}` layout is clean and will scale well.
- The cart logic already lives in a Cubit and is read with `context.read` in callbacks, which is the right pattern. It only needs immutable state.
- The password field uses `obscureText`, and `ProfilePage` already uses `const` constructors and `SingleTickerProviderStateMixin` correctly.
- The Android `MainActivity` correctly declares `android:exported="true"`, and dependencies are recent and resolve cleanly on Flutter 3.44.

## Next steps
1. **Today:** rotate the `DEMO_SECRET_KEY…` key and move that call to your server (#1). Switch the API to HTTPS and remove the cleartext exceptions (#6).
2. Fix the store blockers: add the INTERNET permission (#2), set the real application/bundle ID (#3), create the upload keystore and signing config (#4), add the iOS camera string (#5), and set `targetSdk` (#8).
3. Fix the crash bugs: checkout navigation (#7), login error handling and secure storage (#9, #10), the cart emit (#11), and profile dispose (#12).
4. Add `analysis_options.yaml`, the privacy manifest, icons and the app name, then run `flutter analyze` and `flutter test`. Build with `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols` and `flutter build ipa --release --obfuscate --split-debug-info=build/symbols`.
5. Install the **release** builds on a real Android phone and a real iPhone (`flutter run --release`, or internal testing / TestFlight). Most of the issues above only show up there.
