# Motion rulebook (Flutter)

Exact values and Flutter techniques behind the UI/UX review. Cite these in findings rather than approximating. `assets/motion_kit.dart` implements most of them.

Contents: 1 Should it animate · 2 Easing · 3 Duration · 4 Physicality & origin · 5 Springs · 6 Interruptibility · 7 Gestures & drag · 8 Choosing the Flutter tool · 9 Transform & clip techniques · 10 Stagger, crossfade, asymmetric timing · 11 Performance · 12 Accessibility · 13 Debugging & feel-checks · 14 Review checklist

---

## 1. Should it animate?

| How often the user sees it | Decision | Flutter examples |
|---|---|---|
| 100+ times/day | **No animation**, or instant | Bottom-nav tab switch, keyboard "Done/Next", list-row tap feedback beyond the ripple, search field focus |
| Tens of times/day | Remove or drastically reduce | Expanding list tiles, filter chips, favorite toggles |
| Occasional | Standard animation | Bottom sheets, dialogs, snackbars, page pushes, menus |
| Rare / first time | Can add delight | Onboarding, first purchase success, streak celebration, empty-state illustration |

Valid purposes: **spatial consistency** (the sheet leaves the way it came), **state indication** (a button morphs into a spinner then a check), **explanation** (onboarding shows how a gesture works), **feedback** (press scale, haptic), **preventing a jarring change** (content swaps with a quick crossfade instead of teleporting). "It looks cool" on a frequently-seen element is not a purpose.

## 2. Easing

Decision order:
- Entering or exiting → **strong ease-out** `Cubic(0.23, 1, 0.32, 1)` — starts fast, so it feels responsive.
- Moving/morphing on screen → **strong ease-in-out** `Cubic(0.77, 0, 0.175, 1)`.
- Sheets/drawers → iOS-like `Cubic(0.32, 0.72, 0, 1)` (or a spring, §5).
- Color/opacity-only change → `Curves.ease`.
- Constant motion (indeterminate progress, marquee) → `Curves.linear`.
- Default → strong ease-out.

**Never `Curves.easeIn` (or `easeInCubic`, `easeInQuad`…) for UI.** It starts slow, delaying the moment the user watches most closely; a 200 ms ease-out feels faster than a 200 ms ease-in. The one acceptable use is an exit that the user isn't watching, and even then a fast ease-out is usually better.

Flutter's `Curves.easeOut`/`easeInOut` are weak for deliberate UI; prefer the cubics above (as shared tokens — `MotionCurves` in the kit). Material 3's `Easing.emphasizedDecelerate` / `Easing.standard` and `Durations.*` tokens are acceptable if the app is consistently Material — consistency beats switching systems mid-app. `Curves.bounceOut`/`elasticOut` are for genuinely playful moments only.

For reversible transitions, mirror the curve on the way back: use `CurvedAnimation(curve: …, reverseCurve: …flipped)` so the outbound path matches the return.

## 3. Duration

| Element | Duration |
|---|---|
| Press feedback (scale/highlight) | 100–160 ms |
| Tooltips, small popovers | 125–200 ms |
| Menus, dropdowns, chips, selection changes | 150–250 ms |
| Dialogs, bottom sheets, side drawers | 200–350 ms (large surfaces up to ~500 ms) |
| Page transitions | Platform default (Material ~300 ms; Cupertino route is longer and matches iOS — keep it) |
| Onboarding / explanatory | Can be longer |

**Rule: small UI motion stays under 300 ms.** Faster spinners make loading feel faster. After the first tooltip has shown, neighbours should appear instantly.

## 4. Physicality & origin

- **Never scale from 0.** Start at 0.95–0.97 with opacity 0. A `ScaleTransition` or `Tween<double>(begin: 0.0, end: 1.0)` on scale makes things look like they came from nowhere.
  ```dart
  FadeTransition(
    opacity: anim,
    child: ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.0).animate(anim),
      alignment: originAlignment, // see below
      child: child,
    ),
  )
  ```
