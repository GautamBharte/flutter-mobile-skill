# UI/UX review mode (Flutter)

Goal: review a Flutter screen, component, or whole app against a high craft bar so it feels fast, physical, and at home on iOS and Android. Default to flagging — a UI that "works" but feels sluggish, appears from nowhere, fires motion on every tap, or drops frames is a regression, not a pass.

This mode adapts the design-engineering philosophy of Emil Kowalski ([emilkowalski/skills](https://github.com/emilkowalski/skills): emil-design-eng, review-animations, improve-animations, apple-design, break-ui) and Apple's WWDC design talks (*Designing Fluid Interfaces*, *The Details of UI Typography*, *Designing Audio-Haptic Experiences*) to Flutter's widget, animation, and gesture APIs.

Companion files — load them as you go:
- `references/motion.md` — the full motion rulebook with exact Flutter values (curves, durations, springs, gestures, performance). Load for any finding about animation or gestures.
- `references/stress-test.md` — worst-case data testing ("break the UI"). Load when the user asks to stress-test, or when reviewing lists, cards, profile rows, or anything rendering user data.
- `assets/motion_kit.dart` — ready-made curves, springs, `PressableScale`, `Appear`, `springTo`, `rubberband`, `projectMomentum`. Recommend copying it in rather than hand-rolling the same helpers in every fix.

## Philosophy (why the details matter)

- **Unseen details compound.** Most users never consciously notice a correct easing curve or a press state. They just feel the app is "good". When something behaves exactly as assumed, the user proceeds without a second thought — that's the goal.
- **Taste is trained.** Don't stop at "it works". Ask why the best apps (iOS system apps, Things, Linear, Arc) feel the way they do, and hold this app to that.
- **Beauty is leverage.** People choose apps on the overall experience. Good defaults and good motion are differentiators.
- **The interface should feel like an extension of the user.** It responds instantly, moves continuously, carries momentum, resists at edges, and can be grabbed and redirected mid-motion.

## Review procedure

1. **Recon.** Find the motion and UI surface: `grep -rnE "AnimationController|Animated[A-Z]|Tween|Curves\.|Duration\(|Hero|PageRouteBuilder|GestureDetector|InkWell|BackdropFilter|Opacity\(|HapticFeedback|showModalBottomSheet|Tooltip" lib`. Note the theme (`ThemeData`, `ColorScheme`, `TextTheme`, `pageTransitionsTheme`), any existing motion tokens, motion packages (`flutter_animate`, `animations`, `rive`, `lottie`), and the product's personality (playful consumer app vs. crisp utility).
2. **Frequency map.** Classify each animated element by how often a user sees it (see `motion.md` §1). Severity depends on it.
3. **Audit** against the ten standards below and the checklist at the end. Read `motion.md` for exact values.
4. **Stress-test data** if the screen renders user content (`stress-test.md`).
5. **Vet.** Re-read the code for every finding. Drop anything by-design, exempt (e.g. a centered modal), or speculative. When feel can't be judged from code alone (a crossfade, a spring's bounce), say so and add a feel-check step instead of guessing.
6. **Report** in the format below.

## The ten standards

Each violation is a finding.

1. **Justified motion.** Every animation answers "why does this animate?": spatial consistency, state indication, explanation, feedback, or preventing a jarring change. "It looks cool" on something seen often is not a reason.
2. **Frequency-appropriate.** 100+/day actions (tab switches, keyboard submits, list taps, the search field) get no or near-instant animation. Occasional surfaces (sheets, dialogs, snackbars) get standard motion. Rare moments (onboarding, first success, celebration) may delight.
3. **Responsive easing.** Enter/exit uses a strong ease-out (`Cubic(0.23, 1, 0.32, 1)`). `Curves.easeIn` on UI is a block — it delays the exact moment the user is watching. Flutter's built-in `Curves.easeOut` is weak for deliberate motion.
4. **Sub-300 ms UI.** UI motion stays under 300 ms unless it's a large surface or explanatory animation. A 180 ms menu feels faster than a 400 ms one.
5. **Physical correctness & origin.** Nothing scales from 0 — start at 0.95–0.97 with opacity 0. Menus/popovers/tooltips grow from their trigger (`alignment` of `ScaleTransition`/`Transform.scale`), not from center. **Dialogs are exempt** — they're centered.
6. **Interruptibility.** Anything rapid or gesture-driven can be grabbed and reversed mid-flight. Animate from the current value (implicit animations and `animateWith` do; `controller.forward(from: 0)` does not). Never block input during a transition.
7. **Cheap to render.** Animate transform and opacity (`Transform`, `ScaleTransition`, `SlideTransition`, `FadeTransition`). Animating layout (`AnimatedContainer` width/height/padding in lists, `AnimatedSize` on big subtrees), the `Opacity` widget, `ClipRRect`/`BackdropFilter` over large areas, or `setState` every frame are performance findings.
8. **Accessibility.** Honour `MediaQuery.disableAnimationsOf` (gentler, not zero — keep fades and color, drop movement), `textScaler` (layouts survive 200%), `boldTextOf`, `highContrastOf`, semantics labels, and 48×48 dp tap targets.
9. **Asymmetric timing.** Slow where the user is deciding (hold-to-delete fills over ~1.5–2 s, linear), fast where the system responds (release snaps back in ~200 ms ease-out). Use `AnimationController.reverseDuration`.
10. **Cohesion.** Motion matches the product's personality and is consistent across screens: one set of curve/duration tokens, not five near-identical `Cubic`s. A bouncy component in a crisp app is a finding. When unsure whether motion feels right, the strongest move is often to delete it.

**Escalate on sight:** `Curves.easeIn`/`easeInCubic` on UI; `ScaleTransition`/`Tween(begin: 0.0)` on scale; durations > 300 ms on small UI; animation on high-frequency taps; `Opacity` animated per frame; `setState` inside `addListener` driving the whole screen; `GestureDetector` pressables with no pressed state; `onDoubleTap` on something that's mostly tapped (delays every single tap); `IgnorePointer`/`AbsorbPointer` during transitions; missing reduced-motion handling on movement; `controller.forward(from: 0)` on rapidly re-triggered UI; drag-to-dismiss with a distance threshold only (no velocity).

**Remedy preference** (earlier beats later): 1) delete the animation, 2) reduce it (shorter, smaller, fewer properties), 3) fix the curve, 4) fix origin/physicality, 5) make it interruptible (implicit animation or spring from current value), 6) move it to cheap properties, 7) asymmetric timing, 8) polish (stagger, blur-masked crossfade, haptic), 9) accessibility & cohesion.

