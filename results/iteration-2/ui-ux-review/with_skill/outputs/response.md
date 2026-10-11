The worst problem is checkout. It throws an error and then leaves the user on an empty screen. Login gets stuck on a spinner forever on any server error, and the cart page can't scroll. Overall shop_app doesn't feel native yet. The fixes are small and local, and I didn't change any app code.

I ran a stress-test widget test with 97 cases: **61 passed, 36 failed**. Every test checks what a user would expect, so each red test is a real break. I ran it with Flutter 3.44.4 on a scratch copy of the project, so no build folders were left in your project. Your project has no `analysis_options.yaml`, so `flutter analyze` says "No issues found". With `flutter_lints` it reports 12 issues.

**The worst breaks (all confirmed by failing tests)**
1. **Checkout ends badly.** `Navigator.pop()` runs inside the cart's `BlocBuilder.builder` and throws `setState() or markNeedsBuild() called during build`. Cart is the only screen left after login, so the pop leaves the user with nothing (black screen on iOS, app closes on Android) and no order confirmation. **Fix:** navigate from a `BlocListener` with `listenWhen` to an order-success screen.
2. **Login gets stuck.** Any non-200 response throws an unhandled `FormatException`. The spinner never stops and the Login button never comes back. An empty form is also sent straight to the API. **Fix:** `try/catch/finally`, an inline error message, `mounted` checks and form validation.
3. **The cart overflows.** It's a `Column` that can't scroll. Ten realistic items overflow by 276 px on a 375 pt phone, and even a 430 pt Pro Max overflows. Checkout ends up off-screen. **Fix:** `ListView.builder` with a total/checkout bar pinned to the bottom.
4. **Added items never show up.** `CartCubit.add` changes the same list and re-emits the same state, which Bloc ignores, so the screen doesn't refresh.
5. **Checkout can be tapped twice.** The button stays enabled during the 2 s checkout, so each extra tap starts another order.
6. **Recommendations spin forever.** If that request fails, the spinner never goes away.
7. **Prices look wrong.** You get "₹499.0", "₹0.30000000000000004" and "₹12345678.9" (no grouping). **Fix:** `NumberFormat.currency(locale: 'en_IN', symbol: '₹')` with tabular figures.
8. **The empty cart is a dead end.** Nothing in the app calls `add()`, so every user lands on a cart showing "Total: ₹0.0" with Checkout still enabled.

**What makes it feel non-native**
- **Login button:** a bare `GestureDetector` box with no press feedback, no ripple, no button semantics for screen readers, and only 36 dp tall (the minimum is 48). The label switches to the spinner instantly instead of a quick crossfade. **Fix:** a 48 dp `FilledButton` (or `PressableScale` at 0.97) with an `AnimatedSwitcher` (150 ms, `Cubic(0.23, 1, 0.32, 1)`) into a 20 px `CircularProgressIndicator.adaptive()`.
- **Login fields:** no email keyboard, no autofill hints for the password manager, and Return doesn't submit.
- **Profile avatar:** it pulses forever, using an `Opacity` widget that redraws every frame, and its animation controller is never disposed. Delete the pulse. There's also no `NSCameraUsageDescription` in `Info.plist`, so iOS will kill the app the first time it opens the camera. Profile isn't reachable from any screen yet, so neither has bitten anyone so far.
- **General:** no theme (hard-coded `Colors.*`), no navigation shell (no way to reach Profile or log out), and spinners that aren't `.adaptive()`. Copying the skill's `motion_kit.dart` into `lib/core/motion/` gives you one shared set of curves, durations and `PressableScale`.

**What held up:** the login layout survived every size at 2× text with the keyboard open. Cart rows handled Devanagari, Arabic, emoji and very long titles without spilling sideways. The login double-tap guard works. Default page transitions keep iOS swipe-back.

I also noticed some issues outside UI/UX, listed at the end of `UI_UX_REVIEW.md`:
- The API key is sent in a URL over plain `http://`.
- The login token is stored in `SharedPreferences` and printed to the log.
- The `CartCubit` passed to `BlocProvider.value` is never closed.
- The text controllers on the login screen are never disposed.

Say "fix all" or "fix 1, 3" and I'll apply them, then re-run the stress test until it passes.

Files are in `outputs/shop_app/`:
- `UI_UX_REVIEW.md`
- `STRESS_TEST.md`
- `test/stress_test.dart` (run it with `flutter test test/stress_test.dart`)

## Skill feedback

- **Which report file:** SKILL.md picks one report file per mode, but this request was both a UI/UX review and a stress test. It doesn't say whether to write one combined report or two. I wrote both, `UI_UX_REVIEW.md` and `STRESS_TEST.md`.
- **The stress-test harness can't test the keyboard:** the template in `stress-test.md` wraps `home:` in a fresh `MediaQueryData(size:, textScaler:)`. That throws away the view's insets, so `tester.view.viewInsets` (keyboard open) has no effect. `MediaQuery.of(context).copyWith(textScaler: …)` inside `MaterialApp.builder` works.
- **The harness can time out:** the template calls `pumpAndSettle()`, which times out on any screen with a spinner that never stops or a repeating animation (this app has both). It should say to fall back to `pump(Duration)`.
- **Network calls in tests:** nothing mentions that `flutter_test` answers every HTTP request with a 400 and an empty body. That's useful to know for screens that fetch in `build`/`initState`, and it's a free "API error" case.
- **A Bloc trap that hides bugs:** the first `emit` of the same state object still goes through, because Bloc hasn't emitted anything yet at that point. So seeding fixtures through a mutating `add()` before pumping hides the "UI doesn't update" bug. A one-line warning in `stress-test.md` or `review.md` would help.
- **What tests should check:** it doesn't say whether harness tests should assert correct behaviour (fail until fixed) or only catch overflows. I chose correct behaviour.
- **Page transitions:** `ui-ux-review.md` says to set `pageTransitionsTheme`, but Flutter's defaults already use the Cupertino transition (with swipe-back) on iOS. As written, it could lead a reviewer to flag a correct default `MaterialApp`.
- **Non-UI findings:** there's no guidance on where to put security or architecture issues spotted during a UI/UX-only review. I added a short "Outside UI/UX scope" section.
- **`flutter_scan.sh` false positive:** the "context after await" check flagged `cart_page.dart`, but that file has no `await` before a `context` use. Its real problem is navigating inside `build`, which the scan doesn't look for. Consider adding a "`Navigator.` inside a `builder:`" check.
