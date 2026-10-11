// Worst-case data harness for the Cart and Login screens.
//
// Test-only: nothing here ships. Each test asserts the behaviour a user would
// expect, so a RED test is a real break (see STRESS_TEST.md for the list).
// Layout errors such as `RenderFlex overflowed` fail the test automatically.
//
// Run: flutter test test/stress_test.dart
//
// Note: flutter_test blocks real network access — every http call gets an
// HTTP 400 with an empty body. That is exactly the "API error" worst case for
// the recommendations list and the login call, so it is used on purpose here.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/features/auth/login_page.dart';
import 'package:shop_app/features/cart/cubit/cart_cubit.dart';
import 'package:shop_app/features/cart/view/cart_page.dart';

// ---------------------------------------------------------------------------
// Fixtures (plausible values only — no "aaaa…" filler)
// ---------------------------------------------------------------------------

final demo = <Product>[
  Product('p1', 'Cotton T-shirt', 499),
  Product('p2', 'Coffee Mug', 249),
];

final worst = <Product>[
  // Long, realistic marketplace title (Indian e-commerce titles are often this long).
  Product(
    'p1',
    'Samsung Galaxy S24 Ultra 5G AI Smartphone (Titanium Gray, 12GB RAM, 256GB Storage) with 200MP Camera, S Pen Included',
    129999,
  ),
  // Large order value — needs lakh grouping: ₹1,23,45,678.90
  Product('p2', 'Bulk order: Office chairs ×120', 12345678.9),
  // Classic floating-point artefacts: 0.1 + 0.2.
  Product('p3', 'Sticker', 0.1),
  Product('p4', 'Sticker', 0.2),
  // Non-Latin, emoji, RTL, German compound.
  Product('p5', 'साड़ी — बनारसी रेशम (लाल)', 3499.5),
  Product('p6', '🎁 Gift wrap', 0),
  Product('p7', 'سماعات لاسلكية مع إلغاء الضوضاء', 7999),
  Product('p8', 'Kinderwagenregenschutzabdeckung', 1299),
  // Same product added twice (no quantity concept).
  Product('p8', 'Kinderwagenregenschutzabdeckung', 1299),
  // Negative price from a buggy discount line.
  Product('p9', 'Coupon WELCOME50', -50),
];

final one = <Product>[Product('p1', 'Pen', 10)];

final huge = List<Product>.generate(
  1000,
  (i) => Product('p$i', 'Item #${i + 1} — Basmati Rice 5 kg', 649),
);

final cartFixtures = <(String, List<Product>)>[
  ('demo', demo),
  ('worst', worst),
  ('empty', <Product>[]),
  ('one', one),
  ('huge', huge),
];

const sizes = [Size(320, 640), Size(375, 812), Size(430, 932), Size(1024, 768)];
const scales = [1.0, 1.3, 2.0];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void setView(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (keyboard > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  }
  addTearDown(tester.view.reset);
}

