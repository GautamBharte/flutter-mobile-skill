// Demonstrates the stress-test harness from references/stress-test.md:
// "demo" passes, "worst" fails with a RenderFlex overflow (the intended bug).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemberListView extends StatelessWidget {
  const MemberListView({super.key, required this.members});
  final List<String> members;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView.builder(
          itemCount: members.length,
          itemBuilder: (_, i) => Row(children: [
            const SizedBox(width: 40, height: 40),
            Text(members[i]), // BUG: no Expanded
            const Icon(Icons.more_horiz),
          ]),
        ),
      );
}

final fixtures = <(String, List<String>)>[
  ('demo', ['Jane Doe']),
  ('worst', ['bartholomew.fitzgerald@northwind-industries-holdings.example.com']),
];

void main() {
  const sizes = [Size(320, 640)];
  const scales = [1.0];
  for (final size in sizes) {
    for (final scale in scales) {
      for (final (name, data) in fixtures) {
        testWidgets('$name @ ${size.width.toInt()}w x$scale', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
              child: MemberListView(members: data),
            ),
          ));
          await tester.pumpAndSettle();
        });
      }
    }
  }
}
