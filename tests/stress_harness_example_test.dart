// Demonstrates the stress-test harness from references/stress-test.md:
// "demo" passes; "worst" fails with RenderFlex overflows at 2x text and with the keyboard open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Screen extends StatelessWidget {
  const Screen({super.key, required this.items});
  final List<String> items;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [for (final i in items) ListTile(title: Text(i))]),
      );
}

final fixtures = <(String, List<String>)>[
  ('demo', ['a']),
  ('worst', List.generate(14, (i) => 'Item $i')),
];
const sizes = [Size(375, 812)];
const scales = [1.0, 2.0];

void main() {
  for (final size in sizes) {
    for (final scale in scales) {
      for (final keyboard in [false, true]) {
        for (final (name, data) in fixtures) {
          testWidgets('$name ${size.width.toInt()}w x$scale kb=$keyboard', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 336);
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            await tester.pumpWidget(MaterialApp(home: Screen(items: data)));
            await tester.pump(const Duration(milliseconds: 500));
            final mq = MediaQuery.of(tester.element(find.byType(Screen)));
            expect(mq.textScaler.scale(10), closeTo(10 * scale, 0.01));
            expect(mq.viewInsets.bottom, keyboard ? 336 : 0);
          });
        }
      }
    }
  }
}