## Design foundations (beyond motion)

Use these to judge screens and flows, not just animations. They come from Apple's design principles and hold on Android too.

- **Purpose.** Every element and step must earn the user's time and attention. Ask what could be removed.
- **Agency & forgiveness.** Users stay in control: offer undo (a `SnackBar` with Undo beats an "Are you sure?" dialog for reversible actions). Reserve confirmation dialogs for destructive, irreversible actions — overused, people tap through them.
- **Responsibility.** Ask for permissions in context, at the moment they're needed, with a pre-prompt explaining why — not on first launch. Collect only what's needed.
- **Familiarity.** Use platform conventions people already know: iOS back-swipe and large titles, Android back gesture and Material components, a trash icon for delete. Things that look the same must behave the same. Break a convention only with evidence it's better.
- **Flexibility.** Works one-handed on a small phone, on a tablet, in landscape, at large text sizes, in dark mode, RTL, and for screen-reader users.
- **Simplicity, not minimalism.** Plain language, fewer steps, clear hierarchy (order, spacing, contrast) so the most important thing is the most obvious. Hiding everything behind icons looks minimal but isn't simple. Common path first, advanced options a level deeper.
- **Craft.** Every spacing, radius, timing, and color is a deliberate, defensible choice from a shared scale. Jittery scroll, misaligned icons, and layouts that break on rotation read as carelessness.
- **Delight** is the result of the above, not confetti on top. Decide the feeling (calm, confident, playful) and reinforce it everywhere.

Tactical checks:
- **Four kinds of feedback:** status (progress), completion (success), warning (before a problem), error (after). Validate forms inline as the user goes, not only on submit. Error messages say what happened and how to fix it.
- **Wayfinding:** every screen answers *where am I, where can I go, how do I get back*. Never trap the user (a full-screen flow with no close/back).
- **Grouping & mapping:** related controls sit together and near what they affect. If a control needs a label to explain what it changes, the mapping is weak.
- **Specific labels beat generic ones:** "Save address", not "Submit"; nav items named for their contents.
- **States:** every data screen has loading, empty (with a next action), error (with retry), partial, and success states. Skeletons match the final layout so nothing jumps.

