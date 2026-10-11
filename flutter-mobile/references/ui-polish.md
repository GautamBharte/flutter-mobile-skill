# Polish mode (UI, motion, native feel)

Goal: make the app feel fast, responsive, and at home on both iOS and Android. Great apps are mostly made of many small details done right — focus on the ones users feel on every interaction.

## Principles

1. **Respond instantly.** Every tap gets feedback within ~100 ms: ink ripple / highlight, button pressed state, haptic. Network-bound actions update optimistically or show progress immediately.
2. **Motion explains, it doesn't decorate.** Animate to show where something came from or went (Hero, container transform, shared axis). Skip animations on things users do hundreds of times a day.
3. **Fast and interruptible.** Most UI transitions 150–300 ms; small elements faster, large surfaces slower. A user should be able to interrupt (drag a sheet mid-animation, tap again) without the UI fighting back — physics-based (`SpringSimulation`, `animateWith`) beats fixed curves for gesture-driven UI.
4. **Respect the platform and the user.** Honour reduced motion and text scaling, use platform-appropriate transitions and controls.

## Animation in Flutter — choose the lightest tool

| Need | Use |
|---|---|
| A property changes (size, color, padding, opacity) | Implicit: `AnimatedContainer`, `AnimatedOpacity`, `AnimatedPadding`, `AnimatedAlign`, `TweenAnimationBuilder` |
| Swap one widget for another | `AnimatedSwitcher` (give children distinct `key`s!), `AnimatedCrossFade` |
| List insert/remove | `AnimatedList` / `SliverAnimatedList` |
| Shared element between routes | `Hero`; `animations` package: `OpenContainer`, `SharedAxisTransition`, `FadeThroughTransition` |
| Repeating / choreographed / gesture-driven | Explicit `AnimationController` + `*Transition` widgets, `Interval` for staggering |
| Drag with fling / snap | `AnimationController.animateWith(SpringSimulation(...))` using the gesture velocity |

Curves: `Curves.easeOutCubic` (enter), `Curves.easeInCubic` (exit), `Curves.easeInOutCubic` (move); avoid `Curves.linear` for UI movement and `bounceOut`/`elasticOut` except for genuine playfulness. Material 3 `Easing.emphasizedDecelerate` / `Durations.medium2` are good defaults.

Common bugs to look for:
- `AnimationController` not disposed, or created without `vsync` (`SingleTickerProviderStateMixin`).
- `AnimatedSwitcher` children without different keys → no animation.
- `setState` every frame to drive an animation instead of `AnimatedBuilder`/transitions → whole subtree rebuilds.
- `Opacity` widget animated in a list (expensive) → `FadeTransition` / `AnimatedOpacity`.
- Animations that ignore reduced motion.

## Reduced motion

```dart
final reduce = MediaQuery.disableAnimationsOf(context);
final duration = reduce ? Duration.zero : const Duration(milliseconds: 250);
```
Replace large movement with a simple fade when reduced motion is on, rather than removing feedback entirely.

## Haptics

`HapticFeedback.selectionClick()` for pickers/toggles/segment changes, `lightImpact()` for confirming a successful action or a snap point, `mediumImpact()` for significant actions, `heavyImpact()` sparingly. iOS users expect haptics on toggles, pull-to-refresh trigger, long-press menus; Android haptics vary by device — keep them subtle. Never on every scroll tick.

## Native feel per platform

- **Page transitions:** set `pageTransitionsTheme` so iOS gets `CupertinoPageTransitionsBuilder` (with swipe-back) and Android gets `PredictiveBackPageTransitionsBuilder` / `FadeForwardsPageTransitionsBuilder`.
- **Adaptive controls:** `Switch.adaptive`, `Slider.adaptive`, `Checkbox.adaptive`, `CircularProgressIndicator.adaptive`, `RefreshIndicator.adaptive`, `showAdaptiveDialog` + `AlertDialog.adaptive`. Action sheets: `CupertinoActionSheet` on iOS, `showModalBottomSheet` on Android.
- **Scroll physics:** default `ScrollConfiguration` already gives bouncing on iOS, clamping + stretch on Android — don't force `BouncingScrollPhysics` everywhere.
- **Typography:** platform default fonts (SF Pro / Roboto) unless the brand needs a custom font; respect `TextScaler`, don't clamp it below ~1.3×.
- **Bottom sheets & keyboards:** `isScrollControlled: true` + `MediaQuery.viewInsetsOf(context).bottom` padding so the keyboard doesn't cover inputs; `showDragHandle: true`.
- **Status bar / edge-to-edge:** Android 15 enforces edge-to-edge — content must handle insets (`SafeArea`, `SystemUiOverlayStyle` matching light/dark).

## Visual polish checklist

- Consistent spacing scale (4/8-based), defined once (e.g. `ThemeExtension` or constants), not magic numbers.
- Colors from `Theme.of(context).colorScheme`, so dark mode works; check contrast ≥ 4.5:1 for body text.
- Loading: skeletons/shimmer for content, spinners only for short indeterminate waits; avoid layout jump when data arrives (reserve space).
- Empty and error states with a clear action (Retry, Create first item) — not a blank screen.
- Buttons show a disabled/loading state while submitting and can't be double-tapped (pair with `droppable()` in the bloc).
- Images fade in (`FadeInImage` / `cached_network_image` `fadeInDuration`) with placeholders of the right aspect ratio.
- Tap targets ≥ 48×48 dp; touch feedback on custom tappables (`InkWell` inside `Material`, not bare `GestureDetector`).

## Report

Use the report format from SKILL.md. For each motion finding, give the concrete duration/curve/widget to use and, where helpful, a short before → after Dart snippet.
