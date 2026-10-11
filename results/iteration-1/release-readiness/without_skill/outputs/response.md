# Is shop_app ready for the Play Store and App Store?

**No, not yet.** I found 7 problems that will block the upload or get the app rejected, plus one security problem you should deal with **today**, before next week. Several core flows (login errors, cart updates, checkout) are also broken and App Review will notice. Most fixes are small. The slow parts are signing setup, store paperwork, and possibly Google's tester requirement (see section 4). If you start now, next week is possible.

I read every file in the project (`pubspec.yaml`, `lib/**`, `AndroidManifest.xml`, `android/app/build.gradle`, `ios/Runner/Info.plist`). The project is missing most of the platform scaffolding (no `settings.gradle`, `MainActivity`, `Runner.xcodeproj`, launcher icons or tests), so I couldn't run `flutter build`. Everything below comes from reading the code.

---

## 0. Do this today: a live secret key is in the app

`lib/main.dart:6`
```dart
const apiKey = 'DEMO_SECRET_KEY_NOT_REAL_123456';
```
This looks like a **live Stripe-style secret key**. `cart_page.dart:12` also sends it in a URL query string (`?key=$apiKey`), over plain HTTP. Anything compiled into an app can be pulled out of the APK/IPA in minutes, and query strings end up in server and proxy logs.

- **Rotate/revoke this key now** in the provider's dashboard. If it has been in git, treat it as already leaked.
- Remove it from the client completely. Only your backend should hold secret keys. The app calls your backend with the user's auth token, and the backend calls the third-party API.
- Public/publishable keys can go in the app, but pass them with `--dart-define`, never in source.

---

## 1. Problems that block the upload or cause rejection

