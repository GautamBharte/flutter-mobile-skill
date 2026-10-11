import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shop_app/features/cart/cubit/cart_cubit.dart';
import 'package:shop_app/features/search/data/product_search_repository.dart';
import 'package:shop_app/features/search/view/search_page.dart';

void main() {
  testWidgets('typing shows results and add-to-cart updates CartCubit',
      (tester) async {
    final cart = CartCubit();
    final repo = ProductSearchRepository(
      baseUrl: 'https://x.test/v1',
      client: MockClient((req) async => http.Response(
            jsonEncode([
              {'id': 1, 'name': 'Blue Kettle', 'price': 899},
            ]),
            200,
          )),
    );

    await tester.pumpWidget(BlocProvider.value(
      value: cart,
      child: MaterialApp(home: SearchPage(repository: repo)),
    ));

    expect(find.text('Start typing to search products'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'kettle');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();

    expect(find.text('Blue Kettle'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to cart'));
    await tester.pump();
    expect(cart.state.items.single.name, 'Blue Kettle');

    await cart.close();
  });

  testWidgets('shows empty state when nothing matches', (tester) async {
    final repo = ProductSearchRepository(
      baseUrl: 'https://x.test/v1',
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    await tester.pumpWidget(BlocProvider(
      create: (_) => CartCubit(),
      child: MaterialApp(home: SearchPage(repository: repo)),
    ));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.textContaining('No products match'), findsOneWidget);
  });
}
