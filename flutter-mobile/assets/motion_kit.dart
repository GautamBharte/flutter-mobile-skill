// motion_kit.dart — drop-in motion tokens and helpers for Flutter apps.
//
// Copy into lib/core/motion/ (or wherever the project keeps theme code) and
// adapt names to the project's conventions. No dependencies beyond Flutter.
//
// Values follow the flutter-mobile skill's UI/UX standards
// (references/motion.md): strong ease-out curves, sub-300ms UI timing,
// critically damped springs by default, press feedback on pointer-down,
// and reduced-motion support.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Strong curves. Flutter's built-in `Curves.easeOut` is weak; these have
/// the punch that makes UI motion feel intentional.
abstract final class MotionCurves {
  /// Enter / exit / default UI motion.
  static const Cubic easeOut = Cubic(0.23, 1, 0.32, 1);

  /// Elements moving or morphing on screen.
  static const Cubic easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// iOS-like sheet / drawer curve.
  static const Cubic drawer = Cubic(0.32, 0.72, 0, 1);
}

/// Duration budget. UI motion stays under 300 ms.
abstract final class MotionDurations {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration release = Duration(milliseconds: 160);
  static const Duration tooltip = Duration(milliseconds: 150);
  static const Duration menu = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 300);
  static const Duration staggerStep = Duration(milliseconds: 40);
}

/// Builds a spring from Apple's designer-friendly parameters.
///
/// [dampingRatio] 1.0 = critically damped (no overshoot); < 1 bounces.
/// [response] ≈ how fast it reaches the target, in seconds (not a duration).
SpringDescription appleSpring({
  double dampingRatio = 1.0,
  double response = 0.35,
  double mass = 1.0,
}) {
  final stiffness = math.pow(2 * math.pi / response, 2) * mass;
  final damping = 4 * math.pi * dampingRatio * mass / response;
  return SpringDescription(
    mass: mass,
    stiffness: stiffness.toDouble(),
    damping: damping,
  );
}

abstract final class MotionSprings {
  /// Default for anything that isn't released with momentum.
  static final SpringDescription standard = appleSpring();

  /// Repositioning (PiP-style moves).
  static final SpringDescription move = appleSpring(response: 0.4);

  /// Sheets / drawers released with a flick — slight bounce is earned.
  static final SpringDescription sheet = appleSpring(
    dampingRatio: 0.8,
    response: 0.3,
  );

  /// Thrown cards / flicked items.
  static final SpringDescription flick = appleSpring(
    dampingRatio: 0.8,
    response: 0.4,
  );
}

/// Animates [controller] to [target] with a spring, starting from its current
/// value and carrying [velocity] (in controller units per second).
///
/// Convert a drag velocity: `pixelsPerSecond / extentInPixels`.
TickerFuture springTo(
  AnimationController controller,
  double target, {
  double velocity = 0,
  SpringDescription? spring,
}) {
  return controller.animateWith(
    SpringSimulation(
      spring ?? MotionSprings.standard,
      controller.value,
      target,
      velocity,
    ),
  );
}

/// Where a flick would come to rest (Apple's exponential-decay projection).
/// Add to the current position, then snap to the nearest detent.
double projectMomentum(
  double velocityPxPerSecond, {
  double decelerationRate = 0.998,
}) {
  return (velocityPxPerSecond / 1000) *
      decelerationRate /
      (1 - decelerationRate);
}

/// Progressive resistance past a boundary instead of a hard stop.
double rubberband(double overshoot, double dimension, {double c = 0.55}) {
  return (overshoot * dimension * c) / (dimension + c * overshoot.abs());
}

/// True when the user asked the OS for reduced motion.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Scales a child down slightly while pressed, starting on pointer-down.
///
/// Uses a raw [Listener] for the visual state because `onTapDown` waits up to
/// 100 ms (kPressTimeout) before firing. Releases the press visual if the
/// finger moves past touch slop (the user is scrolling, not tapping).
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = false,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Keep subtle: 0.95–0.98.
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  Offset? _downPosition;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = reduceMotionOf(context);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: enabled
            ? (e) {
                _downPosition = e.position;
                _setPressed(true);
              }
            : null,
        onPointerMove: (e) {
          final start = _downPosition;
          if (start != null && (e.position - start).distance > kTouchSlop) {
            _setPressed(false);
          }
        },
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () {
                  if (widget.haptic) HapticFeedback.lightImpact();
                  widget.onTap!();
                }
              : null,
          child: AnimatedScale(
            scale: _pressed && !reduce ? widget.scale : 1,
            // Asymmetric: press lands fast, release settles slightly slower.
            duration: _pressed
                ? MotionDurations.press
                : MotionDurations.release,
            curve: MotionCurves.easeOut,
            child: AnimatedOpacity(
              opacity: _pressed && reduce ? 0.7 : 1,
              duration: MotionDurations.press,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Entrance animation on first build: fade + small rise + 0.97 scale.
/// Never starts from scale 0. With reduced motion, fades only.
///
/// For lists, stagger with `delay: MotionDurations.staggerStep * index`
/// (cap the index so item 40 doesn't wait 1.6 s).
class Appear extends StatefulWidget {
  const Appear({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 250),
    this.offsetY = 8,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: MotionCurves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotionOf(context);
    // FadeTransition, not Opacity: it animates opacity on the layer without
    // rebuilding the subtree every frame.
    return FadeTransition(
      opacity: _t,
      child: reduce
          ? widget.child
          : AnimatedBuilder(
              animation: _t,
              child: widget.child,
              builder: (context, child) {
                final v = _t.value;
                return Transform.translate(
                  offset: Offset(0, (1 - v) * widget.offsetY),
                  child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
                );
              },
            ),
    );
  }
}