- **Origin-aware popovers.** Menus, popovers, and tooltips grow from their trigger. Compute an `Alignment` from the trigger's position relative to the popup (e.g. a menu opening below-right of a button → `Alignment.topLeft`) and pass it to `ScaleTransition.alignment` / `Transform.scale(alignment:)`. `Alignment.center` on an anchored popup is a finding. **Dialogs and full-screen modals are exempt** — they're centered.
- **Press feedback on every pressable.** Scale 0.95–0.98 while pressed (`PressableScale` in the kit), or the Material ink ripple (`InkWell` inside `Material`). Scale also shrinks children — that's intended.
- **Spatial consistency.** Enter and exit along the same path: a sheet that rises from the bottom dismisses downward; a page pushed from the right pops to the right. A snackbar that slides up shouldn't fade out sideways.
- **Hint in the direction of the gesture.** In-between frames should point at the outcome: a card being dragged toward "dismiss" can tilt slightly and fade; a pull-to-refresh indicator grows with the pull.

## 5. Springs

Springs feel natural because they simulate physics, have no fixed duration, and — critically — start from the current value and carry velocity, which makes them interruptible. Use them for anything the user can touch: draggable sheets, swipeable cards, snapping carousels, pull-to-dismiss, "alive" elements.

Think in Apple's two parameters instead of mass/stiffness/damping:
- **Damping ratio** — 1.0 = critically damped (no overshoot). < 1 overshoots; lower = bouncier.
- **Response** — roughly how fast it gets there, in seconds (not a duration).

Conversion (mass 1): `stiffness = (2π / response)²`, `damping = 4π · dampingRatio / response`. `appleSpring()` in the kit does this. (`SpringDescription.withDampingRatio` takes a ratio but still needs stiffness.)

| Interaction | Damping ratio | Response |
|---|---|---|
| Default UI spring (no momentum) | 1.0 | 0.3–0.4 |
| Reposition / move (PiP-style) | 1.0 | 0.4 |
| Sheet/drawer released with a flick | 0.8 | 0.3 |
| Thrown card / rotation | 0.8 | 0.4 |

**Add bounce only when the gesture carried momentum.** Overshoot on a menu that simply opened feels wrong; overshoot on a card you flicked feels right. Keep it subtle.

```dart
// From the current value, with velocity, to a target:
controller.animateWith(SpringSimulation(appleSpring(), controller.value, target, velocity));
```

## 6. Interruptibility

> The thought and the gesture happen in parallel.

- **Never lock out input during a transition.** `IgnorePointer`/`AbsorbPointer` while animating, or `if (controller.isAnimating) return;` on taps, are findings. The user must be able to grab a closing sheet and pull it back.
- **Animate from the current (presentation) value.** Implicit animations (`AnimatedFoo`, `TweenAnimationBuilder`) retarget from where they are — good for rapidly toggled UI. With explicit controllers, use `controller.animateTo(target)` or `animateWith(spring)`, never `controller.forward(from: 0)` / `reset()` on something the user can re-trigger quickly — it jumps.
- **Carry velocity through a re-target.** When a gesture reverses, start the new spring with the current velocity (`controller.velocity`) so there's no "brick wall".
- **Decompose 2D motion** (a draggable PiP) into separate X and Y controllers/springs; one spring on the 2D distance desyncs.
- **Use the Flutter equivalent of "transitions, not keyframes":** for things added rapidly (snackbars/toasts stacking, counters, toggles), use implicit animations or `animateTo`, not a fixed `TweenSequence` that restarts from zero.

## 7. Gestures & drag