| # | Store | Problem | Where | Fix |
|---|---|---|---|---|
| 1 | Play | **Release build is signed with the debug key.** Play Console rejects debug-signed bundles. | `android/app/build.gradle:21` `signingConfig signingConfigs.debug` | Create an upload keystore. Add a `signingConfigs { release { ... } }` block that reads `key.properties` (keep that file out of git) and use it in `release`. Turn on Play App Signing. |
| 2 | Play | **Package name is `com.example.shop_app`.** Play does not accept the `com.example` prefix, and you can never change the package name after the first upload. | `build.gradle:8,13` | Choose a permanent ID, e.g. `in.myshop.app`. Change both `namespace` and `applicationId`, and move `MainActivity` to the matching package. |
| 3 | Play | **`targetSdk 33` is too old.** New apps must target at least API 35 (Android 15), and the August-2026 deadline has likely raised this to API 36. Check the current requirement in Play Console. | `build.gradle:14` | Use `targetSdk flutter.targetSdkVersion` on a current Flutter, or set it explicitly. Re-test afterwards: Android 15+ forces edge-to-edge, so check that content isn't hidden under the status and navigation bars. |
| 4 | iOS | **`NSCameraUsageDescription` is missing.** `ProfilePage` opens the camera through `image_picker`. iOS kills the app the moment the camera is requested, and App Store Connect flags the missing purpose string. | `ios/Runner/Info.plist` | Add `<key>NSCameraUsageDescription</key><string>Used to take a profile photo.</string>`. If you add a gallery option later, also add `NSPhotoLibraryUsageDescription`. |
| 5 | iOS | **App Transport Security is turned off everywhere** (`NSAllowsArbitraryLoads = true`). Apple asks you to justify this, and here the reason is just a plain-HTTP API. | `Info.plist:13-17` | Move the API to HTTPS (see #6) and delete the whole `NSAppTransportSecurity` block. |
| 6 | Both | **Passwords and tokens travel over plain HTTP.** `baseUrl = 'http://api.myshop.in/v1'`, and the Android manifest allows cleartext. Anyone on the same Wi-Fi can read login credentials. This is a security rejection on iOS and a Play Data-safety violation (you can't say data is encrypted in transit). | `main.dart:7`, `AndroidManifest.xml:6` | Serve the API over HTTPS, change the URL to `https://`, and remove `android:usesCleartextTraffic="true"`. |
| 7 | iOS | **Portrait-only orientation fails iPad validation.** Flutter builds for iPhone and iPad by default (`TARGETED_DEVICE_FAMILY = 1,2`). An app that supports iPad multitasking must declare all 4 orientations, otherwise upload fails with ITMS-90474. | `Info.plist:18-21` | Pick one: (a) add `UIRequiresFullScreen = true`, (b) add `UISupportedInterfaceOrientations~ipad` with all four orientations, or (c) make the app iPhone-only in Xcode. |
| 8 | iOS | **`Info.plist` looks incomplete.** `UILaunchStoryboardName`, `CFBundleExecutable`, `CFBundlePackageType`, `CFBundleName` and `LSRequiresIPhoneOS` are missing. Without a launch storyboard the upload is rejected. | `Info.plist` | Restore the keys from a fresh `flutter create` template, keeping your own values. |

---

## 2. Bugs App Review will hit (rejection under Guideline 2.1, "App Completeness")

Reviewers will log in, add something to the cart and tap Checkout. Right now each of those steps can fail:

1. **Login crashes or hangs on any error** (`login_page.dart:18-28`).
   - It never checks `res.statusCode`, and there's no `try/catch`. A wrong password, a network error or a non-JSON response throws.
   - `data['token']` can be null, and `setString` needs a non-null String, so this crashes.
   - If anything throws, `loading` stays `true` and the spinner never stops.
   - `Navigator` is used after an `await` without checking `if (!mounted) return;`.
   - Fix: wrap the call in try/catch/finally, check the status code, show an error `SnackBar`, and check `mounted` before navigating.
2. **Adding to the cart never updates the screen** (`cart_cubit.dart:20-23`). The code changes the current state's list and then calls `emit(state)` with that same object. Bloc skips an emit when the new state equals the current one, so `BlocBuilder` never rebuilds. Fix: `emit(CartState(items: [...state.items, p]))`, and make the fields `final` (`checkoutDone` currently isn't).
3. **Checkout breaks navigation** (`cart_page.dart:22-24`).
   - `Navigator.pop()` runs inside `build()`. That's a side effect during build, which throws a "setState/markNeedsBuild called during build" error.
   - `CartPage` was opened with `pushReplacement`, so it is the only route. Popping it leaves a **black screen**.
   - Fix: move this to a `BlocListener` and navigate to a confirmation screen.
4. **Checkout doesn't do anything** (`cart_cubit.dart:25-28`). It waits 2 seconds and clears the cart. Apple and Google both reject placeholder features.
   - Either build a real order/payment flow or hide the button.
   - Payment rule: physical goods may use Stripe/Razorpay etc. **Digital goods or content must use Apple In-App Purchase and Google Play Billing.**
5. **The recommendations request runs again on every rebuild** (`cart_page.dart:29-30`). `_recommendations()` is called inside `build`, so each rebuild sends a new request. Errors are never handled, so on failure the spinner spins forever. Also, `r['name']` can be null and crash `Text`. Fix: make the page a `StatefulWidget`, create the future once in `initState`, and handle `snap.hasError`.
6. **A new `CartCubit` is created on every rebuild and never closed** (`main.dart:18-19`). `BlocProvider.value(value: CartCubit())` is the wrong API here. Use `BlocProvider(create: (_) => CartCubit(), ...)`.
7. **`ProfilePage` never disposes its `AnimationController`** (`profile_page.dart:18`). Add `dispose()` that calls `_pulse.dispose()`. Also, nothing in the app navigates to `ProfilePage`, so either link to it or remove it (along with the camera permissions).
8. **Android camera permission conflict** (`AndroidManifest.xml:2`). `image_picker` opens the system camera app and does not need `CAMERA`. Because the app *declares* `CAMERA` but never requests it at runtime, Android throws a `SecurityException` when the camera opens. Remove the `<uses-permission android:name="android.permission.CAMERA"/>` line, unless you plan to request the permission at runtime.

---

## 3. Security and privacy fixes (expected by store policies)

- **Remove `print('login response: $data')`** (`login_page.dart:23`). It writes the auth token to the device log, and `print` still runs in release builds. Use `debugPrint` inside `if (kDebugMode)`, or a logger.
- **Store the auth token in secure storage.** It's currently in `SharedPreferences`, which is plain text. Use `flutter_secure_storage` (Keychain / Keystore).
- **Privacy policy URL.** Both stores require one, because the app collects email, password and photos.
- **Play "Data safety" form and Apple "App Privacy" labels.** Declare the email, auth token and photos (if uploaded).
- **Apple privacy manifest (`PrivacyInfo.xcprivacy`).** `shared_preferences` uses UserDefaults, which is a "required-reason" API. Recent plugin versions ship their own manifest. Run `flutter pub upgrade` and add an app-level `PrivacyInfo.xcprivacy` in Runner.
- **Account deletion.** If users can *create* accounts in the app or on your site, Apple (5.1.1(v)) requires in-app account deletion, and Google requires a deletion option in the app plus a web URL in Play Console.
- **Demo account for reviewers.** The app opens on a login screen, so you must give App Review (and Play's "App access" section) working test credentials, or the app gets rejected straight away.

---

## 4. Store and account items that take time

- **Google Play, new personal developer account:** if your account was created after Nov 2023, Google requires a **closed test with at least 12 testers opted in for 14 continuous days** before you can apply for production. That alone makes "next week" impossible for a Play **production** release. Upload to closed testing now. Organization accounts don't have this requirement.
- **Upload format:** Play needs an `.aab` (`flutter build appbundle --release`). iOS goes through `flutter build ipa` and then Transporter or Xcode.
- **Xcode/SDK:** Apple requires uploads built with a recent Xcode/iOS SDK. Update Xcode and Flutter before you build.
- **iOS signing:** register the Bundle ID in the Apple Developer portal, set the Team and Bundle Identifier in Xcode (still a default `com.example`-style ID until you change it), and create the App Store Connect record.
- **Branding:**
  - The Android label is `shop_app` (with an underscore). Change `android:label` to `Shop App` to match iOS.
  - Replace the default Flutter launcher icons, for example with `flutter_launcher_icons`.
  - Play also needs a 512x512 icon, a 1024x500 feature graphic and screenshots. App Store Connect needs a 1024x1024 icon and 6.9" iPhone screenshots (plus iPad screenshots if you support iPad).
- **Content rating questionnaire, target audience and ads declaration** in Play Console. **Age rating and export compliance** in App Store Connect. If you only use HTTPS, add `ITSAppUsesNonExemptEncryption = false` to `Info.plist` to skip the export-compliance prompt on every build.
- **Version:** `1.0.0+1` is fine for the first upload. Increase the `+N` build number for every later upload.

---

## 5. Polish (won't block release)

- `debugShowCheckedModeBanner: true` (`main.dart:21`). The banner never appears in release builds, but set it to `false` anyway.
- The login button is a `GestureDetector` around a `Container`: it gives no tap feedback, has no accessibility semantics and is only 36 px high (below the 48 dp minimum). Use `FilledButton`.
- Add `keyboardType: TextInputType.emailAddress`, `autofillHints` and some validation to the login fields. Dispose the `TextEditingController`s.
- Money is stored as `double`. Use integer paise or a decimal type, and format with `NumberFormat.currency(locale: 'en_IN', symbol: '₹')`.
- `TextStyle(color: Colors.black)` will disappear if you add dark mode later. Use theme colors.
- There are no tests. Add at least a widget test for login → cart → checkout. Running `flutter analyze` will also flag the missing `const`/`key` parameters.

---

## Suggested order for this week

1. **Today:** rotate the leaked key and remove it from the app. Put the API on HTTPS.
2. Change the package/bundle ID, set up release signing, raise `targetSdk`, fix `Info.plist` (camera string, ATS, iPad orientations, missing keys), and remove the Android `CAMERA` permission.
3. Fix login error handling, cart `emit`, checkout navigation, the recommendations future, cubit creation and the controller disposals.
4. Decide on checkout: build a real payment flow or hide it.
5. Write the privacy policy, fill in Data safety / App Privacy, create the reviewer demo account and prepare icons and screenshots.
6. Upload to **Play closed testing** and **TestFlight** first. Go to production when the testing requirements are met.
