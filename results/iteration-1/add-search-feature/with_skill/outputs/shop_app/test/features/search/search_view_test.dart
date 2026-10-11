import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shop_app/features/cart/cubit/cart_cubit.dart';
import 'package:shop_app/features/search/bloc/product_search_bloc.dart';
import 'package:shop_app/features/search/view/search_view.dart';

class _MockBloc extends MockBloc<ProductSearchEvent, ProductSearchState>
    implements ProductSearchBloc {}

void main() {
  late ProductSearchBloc bloc;

  setUp(() => bloc = _MockBloc());

  Widget app() => MaterialApp(
        home: BlocProvider.value(value: bloc, child: const SearchView()),
      );

  testWidgets('typing dispatches SearchQueryChanged', (tester) async {
    when(() => bloc.state).thenReturn(const ProductSearchState());
    await tester.pumpWidget(app());

    await tester.enterText(find.byType(TextField), 'shoe');

    verify(() => bloc.add(const SearchQueryChanged('shoe'))).called(1);
  });

  testWidgets('shows results', (tester) async {
    when(() => bloc.state).thenReturn(ProductSearchState(
      status: ProductSearchStatus.success,
      query: 'shoe',
      products: [Product('1', 'Running shoe', 2499)],
    ));
    await tester.pumpWidget(app());

    expect(find.text('Running shoe'), findsOneWidget);
    expect(find.text('₹2499.00'), findsOneWidget);
  });

  testWidgets('shows empty message', (tester) async {
    when(() => bloc.state).thenReturn(const ProductSearchState(
      status: ProductSearchStatus.success,
      query: 'zzz',
    ));
    await tester.pumpWidget(app());

    expect(find.text('No products found for "zzz"'), findsOneWidget);
  });

  testWidgets('shows error with retry', (tester) async {
    when(() => bloc.state).thenReturn(const ProductSearchState(
      status: ProductSearchStatus.failure,
      query: 'shoe',
      errorMessage: 'offline',
    ));
    await tester.pumpWidget(app());

    expect(find.text('offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    verify(() => bloc.add(const SearchQueryChanged('shoe'))).called(1);
  });
}
