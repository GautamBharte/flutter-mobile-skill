# flutter-mobile — a Claude Code skill for Flutter (Android + iOS)

A [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) that makes Claude act like a senior Flutter engineer for **BLoC/Cubit** apps on Android and iOS.

| Mode | Ask Claude something like | What you get |
|---|---|---|
| **Review** | "review my flutter app" | `FLUTTER_REVIEW.md` — findings ranked 🔴 Critical → 🟢 Low, each with `file:line` and a Dart fix |
| **Build** | "add a search screen using bloc" | Feature-first code (repository → bloc → view), Equatable state, debounce/restartable, `bloc_test` tests |
| **Release** | "is it ready for Play Store / App Store?" | `RELEASE_READINESS.md` with a ✅ / ⚠️ / ❌ verdict and blockers (Gradle, AndroidManifest, Info.plist, signing, privacy) |
| **Polish** | "make it feel smoother / more native" | `UI_POLISH.md` — animations, haptics, adaptive widgets, reduced motion |

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
│   └── ui-polish.md         # motion, haptics, native feel
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

Formal per-assertion grading is next (iteration 2).

## License

MIT
