# shop_app — UI/UX Review Report

## Summary

shop_app is a three-screen prototype (Login → Cart, plus an unreachable Profile) and it doesn't feel native yet. Buttons give no feedback, the async flows have no error states, and the cart can't scroll. **Fix first: finishing checkout.** It calls `Navigator.pop()` inside `build`, which throws `setState() or markNeedsBuild() called during build` (seen in the widget test). Because Cart is the only route left after login, that pop leaves the user with nothing. Close behind: login gets stuck on a spinner forever on any server error, and the cart overflows once it holds about 10 items on a 375 pt phone. Verdict: ⚠️ needs a round of fixes before it feels like a real store app. Most fixes are small and local.

How this was checked: I read all of `lib/` and ran `flutter analyze` (Flutter 3.44.4) with the repo's settings and again with `flutter_lints`. I also ran a 97-case worst-case widget harness (`test/stress_test.dart`, results in `STRESS_TEST.md`). Findings marked **(verified)** failed in that harness. The rest come from reading the code. Motion "feel" can't be judged from code alone, so I added feel-check steps where they apply.

Product personality: a utility shopping app. It should feel **crisp and calm**: fast ease-out, no bounce, and delight saved for the order-success moment.

---

## 🔴 Critical

| Before | After | Why |
| --- | --- | --- |
| Checkout completion does `Navigator.of(context).pop()` **inside `BlocBuilder.builder`** (`lib/features/cart/view/cart_page.dart:22-24`) **(verified: throws `setState() or markNeedsBuild() called during build`)** | Move navigation into a `BlocListener`/`BlocConsumer.listener` with `listenWhen: (p, c) => !p.checkoutDone && c.checkoutDone`, and `pushReplacement` to an order-success screen (snippet below) | `build` can run many times per state, and navigating there throws. Cart is also the **root route**: Login used `pushReplacement` (`login_page.dart:27`), so popping it leaves an empty navigator (black screen on iOS, app closes on Android). The user pays and gets no confirmation (Both). |
| Login has no `try/catch` and never resets `loading` (`lib/features/auth/login_page.dart:18-28`) **(verified: `FormatException: Unexpected end of input` on an HTTP 400, spinner never goes away, the Login button never comes back)** | `try / catch / finally`, check `res.statusCode`, null-check the token, `if (!mounted) return;` before `setState`/`Navigator`, and show an inline error (snippet below) | Wrong password, server down, captive Wi-Fi or a timeout all leave the user on an endless spinner, and the only escape is killing the app. That's the worst first impression possible, on the very first screen. |
| Cart body is a non-scrolling `Column` (`lib/features/cart/view/cart_page.dart:25-40`) **(verified: overflows by 276 px with 10 items at 375×812, 640 px at 320 w and 3,936 px at 2× text; even a 430 pt Pro Max overflows)** | `ListView.builder` in an `Expanded`, with a pinned bottom bar (total + Checkout) in a `SafeArea` (snippet below) | Items past the fold, **and the Checkout button**, can't be reached. Yellow/black overflow stripes show in debug; in release the content is just cut off. |

```dart
// cart_page.dart — navigation in a listener, scrollable list, pinned checkout bar
body: BlocConsumer<CartCubit, CartState>(
  listenWhen: (prev, curr) => !prev.checkoutDone && curr.checkoutDone,
  listener: (context, state) {
    HapticFeedback.lightImpact(); // same frame as the transition starts
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OrderSuccessPage()),
    );
  },
  builder: (context, state) {
    if (state.items.isEmpty) return const _EmptyCart();
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: state.items.length,
            itemBuilder: (context, i) {
              final p = state.items[i];
              return ListTile(
                title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(rupees.format(p.price), style: tabular),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text('Total ${rupees.format(state.total)}',
                      style: Theme.of(context).textTheme.titleMedium?.merge(tabular)),
                ),
                FilledButton(
                  onPressed: state.isCheckingOut ? null : () => context.read<CartCubit>().checkout(),
                  child: const Text('Place order'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  },
),
```

