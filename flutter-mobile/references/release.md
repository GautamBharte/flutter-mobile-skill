# Release mode (Play Store + App Store)

Goal: catch everything that would get the build rejected, crash on real devices, or embarrass the user on launch day. Check each item against the actual files; report only what's wrong or unverifiable, plus a final verdict.

Store policies change yearly. When a requirement depends on a current deadline (target SDK level, Xcode/iOS SDK version, privacy rules), state the value you'd expect and tell the user to confirm it against the current Play Console / App Store Connect notice — don't present a remembered number as certain.

## App identity (both)

- `pubspec.yaml` `version: 1.2.0+5` — name and build number. Build number must increase for every upload to each store.
- Package name / bundle ID is not `com.example.*` (Play rejects it; it's also permanent once published). Check `applicationId` in `android/app/build.gradle(.kts)` and `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj`.
- App display name: `android:label` in AndroidManifest, `CFBundleDisplayName` in Info.plist.
- Launcher icons and splash: not the default Flutter logo (`flutter_launcher_icons`, `flutter_native_splash`). iOS icon must have no alpha channel.

## Android

`android/app/build.gradle(.kts)`:
- `targetSdk` meets Google Play's current requirement (recent years: one level below the newest Android release, updated each August). `minSdk` reasonable for the audience.
- Release `signingConfig` uses an upload keystore loaded from `key.properties` — **not** `signingConfigs.debug` (the default template does this!). `key.properties` and `*.jks` must be in `.gitignore`.
- `isMinifyEnabled` / `isShrinkResources` for release, with ProGuard/R8 keep rules if using reflection-based plugins.
- Build as App Bundle: `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols` (keep the symbols to de-obfuscate crash reports).

`AndroidManifest.xml` (main, not debug/profile):
- `<uses-permission android:name="android.permission.INTERNET"/>` present if the app uses the network — Flutter adds it only to debug/profile manifests, so release builds silently have no network. Classic launch-day bug.
- Only permissions actually needed; each sensitive one (location, camera, contacts, SMS, `QUERY_ALL_PACKAGES`, background location) needs a Play Console declaration.
- Android 13+: `POST_NOTIFICATIONS` declared *and* requested at runtime if sending notifications.
- `android:exported` set on activities/services/receivers with intent-filters (required since Android 12).
- No `android:usesCleartextTraffic="true"` unless justified.
- Deep links: `autoVerify` + `assetlinks.json` if using App Links.

## iOS

`ios/Runner/Info.plist`:
- A usage-description string for **every** permission the app or its plugins request: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSMicrophoneUsageDescription`, `NSContactsUsageDescription`, `NSFaceIDUsageDescription`, `NSUserTrackingUsageDescription`… Missing one = instant crash when requested + App Review rejection. Strings must explain *why*, not "Needs camera".
- No `NSAllowsArbitraryLoads = true` without justification.
- `ITSAppUsesNonExemptEncryption` set (usually `false`) to skip the export-compliance question each upload.
- Supported orientations match the app's design (iPad requires all four unless `UIRequiresFullScreen`).

Other iOS:
- `PrivacyInfo.xcprivacy` privacy manifest present, declaring required-reason APIs (e.g. UserDefaults via shared_preferences, file timestamps) and collected data. Plugins ship their own, but the app needs one too.
- `ios/Podfile` `platform :ios, 'X'` matches the deployment target in Xcode; plugins may require a minimum.
- Sign in with Apple is required if the app offers other third-party social logins (Google/Facebook) — App Review guideline 4.8.
- If the app has account creation, it must offer in-app account deletion (both stores require this).
- Build: `flutter build ipa --release --obfuscate --split-debug-info=build/symbols`.

## Dart code checks for release

- No `debugShowCheckedModeBanner: true`, no test/staging API URLs hard-coded (use `--dart-define-from-file=env/prod.json` or flavors).
- No `print` of tokens/PII; use `debugPrint` or a logger that is silent in release (`kReleaseMode`).
- Crash reporting wired up (Firebase Crashlytics / Sentry) with `FlutterError.onError` and `PlatformDispatcher.instance.onError`, and symbols uploaded.
- Analytics/ads/tracking: iOS ATT prompt before tracking; Play Data safety form and App Store privacy "nutrition label" match what the SDKs actually collect.
- `flutter analyze` clean; `flutter test` passes.

## Store listing reminders (mention briefly, can't verify from code)

Privacy policy URL (required by both), screenshots for required device sizes, content rating questionnaire, Play closed-testing requirement for new personal developer accounts, demo account credentials for App Review if login is required.

## Verdict

End the Summary with one of: ✅ Ready, ⚠️ Ready after fixes (list the blockers), ❌ Not ready. Anything that causes a rejection or a crash on launch is a blocker.