- **Respond on pointer-down, commit on pointer-up.** `GestureDetector.onTapDown` waits up to 100 ms (`kPressTimeout`) before firing; for instant visual feedback use a `Listener.onPointerDown` (cancel the visual when the pointer moves past `kTouchSlop` — the user is scrolling). The kit's `PressableScale` does this. `InkWell` shows its splash quickly and is fine.
- **Don't add `onDoubleTap` casually.** A `GestureDetector` with `onDoubleTap` delays every single `onTap` while it waits for a possible second tap (~300 ms). Only pay that cost where double-tap really exists.
- **1:1 tracking.** During a drag, the element follows the finger exactly and keeps the grab offset — don't snap its center to the finger. Update continuously in `onPanUpdate`/`onVerticalDragUpdate`; never animate only at the end.
- **Hysteresis.** Flutter's gesture arena already waits for `kTouchSlop` before choosing between a drag and a scroll. Don't add extra thresholds that make drags feel sticky; do use the arena (competing recognizers) instead of guessing direction yourself.
- **Velocity-based dismissal.** Dismiss if the release velocity is high *or* the distance is past a threshold — a quick flick should be enough even if short. `DragEndDetails.velocity.pixelsPerSecond`; ~700 px/s is a reasonable "flick" threshold on phones (Flutter's `kMinFlingVelocity` is 50 px/s, which is too sensitive for dismiss decisions). Decide commit vs. reverse by the **sign** of velocity, not position, at release.
- **Velocity handoff.** When the finger lifts, the animation continues at the finger's velocity — no seam. Convert pixels/s into controller units/s by dividing by the drag extent: `velocity = details.velocity.pixelsPerSecond.dy / sheetHeight`.
- **Momentum projection.** Choose the snap target from where the flick *would* land, not from the release point: `projected = position + projectMomentum(velocityPxPerSec)`, then snap to the nearest detent (the kit's `projectMomentum` uses Apple's `(v/1000)·d/(1−d)`, `d ≈ 0.998`). This is what makes a flick "throw" a sheet.
- **Rubber-band at boundaries.** Dragging past an edge should move less the further you go (`rubberband(overshoot, dimension)` in the kit), not hit a hard wall.
- **Multi-touch protection.** Once a custom drag starts, track the first pointer and ignore others, so a second finger doesn't make the element jump (`Listener` + remember `PointerDownEvent.pointer`; for scrollables see `ScrollBehavior.multitouchDragStrategy`).
- **Hidden gestures need a visible alternative** (swipe-to-delete also has a menu action; long-press has a button).

Draggable sheet with all of the above:

```dart
void _onDragUpdate(DragUpdateDetails d) {
  final next = _controller.value - d.primaryDelta! / _sheetHeight;
  // Rubber-band above fully-open instead of a hard stop.
  _controller.value = next > 1
      ? 1 + rubberband(next - 1, 1)
      : next;
}

void _onDragEnd(DragEndDetails d) {
  final vPx = -d.velocity.pixelsPerSecond.dy;          // up = positive
  final projected = _controller.value + projectMomentum(vPx) / _sheetHeight;
  final target = projected > 0.5 ? 1.0 : 0.0;           // nearest detent
  final spring = vPx.abs() > 700 ? MotionSprings.sheet : MotionSprings.standard;
  springTo(_controller, target, velocity: vPx / _sheetHeight, spring: spring);
  HapticFeedback.lightImpact();                         // same frame as the snap starts
}
```

Use an `AnimationController.unbounded` (or clamp after rubber-banding) when values can exceed 0–1.

## 8. Choosing the Flutter tool

Pick the lightest tool that works.

| Need | Use |
|---|---|
| A property changes (size, color, alignment, opacity, scale) | Implicit: `AnimatedOpacity`, `AnimatedScale`, `AnimatedSlide`, `AnimatedAlign`, `AnimatedContainer` (not in long lists), `TweenAnimationBuilder` |
| Animate on first appearance (CSS `@starting-style` equivalent) | `TweenAnimationBuilder` from begin→end on first build, or the kit's `Appear`; `flutter_animate`'s `.animate().fadeIn().scaleXY(begin: 0.96)` if the project uses it |
| Swap one widget for another | `AnimatedSwitcher` (children **must** have different `key`s or nothing animates) with `switchInCurve`/`switchOutCurve`; `AnimatedCrossFade` for two fixed children |
| List insert/remove | `AnimatedList` / `SliverAnimatedList` (animate size + fade together; tune until it feels right) |
| Element shared between routes | `Hero` (consider `createRectTween: (b, e) => MaterialRectArcTween(begin: b, end: e)`); `animations` package `OpenContainer` (container transform), `SharedAxisTransition`, `FadeThroughTransition` |
| Choreographed / repeating / gesture-driven | `AnimationController` + `FadeTransition`/`ScaleTransition`/`SlideTransition`/`RotationTransition`, `Interval` for sequencing, `SpringSimulation` for physics |
| Designer-made illustration animation | Rive / Lottie (pause when off-screen) |

## 9. Transform & clip techniques

- **Offsets relative to own size** (CSS `translateY(100%)`): `SlideTransition` and `FractionalTranslation` use fractions of the child's size — `Offset(0, 1)` moves it by its own height regardless of content. Prefer this to hard-coded pixel offsets.
- **Scale scales children** — fonts and icons shrink with a press scale. Intended.
- **3D depth** (flips, card tilt): `Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle))`. The `setEntry(3, 2, 0.001)` adds perspective.
- **Clip reveals** (CSS `clip-path: inset()`): `ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: t, child: child))` reveals left→right as `t` goes 0→1; `heightFactor` for top→bottom; a `CustomClipper<Rect>` for anything else. Cheap and smooth.
- **Hold-to-delete:** a colored overlay revealed with the clip above, driven by a controller with `duration: 1500–2000 ms` (linear, deliberate) and `reverseDuration: 200 ms` (snappy release); commit in the status listener when it completes; `HapticFeedback.mediumImpact()` on commit; scale 0.97 on the button while held.
- **Seamless segmented/tab color change:** stack a second copy of the labels styled "active" on top and clip it to the moving indicator's rect — text color changes exactly at the indicator edge, which per-label color tweens can't do.
- **Reveal on scroll:** animate once when the item first becomes visible (`visibility_detector`, or check position in a `ScrollController` listener); don't replay every time it re-enters.
- **Before/after comparison slider:** stack two images, clip the top one with `Align(widthFactor: dragFraction)`.

## 10. Stagger, crossfade, asymmetric timing

- **Stagger** group entrances by **30–80 ms** per item (`Interval(i * step, i * step + span)` on one controller, or `Appear(delay: step * i)`). Cap the index (only the first ~8 visible items stagger). Stagger is decorative — taps must work immediately.
- **Blur-masked crossfade:** when an `AnimatedSwitcher` crossfade shows two overlapping states despite curve tuning, add a brief blur during the swap — `ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s))` with `s` peaking around 2–4 mid-transition. It blends the two states into one perceived change. Keep it small; blur is expensive.
- **Asymmetric timing:** slow where the user decides, fast where the system responds. `AnimationController(duration: …, reverseDuration: …)`, `AnimatedSwitcher(duration:, reverseDuration:)`. Exits are generally faster than entrances.
- **Cohesion:** match motion to personality — playful apps can bounce a little, finance/productivity stays crisp. One token set for the whole app.

## 11. Performance

Smooth = every frame under 16 ms (8 ms on 120 Hz ProMotion / high-refresh Android). Check in **profile mode** with DevTools — debug mode is not representative.

- **Prefer transform/opacity animations** via `*Transition` widgets and `Transform`; they don't re-layout. Animating `width`/`height`/`padding`/`margin` (`AnimatedContainer`, `AnimatedSize`, `AnimatedPadding`) relayouts every frame — fine for one small widget, a problem in lists or big subtrees.
- **`Opacity` widget in an animation is a finding** — use `FadeTransition`/`AnimatedOpacity` (which use an opacity layer without rebuilding). For a static semi-transparent image/color, use the color's alpha instead.
- **Avoid `saveLayer`-heavy widgets in animated or scrolling content:** `Opacity`, `ShaderMask`, `ColorFiltered`, `BackdropFilter`, `Clip.antiAliasWithSaveLayer`. Always bound `BackdropFilter` with a clip.
- **Don't drive animation with `setState` on a big widget.** `controller.addListener(() => setState(() {}))` on a screen rebuilds everything 60–120×/s. Use `AnimatedBuilder` scoped to the animated part, pass the static subtree as `child:`, or pass the `Animation` straight to a `*Transition` widget.
- **Isolate repaints** with `RepaintBoundary` around continuously animating parts (spinners, Lottie, tickers) so the rest of the screen doesn't repaint.
- **Rebuild storms** (Flutter's version of updating a CSS variable on a parent): a value that changes every frame stored high in the tree (`setState` at the root, a `Provider`/`InheritedWidget` many widgets depend on, `MediaQuery.of(context)` instead of `MediaQuery.sizeOf`) rebuilds all dependents. Push per-frame values down to the one widget that needs them.
- **Don't do heavy work during transitions** (JSON decode, image decode, DB queries) — kick it off before or after, or use `compute`/`Isolate.run`. A page transition that stutters because `initState` parses a big file is a finding.
- **Impeller** (default renderer on iOS and modern Android) removes most shader-compilation jank; if the app opts out, first-run animation jank is expected.

## 12. Accessibility

- **Reduced motion** — `MediaQuery.disableAnimationsOf(context)` (iOS Reduce Motion / Android "Remove animations"). Reduced means gentler, not zero: replace slides, scales, springs, parallax, and auto-playing loops with short opacity crossfades (~150–200 ms); keep color/opacity changes that aid understanding; drop overshoot.
  ```dart
  final reduce = MediaQuery.disableAnimationsOf(context);
  final offset = reduce ? Offset.zero : const Offset(0, 0.08);
  ```
- **Avoid** full-screen moving backgrounds, slow looping oscillations (~one cycle per 5 s is the worst for motion sensitivity), and abrupt brightness jumps (animate theme changes; `MaterialApp` already lerps `ThemeData`).
- **Large moving objects:** make them semi-transparent while travelling; fade big surfaces out during a large reposition and back once settled.
- **Hover** only matters for tablets with a pointer or desktop — use `MouseRegion`/`InkWell.onHover`, never make hover the only way to reveal an action on mobile.
- **High contrast** (`MediaQuery.highContrastOf`) → solid surfaces with borders; **bold text** (`MediaQuery.boldTextOf`) → don't hard-code weights that ignore it.
- Animated status changes should also be announced: `SemanticsService.announce` or live regions for important async results.

## 13. Debugging & feel-checks

- **Slow motion:** `import 'package:flutter/scheduler.dart'; timeDilation = 5.0;` (or DevTools → *Slow Animations*). Check: do colors crossfade cleanly or show two states? Does the curve start/stop abruptly? Is the scale origin right? Are opacity, scale, and position in sync?
- **Frame-by-frame:** DevTools Performance view in profile mode; look for frames over budget during the animation.
- **Performance overlay:** `MaterialApp(showPerformanceOverlay: true)` in profile mode.
- **Real devices for gestures** — sheets, swipes, and springs feel different under a real finger at 120 Hz. Test on one iPhone and one mid-range Android.
- **Fresh eyes:** review motion again the next day; imperfections you stopped seeing become obvious.

## 14. Review checklist (Flutter)

| Issue | Fix |
|---|---|
| `Curves.easeIn*` on UI | `Cubic(0.23, 1, 0.32, 1)` (enter/exit) or `Cubic(0.77, 0, 0.175, 1)` (on-screen move) |
| Scale tween begins at `0.0` | Begin at 0.95–0.97 + `FadeTransition` |
| Anchored popup scales from `Alignment.center` | Alignment toward the trigger (dialogs exempt) |
| Animation on a 100+/day action | Remove it or make it near-instant |
| Small UI motion > 300 ms | 150–250 ms |
| Pressable with no pressed state (`GestureDetector` button) | `PressableScale` (0.97, on pointer-down) or `InkWell` in `Material` |
| `onDoubleTap` on a mostly-tapped widget | Remove, or move double-tap to a dedicated gesture |
| `controller.forward(from: 0)` / `reset()` on re-triggerable UI | `animateTo` / implicit animation / spring from current value |
| `IgnorePointer` / `isAnimating` guard during transitions | Let the user interrupt |
| Drag dismiss on distance only, hard stop at edges | Velocity + projection, rubber-band past edges, spring with velocity handoff |
| Same enter/exit timing on press/hold | `reverseDuration` shorter (release snaps) |
| `Opacity` / `setState` driven animation | `FadeTransition` / scoped `AnimatedBuilder` with `child:` |
| Layout animation in a list (`AnimatedContainer` height) | Transform/opacity, or `SizeTransition` on a small subtree |
| Unbounded `BackdropFilter` | Wrap in `ClipRect`/`ClipRRect` |
| No reduced-motion branch for movement | `MediaQuery.disableAnimationsOf` → crossfade |
| Group appears all at once | 30–80 ms stagger, first ~8 items |
| `AnimatedSwitcher` children without distinct keys | `ValueKey(state)` |
| Custom route removes iOS swipe-back | `CupertinoPageRoute` / platform `pageTransitionsTheme` |
| Five near-identical curves/durations | Shared `MotionCurves` / `MotionDurations` tokens |
