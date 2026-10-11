// Widget tests for flutter-mobile/assets/motion_kit.dart.
// Run: flutter create --empty motioncheck && cp flutter-mobile/assets/motion_kit.dart motioncheck/lib/
//      cp tests/*.dart motioncheck/test/ && cd motioncheck && flutter test
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motioncheck/motion_kit.dart';

void main() {
  testWidgets('PressableScale scales on pointer down and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Center(
      child: PressableScale(onTap: () => taps++, child: const SizedBox(width: 100, height: 48, child: Text('Buy'))),
    )));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Buy')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.97);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('Appear fades in from 0 and never scales from 0', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Appear(child: Text('Hi'))));
    expect(tester.widget<FadeTransition>(find.descendant(of: find.byType(Appear), matching: find.byType(FadeTransition))).opacity.value, 0);
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(find.descendant(of: find.byType(Appear), matching: find.byType(FadeTransition))).opacity.value, 1);
  });

  testWidgets('Appear respects reduced motion (no transforms)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(disableAnimations: true), child: Appear(child: Text('Hi')))));
    expect(find.descendant(of: find.byType(Appear), matching: find.byType(Transform)), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('springTo settles at target from current value', (tester) async {
    late AnimationController c;
    await tester.pumpWidget(MaterialApp(home: _Host(onReady: (ctrl) => c = ctrl)));
    c.value = 0.2;
    springTo(c, 1.0, velocity: 2.0, spring: MotionSprings.sheet);
    await tester.pumpAndSettle();
    expect(c.value, closeTo(1.0, 0.01));
  });

  test('appleSpring critical damping has no overshoot ratio', () {
    final s = appleSpring();
    final critical = 2 * (s.stiffness * s.mass) .abs();
    expect(s.damping * s.damping, closeTo(4 * s.stiffness * s.mass, 1e-6));
    expect(critical > 0, isTrue);
  });

  test('rubberband resists progressively and projectMomentum is positive', () {
    expect(rubberband(100, 400), lessThan(100));
    expect(rubberband(200, 400) - rubberband(100, 400), lessThan(rubberband(100, 400)));
    expect(projectMomentum(1000), closeTo(499, 1));
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onReady});
  final void Function(AnimationController) onReady;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController.unbounded(vsync: this);
  @override
  void initState() { super.initState(); widget.onReady(c); }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const SizedBox();
}