Widget app(Widget home, {double scale = 1.0, CartCubit? cubit}) {
  return BlocProvider<CartCubit>.value(
    value: cubit ?? CartCubit(),
    child: MaterialApp(
      // Keep the real view's insets (keyboard) and only override text scale.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

CartCubit cartWith(List<Product> items) {
  final c = CartCubit();
  for (final p in items) {
    c.add(p); // the real entry point the app uses
  }
  return c;
}

// ---------------------------------------------------------------------------
// Cart — layout matrix
// ---------------------------------------------------------------------------

void main() {
  group('Cart layout', () {
    for (final size in sizes) {
      for (final scale in scales) {
        for (final (name, data) in cartFixtures) {
          testWidgets('cart $name @ ${size.width.toInt()}w x$scale', (
            tester,
          ) async {
            setView(tester, size);
            await tester.pumpWidget(
              app(const CartPage(), scale: scale, cubit: cartWith(data)),
            );
            // No pumpAndSettle: the recommendations spinner never stops (see
            // 'Cart states' below), so settle would time out.
            await tester.pump(const Duration(milliseconds: 500));
          });
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  // Cart — data & state behaviour
  // -------------------------------------------------------------------------

  group('Cart data', () {
    testWidgets('prices are formatted as money (no float artefacts)', (
      tester,
    ) async {
      setView(tester, const Size(430, 932));
      await tester.pumpWidget(
        app(
          const CartPage(),
          cubit: cartWith([Product('a', 'A', 0.1), Product('b', 'B', 0.2)]),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('0.30000000000000004'),
        findsNothing,
        reason: 'Total renders raw double.toString()',
      );
    });

    testWidgets('whole-rupee price does not render as "₹499.0"', (
      tester,
    ) async {
      setView(tester, const Size(430, 932));
      await tester.pumpWidget(app(const CartPage(), cubit: cartWith(demo)));
      await tester.pump();
      expect(find.text('₹499.0'), findsNothing);
    });

    testWidgets('large amount uses Indian digit grouping', (tester) async {
      setView(tester, const Size(430, 932));
      await tester.pumpWidget(
        app(
          const CartPage(),
          cubit: cartWith([Product('a', 'Bulk', 12345678.9)]),
        ),
      );
      await tester.pump();
      expect(find.textContaining('1,23,45,678.90'), findsWidgets);
    });

    testWidgets('empty cart shows an empty state, not "Total: ₹0.0"', (
      tester,
    ) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(const CartPage(), cubit: cartWith([])));
      await tester.pump();
      expect(find.text('Total: ₹0.0'), findsNothing);
    });

    testWidgets('empty cart cannot start checkout', (tester) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(const CartPage(), cubit: cartWith([])));
      await tester.pump();
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(
        button.onPressed,
        isNull,
        reason: 'Checkout is enabled with 0 items',
      );
    });

    testWidgets('adding an item while the cart is open shows it', (
      tester,
    ) async {
      setView(tester, const Size(375, 812));
      // Start with items, as a real session would: the cubit has already
      // emitted once, so Bloc's "same state instance" check now drops emits.
      final cubit = cartWith(demo);
      await tester.pumpWidget(app(const CartPage(), cubit: cubit));
      await tester.pump();
      cubit.add(Product('x', 'Wireless Mouse', 799));
      await tester.pump();
      expect(
        find.text('Wireless Mouse'),
        findsOneWidget,
        reason: 'add() mutates state.items and re-emits the same instance',
      );
    });

    testWidgets(
      'recommendations API error shows an error/retry, not an endless spinner',
      (tester) async {
        setView(tester, const Size(375, 812));
        await tester.pumpWidget(app(const CartPage(), cubit: cartWith(demo)));
        await tester.pump(const Duration(seconds: 5));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('checkout shows progress and blocks a double tap', (
      tester,
    ) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(const CartPage(), cubit: cartWith(demo)));
      await tester.pump();
      await tester.tap(find.text('Checkout'));
      await tester.pump(const Duration(milliseconds: 100));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(
        button.onPressed,
        isNull,
        reason: 'Button stays enabled for the full 2 s checkout',
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('finishing checkout from the root cart route does not throw', (
      tester,
    ) async {
      // In the real app CartPage is the ONLY route (LoginPage uses
      // pushReplacement), and the cubit calls Navigator.pop() inside build.
      setView(tester, const Size(375, 812));
      final cubit = cartWith(demo);
      await tester.pumpWidget(app(const CartPage(), cubit: cubit));
      await tester.pump();
      await tester.tap(find.text('Checkout'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason: 'User should land on a success screen, not a blank one',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Login — layout matrix with nasty input and the keyboard open
  // -------------------------------------------------------------------------

  const longEmail =
      'bartholomew.fitzgerald+orders@northwind-industries-holdings.example.com';

  group('Login layout', () {
    for (final size in sizes) {
      for (final scale in scales) {
        for (final keyboard in [0.0, 336.0]) {
          final kb = keyboard > 0 ? 'keyboard' : 'no-keyboard';
          testWidgets('login @ ${size.width.toInt()}w x$scale $kb', (
            tester,
          ) async {
            setView(tester, size, keyboard: keyboard);
            await tester.pumpWidget(app(LoginPage(), scale: scale));
            await tester.enterText(find.byType(TextField).first, longEmail);
            await tester.enterText(
              find.byType(TextField).last,
              'pässwörd 🔐 with spaces',
            );
            await tester.pump();
          });
        }
      }
    }
  });

  group('Login behaviour', () {
    testWidgets('Login button: label fits and tap target is >= 48 dp at x2.0', (
      tester,
    ) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(LoginPage(), scale: 2.0));
      final label = tester.getSize(find.text('Login'));
      final box = tester.getSize(
        find
            .ancestor(of: find.text('Login'), matching: find.byType(Container))
            .first,
      );
      expect(label.height, lessThanOrEqualTo(box.height));
      expect(
        box.height,
        greaterThanOrEqualTo(48),
        reason: 'Tap target is 36 dp, below the 48 dp minimum',
      );
    });

    testWidgets('empty email + password is rejected before any network call', (
      tester,
    ) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(LoginPage()));
      await tester.tap(find.text('Login'));
      await tester.pump();
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'No validation — empty form goes straight to the API',
      );
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();
    });

    testWidgets('server error leaves the user able to retry', (tester) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(LoginPage()));
      await tester.enterText(find.byType(TextField).first, 'a@b.co');
      await tester.enterText(find.byType(TextField).last, 'x');
      await tester.tap(find.text('Login'));
      await tester.pump(const Duration(seconds: 2));
      final error = tester.takeException(); // jsonDecode('') on HTTP 400
      expect(
        error,
        isNull,
        reason: 'Unhandled ${error.runtimeType} on a non-200 response',
      );
      expect(
        find.text('Login'),
        findsOneWidget,
        reason: 'Spinner stays forever; button never comes back',
      );
    });

    testWidgets('email field uses the email keyboard and autofill', (
      tester,
    ) async {
      setView(tester, const Size(375, 812));
      await tester.pumpWidget(app(LoginPage()));
      final email = tester.widget<TextField>(find.byType(TextField).first);
      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.autofillHints, contains(AutofillHints.email));
    });
  });
}
