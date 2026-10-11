# flutter-mobile — a Claude Code skill for Flutter (Android + iOS)

A [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that makes Claude act like a senior Flutter engineer for **BLoC/Cubit** apps on Android and iOS.

| Mode | Ask Claude something like | What you get |
|---|---|---|
| **Review** | "review my flutter app" | `FLUTTER_REVIEW.md` — findings ranked 🔴 Critical → 🟢 Low, each with `file:line` and a Dart fix |
| **Build** | "add a search screen using bloc" | Feature-first code (repository → bloc → view), Equatable state, debounce/restartable, `bloc_test` tests |
| **Release** | "is it ready for Play Store / App Store?" | `RELEASE_READINESS.md` with a ✅ / ⚠️ / ❌ verdict and blockers (Gradle, AndroidManifest, Info.plist, signing, privacy) |
| **UI/UX** | "review the UI/UX", "make it feel smoother", "this sheet feels off" | `UI_UX_REVIEW.md` — Before / After / Why tables for motion, gestures, haptics, materials, typography, platform feel, accessibility |
| **Stress test** | "try to break this screen", "what if the name is really long" | `STRESS_TEST.md` — worst-case data (long/short/RTL/emoji names, 0/1/1,000 items, 200% text, dark, RTL) + a widget-test harness that fails on overflow |

## Install

```bash
git clone https://github.com/GautamBharte/flutter-mobile-skill.git
cp -R flutter-mobile-skill/flutter-mobile ~/.claude/skills/
```

Or per project: copy `flutter-mobile/` into `<your-app>/.claude/skills/`. Restart Claude Code — the skill triggers automatically when you work on a Flutter app.

## What's inside

```
flutter-mobile/
├── SKILL.md                 # mode selection, project orientation, report format
├── references/
│   ├── review.md            # crashes, BLoC misuse, leaks, performance, security
│   ├── build-bloc.md        # BLoC/Cubit conventions, folder layout, tests
│   ├── release.md           # Play Store + App Store checklist
│   ├── ui-ux-review.md      # UI/UX standards, design foundations, materials, haptics, typography
│   ├── motion.md            # exact curves, durations, springs, gestures, performance (Flutter APIs)
│   └── stress-test.md       # worst-case data catalog + overflow test harness
├── assets/motion_kit.dart   # tested drop-in: curves, Apple-style springs, PressableScale, Appear, rubberband
├── scripts/flutter_scan.sh  # quick grep scan for common anti-patterns
└── evals/evals.json         # test prompts + assertions
examples/shop_app/           # deliberately buggy sample app used for testing
results/iteration-1/         # test outputs: with skill vs. plain Claude
```

> ⚠️ `examples/shop_app` is **intentionally broken** (fake key, cleartext HTTP, missing permissions, BLoC bugs). Don't copy code from it.

## Test results (iteration 1)

Three tasks on `examples/shop_app`, each run with the skill and without it (plain Claude). Full outputs are in [`results/iteration-1/`](results/iteration-1).

| Task | With skill | Plain Claude |
|---|---|---|
| **Code review** | Saved `FLUTTER_REVIEW.md`: 25 findings (5 Critical / 7 High / 7 Medium / 6 Low) with file:line + fixes; ran `flutter analyze` | Thorough findings, chat reply only, no severity ranking or saved report; didn't run tooling |
| **Release readiness** | Saved `RELEASE_READINESS.md`, ❌ verdict, 7 numbered blockers; ran analyze + format | Similar blockers, chat only |
| **Add search feature** | Bloc + Equatable state + `bloc_concurrency` debounce/restartable, repository with typed exceptions, 16 tests, analyze clean | Bloc with hand-written debounce/cancel, 9 tests, analyze clean |
| Avg. time | ~158 s | ~107 s |

Notable: running the Flutter toolchain let the skill discover the sample app had **no `analysis_options.yaml`**, so `flutter analyze` reported "No issues" while hiding 12 lint warnings. That check is now built into the skill.

### Iteration 2 — UI/UX + stress test

The skill reviewed `examples/shop_app` for UI/UX and stress-tested the cart and login screens ([`results/iteration-2/`](results/iteration-2)). It wrote `UI_UX_REVIEW.md`, `STRESS_TEST.md`, and a 97-case widget test (61 pass / 36 fail, every failure a real break). It caught the checkout crash (`Navigator.pop` inside `BlocBuilder`), the non-scrolling cart overflowing on a 375 pt phone, raw price formatting (`₹0.30000000000000004`), the 36 dp `GestureDetector` login button with no press state, and the `Opacity`-driven infinite pulse. Its feedback on the skill (keyboard insets lost in the test template, `pumpAndSettle` timeouts, test HTTP returning 400, seeding Bloc state) has been folded back into `stress-test.md`, `ui-ux-review.md`, and `flutter_scan.sh`.

## UI/UX standards — what's covered

The UI/UX and stress-test modes are a Flutter translation of Emil Kowalski's design-engineering skills ([emilkowalski/skills](https://github.com/emilkowalski/skills) — `emil-design-eng`, `review-animations`, `improve-animations`, `apple-design`, `break-ui`) and Apple's WWDC design talks, mapped onto Flutter widgets, `AnimationController`, `SpringSimulation`, gestures, and `MediaQuery` accessibility flags:

- **Animation decisions** — frequency (no motion on 100+/day actions), purpose, strong curves (`Cubic(0.23, 1, 0.32, 1)`), sub-300 ms durations, never scale from 0, origin-aware popovers
- **Springs & gestures** — Apple damping/response springs, velocity handoff, momentum projection, rubber-banding, interruptibility, press feedback on pointer-down, `onDoubleTap` delay trap
- **Performance** — transform/opacity over layout, `FadeTransition` over `Opacity`, scoped `AnimatedBuilder`, `RepaintBoundary`, bounded `BackdropFilter`, profile-mode checks
- **Accessibility** — reduced motion as gentler (not zero), text scale 200%, high contrast, bold text, 48 dp targets
- **Design foundations** — feedback types, wayfinding, forgiveness over confirmation, materials & depth, haptics, typography, iOS vs Android feel
- **Stress testing** — realistic worst-case data catalog and an automated multi-size/text-scale widget-test harness

`motion_kit.dart` is analyzer-clean and covered by widget tests (press scale, entrance, reduced motion, spring settling).

## License

MIT