```dart
// login_page.dart — never strand the user
Future<void> _login() async {
  if (!(_formKey.currentState?.validate() ?? false)) return;
  setState(() { loading = true; error = null; });
  try {
    final res = await http
        .post(Uri.parse('$baseUrl/login'), body: {'email': email.text.trim(), 'password': password.text})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw const FormatException('status');
    final token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
    if (token == null) throw const FormatException('token');
    // ...store token (see "Outside UI/UX scope")
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CartPage()));
  } catch (_) {
    if (!mounted) return;
    setState(() => error = "Couldn't sign in. Check your email and password, then try again.");
  } finally {
    if (mounted) setState(() => loading = false);
  }
}
```

(Longer term, move this into an `AuthCubit`. The project already uses flutter_bloc, and that keeps the widget dumb and testable.)

## 🟠 High

| Before | After | Why |
| --- | --- | --- |
| Login "button" is a bare `GestureDetector` + `Container(height: 36, color: Colors.blue)` (`login_page.dart:41-49`) **(verified: 36 dp tall)** | `FilledButton` with `minimumSize: Size.fromHeight(48)`, or keep the custom look and wrap it in `PressableScale(scale: 0.97)` from `assets/motion_kit.dart` | No ripple, no pressed state, no button semantics for VoiceOver/TalkBack, no focus/keyboard activation, and a 36 dp target (minimum is 48). It doesn't feel like it heard the tap. It's the app's primary action, so everyone notices. |
| Label → spinner swap teleports, and the Material spinner fills the 36 px bar in the theme's primary purple on blue (`login_page.dart:47`) | `AnimatedSwitcher(duration: 150 ms, switchInCurve: Cubic(0.23, 1, 0.32, 1))` between `Text('Log in', key: ValueKey('label'))` and `SizedBox.square(key: ValueKey('spin'), dimension: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2))`. Set `disabledBackgroundColor: cs.primary, disabledForegroundColor: cs.onPrimary` so the button doesn't flash grey while loading | State indication should be a quick crossfade, not a jump. A 20 px adaptive spinner is native on iOS and readable on the fill. Without distinct keys, `AnimatedSwitcher` doesn't animate at all. |
| Checkout button stays enabled during the 2 s `await` (`cart_page.dart:36-39`, `cart_cubit.dart:25-28`) **(verified: `onPressed` still non-null 100 ms after tap)** | Add `isCheckingOut` to `CartState`; emit it before the await; button shows the same 20 px adaptive spinner and `onPressed: null` | Every extra tap starts another checkout (duplicate orders), and there's no sign anything is happening for 2 s. That's long enough for users to tap again. |
| Items added while the cart is open never appear: `state.items.add(p); emit(state);` (`cart_cubit.dart:20-23`) **(verified)** | `emit(CartState(items: [...state.items, p]))`, make `CartState` immutable (`final` fields, `List.unmodifiable`, `Equatable`) | Bloc drops an emit of the same instance, so the UI never rebuilds. To the user, "Add to cart" does nothing. |
| Profile avatar pulses forever: `AnimationController(1 s)..repeat(reverse: true)` driving an `Opacity` widget (`lib/features/profile/profile_page.dart:18, 31-39`); controller never disposed | **Delete the pulse** (remedy #1). If you want to hint "tap to add photo", use a static camera badge on the avatar plus `InkWell`/`PressableScale`. If you keep any motion: `FadeTransition`, `RepaintBoundary`, honour `MediaQuery.disableAnimationsOf`, and `dispose()` the controller | A purposeless endless loop on a static element. The `Opacity` widget repaints through `saveLayer` every frame (battery), a slow ~1 Hz oscillation is a known motion-sensitivity trigger, and the undisposed ticker throws `Ticker was active when disposed`. (The page isn't reachable yet, so fix it before you wire it up.) |
| Camera opened with no `NSCameraUsageDescription` in `ios/Runner/Info.plist` (`profile_page.dart:22`) | Add the key with a human reason ("Take a profile photo"). Better: offer Camera / Photo library in a `CupertinoActionSheet` / `showModalBottomSheet` and ask permission in context | iOS kills the app on first camera access without it (latent: Profile isn't navigable yet). Jumping straight into the camera with no choice also isn't how native apps do avatars. |

Feel-check after fixing: run `timeDilation = 5.0` (or DevTools → Slow Animations) and press and hold the Login and Checkout buttons. The scale or ripple should start on finger-down, and the label → spinner crossfade should show one clean change, not two overlapping states.

## 🟡 Medium

| Before | After | Why |
| --- | --- | --- |
| Recommendations: `FutureBuilder(future: _recommendations())` created inside `build` (`cart_page.dart:29-34`) **(verified: spinner still showing after 5 s on an API error)** | Fetch once in the cubit (or a `RecommendationsCubit`); loading = a skeleton the same height as the final rows; error = hide the section (it's optional) | Every rebuild refetches, so the spinner flashes and the layout jumps. On error the user sees an endless spinner. A non-200 body also throws in `jsonDecode`, and `r['name']` on a missing field throws. |
| Prices rendered with raw `double.toString()`: `'₹${p.price}'` / `'Total: ₹${state.total}'` (`cart_page.dart:27-28`) **(verified: "₹499.0", "₹0.30000000000000004", "₹12345678.9")** | `final rupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);` (add `intl`) + `TextStyle(fontFeatures: [FontFeature.tabularFigures()])`; store money as integer paise | Wrong-looking money destroys trust in a shopping app. Lakh grouping (₹1,23,45,678.90) is what Indian users expect, and tabular figures stop the total jittering as it changes. |
| Empty cart shows a bare "Total: ₹0.0" and an enabled Checkout (`cart_page.dart:25-39`) **(verified)**. Nothing in the app ever calls `CartCubit.add`, so **this is what every user sees** today | Empty state with an icon, "Your cart is empty", and a primary "Browse products" action; Checkout hidden or disabled when `items.isEmpty` | Every data screen needs an empty state with a next action. Right now the first screen after login is a dead end. |
| Wayfinding: Cart is the root after login with no way to Profile, Products, or Log out; Profile is unreachable (`main.dart:23`, `login_page.dart:27`) | Add a home shell (`NavigationBar` on Android / `CupertinoTabBar` on iOS: Shop · Cart · Profile) after login | Every screen should answer "where can I go, how do I get back". Here the user is trapped. |
| Login form: no `Form`/validators, no `keyboardType: TextInputType.emailAddress`, no `autofillHints`, no `textInputAction`/`onSubmitted`, `autocorrect` on for email (`login_page.dart:38-39`) **(verified: default keyboard, no autofill hints; an empty form goes straight to the network)** | `AutofillGroup` + `TextFormField(keyboardType: emailAddress, autofillHints: [AutofillHints.email], textInputAction: next, autocorrect: false)`; password `autofillHints: [AutofillHints.password], textInputAction: done, onFieldSubmitted: (_) => _login()`; validate on submit, then inline as the user edits | Native login screens give the `@` keyboard, Keychain/Google Password Manager autofill and Return-to-submit. Missing them is the most noticeable "this isn't a real app" moment on both platforms. |
| Spinners use `CircularProgressIndicator()` instead of `.adaptive()` (`login_page.dart:47`, `cart_page.dart:32`) | `CircularProgressIndicator.adaptive()` | Shows the iOS activity indicator on iPhone and the Material ring on Android. |
| No theme at all: hard-coded `Colors.blue`, `Colors.white`, `Colors.black` (`login_page.dart:45,47`, `cart_page.dart:28`); the Total has no hierarchy | `MaterialApp(theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: …)), darkTheme: …, themeMode: ThemeMode.system)`; colors from `colorScheme`, text from `textTheme` (`titleMedium` for the total) | Dark mode is ignored (`Colors.black` text disappears on a dark surface once you add a dark theme), and the most important number on the screen looks like body copy. |

## 🟢 Low

| Before | After | Why |
| --- | --- | --- |
| Same product added twice renders as two identical rows (`cart_page.dart:27`) | Group by `id` and show a quantity stepper (`−  2  +`) with `HapticFeedback.selectionClick()` on change | Native carts show quantity. Duplicate rows look like a bug. |
| Long titles wrap without limit in `ListTile` (inferred from the 320 w/2× overflow sizes) | `maxLines: 2, overflow: TextOverflow.ellipsis` in the list; full title on the product detail | Keeps row heights predictable while still identifying the item. |
| `debugShowCheckedModeBanner: true` (`main.dart:21`) | Remove (default is fine) | Debug-only, but it clutters screenshots and design reviews. |
| No haptics anywhere | `lightImpact()` when an item is added and when the order succeeds; `selectionClick()` on quantity changes. Never on scroll or keystrokes | Fire it in the same callback that starts the visual change, so the two feel like one event. Keep it subtle on Android. |

### Missed opportunities

1. **Order placed** is a rare, emotional moment, so it can carry a little delight: a success screen with a check mark that draws in (~400 ms, `Cubic(0.23, 1, 0.32, 1)`), the order total, and `HapticFeedback.lightImpact()` on the same frame. With reduced motion, use a plain fade.
2. **Item added to cart** currently teleports, or doesn't show up at all. Use `AnimatedList` insert with `SizeTransition` + `FadeTransition`, ~200 ms ease-out, and a tiny `AnimatedScale` bump on a cart badge.
3. **Login → Cart**: the swap via `pushReplacement` is fine. On success, keep the button showing the spinner until the route pushes, so there's no flash of the "Log in" label in between.
4. **Recommendations** pop in when the request finishes. Reserve their height with a skeleton and `Appear` them (kit) with a 40 ms stagger across the first ~4 items.

Recommendation: copy `assets/motion_kit.dart` from the flutter-mobile skill into `lib/core/motion/motion_kit.dart`. It provides `MotionCurves.easeOut` (`Cubic(0.23, 1, 0.32, 1)`), `MotionDurations.press` (120 ms) / `menu` (200 ms), `PressableScale` (responds on pointer-down, cancels on scroll), and `Appear`. Then every fix above uses one set of tokens instead of new ad-hoc `Duration`s.

## Outside UI/UX scope (spotted in passing, worth a full review)

- `apiKey` is sent in a query string over cleartext `http://` (`main.dart:6-7`, `cart_page.dart:12`), and `usesCleartextTraffic="true"` / `NSAllowsArbitraryLoads` are set. Switch to HTTPS and keep secrets on the server.
- The auth token is stored in `SharedPreferences` (`login_page.dart:25`): use `flutter_secure_storage`. The full login response, including the token, is `print`ed (`login_page.dart:23`).
- `BlocProvider.value(value: CartCubit())` (`main.dart:18-19`) creates a cubit that's never closed and is recreated on every `ShopApp` rebuild. Use `BlocProvider(create: (_) => CartCubit())`.
- `TextEditingController`s in Login are never disposed (`login_page.dart:14-15`).
- There's no `analysis_options.yaml`, so `flutter analyze` reports "No issues found". With `flutter_lints` it reports 12, including `use_build_context_synchronously` at `login_page.dart:27` and `avoid_print`. `dart format` would also change 3 of the 5 files in `lib/`.

## What's good

- The cubit split already exists (`CartCubit` in its own feature folder), so moving the async flows and loading flags into state is a small step, not a rewrite.
- Login guards double-submit correctly (`onTap: loading ? null : _login`, with `loading` set before the first `await`).
- `ListTile` is the right building block for cart rows: it handled the long German compound, Devanagari, Arabic and emoji titles without a horizontal overflow at any width.
- Default `MaterialApp` page transitions are left alone, so iOS keeps the Cupertino swipe-back and Android gets the platform transition. Keep it that way when you add routes (no custom `PageRouteBuilder`s).
- The login layout held up in the harness at 320 pt, at 2× text, with a 336 px keyboard open.

## Next steps

1. Move checkout navigation into a `BlocListener` and land on an order-success screen. Add `isCheckingOut` so Checkout can't be double-tapped.
2. Wrap login in `try/catch/finally` with an inline error and `mounted` checks. Swap the `GestureDetector` for a 48 dp `FilledButton` with an `AnimatedSwitcher` label → adaptive spinner.
3. Make the cart a `ListView.builder` with a pinned `SafeArea` total/checkout bar, an empty state, and `NumberFormat.currency(locale: 'en_IN')` prices.
4. Make `CartState` immutable so additions show up, and move recommendations into a cubit with skeleton and error states.
5. Delete the profile pulse, add `NSCameraUsageDescription`, add a navigation shell, and copy in `motion_kit.dart`. Then re-run `flutter test test/stress_test.dart` until it's green.