## Platform feel (iOS vs Android)

- **Transitions:** set `pageTransitionsTheme` — `CupertinoPageTransitionsBuilder` on iOS (keeps edge swipe-back), `PredictiveBackPageTransitionsBuilder` or `FadeForwardsPageTransitionsBuilder` on Android. Custom `PageRouteBuilder`s often silently remove iOS swipe-back — flag it.
- **Adaptive widgets:** `Switch.adaptive`, `Slider.adaptive`, `Checkbox.adaptive`, `CircularProgressIndicator.adaptive`, `RefreshIndicator.adaptive`, `AlertDialog.adaptive` + `showAdaptiveDialog`, `CupertinoActionSheet` vs `showModalBottomSheet`, `CupertinoContextMenu` for long-press previews on iOS.
- **Scroll physics:** keep the platform default (bounce on iOS, stretch on Android). Forcing `BouncingScrollPhysics` everywhere makes Android feel foreign.
- **Navigation chrome:** iOS large titles collapse on scroll (`CupertinoSliverNavigationBar` / `SliverAppBar.large`); Android uses Material 3 top app bars. Bottom navigation: `CupertinoTabBar` vs `NavigationBar`.
- **Edge-to-edge & insets:** Android 15 enforces edge-to-edge; iOS has the Dynamic Island and home indicator. Use `SafeArea`/`MediaQuery.paddingOf`, set `SystemUiOverlayStyle` for light/dark status bar icons, and pad sheets/inputs by `MediaQuery.viewInsetsOf(context).bottom` so the keyboard never covers them.

## Materials & depth

- **Translucent chrome:** bars and sheets as a blurred layer with content scrolling underneath — `extendBodyBehindAppBar: true` + `ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: ColoredBox(color: surface.withValues(alpha: 0.7))))`. `CupertinoNavigationBar` and `CupertinoTabBar` already do this on iOS. Always wrap `BackdropFilter` in `ClipRect` (or `ClipRRect`) so the blur is limited to that area — unbounded, it blurs the whole screen behind it and is expensive.
- **Weight encodes hierarchy:** heavier/darker materials for structural regions, lighter for interactive elements. Never stack a light translucent surface on another — text legibility collapses.
- **Bigger surfaces read as thicker:** stronger blur and deeper shadow for sheets than for chips.
- **Dim to focus, separate to keep flow:** modal tasks get a scrim (`barrierColor`) and push the background back; non-blocking panels use offset/translucency without a scrim.
- **Text on translucent surfaces:** higher contrast, slightly heavier weight, a touch of letter-spacing — not flat grey.
- **Scroll edge effects, not hard dividers:** instead of a permanent 1px divider under a header, fade a subtle shadow/gradient in only when content scrolls under it (`AppBar.scrolledUnderElevation`, `notificationPredicate`).
- **Materialize, don't just fade:** blurred surfaces arrive by animating blur sigma and scale together.
- **Reduced transparency / high contrast:** when `MediaQuery.highContrastOf(context)` is true, make translucent surfaces near-solid with a defined border. (Flutter has no direct "reduce transparency" flag; high contrast is the closest signal.)

## Multimodal feedback (haptics + motion + sound)

1. **Causality** — trigger feedback on the actual event (the toggle flipping, the sheet snapping to a detent, the item dropping), and match its intensity to the action's physicality.
2. **Harmony** — haptic, visual, and sound fire on the same frame. Call `HapticFeedback` in the same callback that starts the animation, not after an `await`.
3. **Utility** — only where it earns its place. Over-feedback trains users to ignore it.

Flutter mapping: `HapticFeedback.selectionClick()` for pickers, segmented controls, toggles, and passing detents; `lightImpact()` for snaps and successful small actions; `mediumImpact()` for meaningful commits (pull-to-refresh trigger, drop); `heavyImpact()` rarely; `vibrate()` almost never. Never on every scroll tick or keystroke. Android haptic quality varies by device — keep it subtle there.

## Typography

- **Use the platform font by default** (SF Pro on iOS, Roboto/Google Sans on Android — Flutter's default `TextTheme` does this). A custom font needs a reason, and then needs its own tracking/leading tuning.
- **Tracking is size-specific:** large display text wants negative `letterSpacing` (≈ −0.02 × fontSize for 28 px+), small text slightly positive, body ≈ 0. One `letterSpacing` value for all sizes is wrong somewhere.
- **Leading inverts with size:** `height` ≈ 1.1–1.2 for big headings, 1.4–1.5 for body. Increase for scripts with tall glyphs (Thai, Vietnamese, Devanagari); clipping them is a bug.
- **Hierarchy from weight + size + leading as a set,** defined once in `TextTheme` — not ad-hoc `TextStyle(fontSize: 17)` across files.
- **Respect text scaling (Dynamic Type):** never clamp `textScaler` below ~1.3×; layouts must grow with text (no fixed heights around `Text`, use `Flexible`/wrapping). Test at 200%.
- **Numbers that change** (prices, counters, timers) use `FontFeature.tabularFigures()` so they don't jitter.

## Visual craft checklist

- Spacing from a 4/8 scale and radii from a small set, defined once (`ThemeExtension` or constants).
- Colors from `Theme.of(context).colorScheme`; no hard-coded `Colors.black`/`Colors.white` text that breaks dark mode. Body text contrast ≥ 4.5:1; large text ≥ 3:1.
- Tap targets ≥ 48×48 dp (`MaterialTapTargetSize.padded`), even when the visual is smaller.
- Every pressable gives feedback: `InkWell` inside a `Material` (ripple), or a scale press state (`PressableScale`). Bare `GestureDetector` buttons are a finding.
- Buttons show disabled/loading state during async work and can't be double-submitted.
- Images reserve their aspect ratio, fade in, have `errorBuilder` fallbacks, and decode at display size (`cacheWidth`).
- Icon-only buttons have `tooltip`/semantic labels.
- Long-press menus, swipe actions, and other hidden gestures have a visible alternative.

## Required output format

Use the report structure from SKILL.md (title as "UI/UX Review", severity sections, What's good, Next steps), and **inside each severity section put findings in a Before | After | Why table** — never "Before:/After:" lines:

| Before | After | Why |
| --- | --- | --- |
| `curve: Curves.easeIn` on menu (`lib/x.dart:42`) | `curve: Cubic(0.23, 1, 0.32, 1)` | Ease-in delays the first frames — the moment the user is watching |
| `ScaleTransition` from `0.0` | `Tween(begin: 0.96, end: 1.0)` + `FadeTransition` | Nothing appears from nothing |
| `GestureDetector` login button, no pressed state | `PressableScale(scale: 0.97)` or `FilledButton` | The UI must show it heard the tap |
| `Opacity(opacity: _c.value)` in `AnimatedBuilder` | `FadeTransition(opacity: _c)` | Opacity widget repaints the subtree every frame |

Severity for UI/UX findings: 🔴 **Critical** — broken or unusable (content cut off, action unreachable, crash at large text, inaccessible primary action). 🟠 **High** — feel-breaking (ease-in on UI, animation on high-frequency actions, dropped frames, scale from 0, no press feedback on primary actions, blocked swipe-back). 🟡 **Medium** — noticeably off (wrong origin, non-interruptible dynamic UI, missing reduced motion, inconsistent tokens, missing empty/error state). 🟢 **Low** — polish (stagger, blur-masked crossfade, haptics, typography tuning).

After the tables, add up to four **Missed opportunities** — places that don't animate or give feedback but should (a state change that teleports, a sheet that doesn't explain where it came from, a first-success moment with no delight). Keep it grounded in what you saw.

For each motion finding, give exact values (curve, duration, spring) from `motion.md` and a compilable Dart snippet when the fix is more than a one-liner. Recommend a feel-check where needed: `timeDilation = 5.0` (slow motion), DevTools *Slow Animations*, profile-mode performance overlay, and a real device for gestures.

### Plan mode (optional)

If the user wants a roadmap rather than a review ("plan the animation improvements", "write tasks for my team"), write one self-contained plan per selected finding to `plans/NNN-short-slug.md`: exact file paths and current code excerpts, exact target values, ordered steps, scope boundaries, and a verification section (tests + feel-check). Write it so a developer or another agent with zero context can execute it.
