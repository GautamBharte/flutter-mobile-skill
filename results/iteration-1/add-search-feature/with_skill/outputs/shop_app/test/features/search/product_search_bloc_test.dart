import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shop_app/features/cart/cubit/cart_cubit.dart';
import 'package:shop_app/features/search/bloc/product_search_bloc.dart';
import 'package:shop_app/features/search/data/product_search_repository.dart';

class _MockRepo extends Mock implements ProductSearchRepository {}

void main() {
  late ProductSearchRepository repo;
  final shoe = Product('1', 'Running shoe', 2499);
  final sock = Product('2', 'Sock', 199);
  const wait = Duration(milliseconds: 350); // > searchDebounce

  setUp(() => repo = _MockRepo());

  test('initial state is empty', () {
    expect(ProductSearchBloc(repo).state, const ProductSearchState());
  });

  blocTest<ProductSearchBloc, ProductSearchState>(
    'emits [loading, success] when search succeeds',
    setUp: () =>
        when(() => repo.search('shoe')).thenAnswer((_) async => [shoe]),
    build: () => ProductSearchBloc(repo),
    act: (bloc) => bloc.add(const SearchQueryChanged('  shoe ')),
    wait: wait,
    expect: () => [
      const ProductSearchState(
        status: ProductSearchStatus.loading,
        query: 'shoe',
      ),
      ProductSearchState(
        status: ProductSearchStatus.success,
        query: 'shoe',
        products: [shoe],
      ),
    ],
  );

  blocTest<ProductSearchBloc, ProductSearchState>(
    'emits [loading, failure] when the repository throws',
    setUp: () => when(() => repo.search('shoe'))
        .thenThrow(const ProductSearchException('offline')),
    build: () => ProductSearchBloc(repo),
    act: (bloc) => bloc.add(const SearchQueryChanged('shoe')),
    wait: wait,
    expect: () => [
      const ProductSearchState(
        status: ProductSearchStatus.loading,
        query: 'shoe',
      ),
      const ProductSearchState(
        status: ProductSearchStatus.failure,
        query: 'shoe',
        errorMessage: 'offline',
      ),
    ],
  );

  blocTest<ProductSearchBloc, ProductSearchState>(
    'debounces fast typing into a single request for the last query',
    setUp: () => when(() => repo.search(any())).thenAnswer((_) async => [sock]),
    build: () => ProductSearchBloc(repo),
    act: (bloc) => bloc
      ..add(const SearchQueryChanged('s'))
      ..add(const SearchQueryChanged('so'))
      ..add(const SearchQueryChanged('sock')),
    wait: wait,
    expect: () => [
      const ProductSearchState(
        status: ProductSearchStatus.loading,
        query: 'sock',
      ),
      ProductSearchState(
        status: ProductSearchStatus.success,
        query: 'sock',
        products: [sock],
      ),
    ],
    verify: (_) {
      verify(() => repo.search('sock')).called(1);
      verifyNoMoreInteractions(repo);
    },
  );

  blocTest<ProductSearchBloc, ProductSearchState>(
    'resets to initial without a request when the query is cleared',
    build: () => ProductSearchBloc(repo),
    seed: () => ProductSearchState(
      status: ProductSearchStatus.success,
      query: 'shoe',
      products: [shoe],
    ),
    act: (bloc) => bloc.add(const SearchQueryChanged('   ')),
    wait: wait,
    expect: () => [const ProductSearchState()],
    verify: (_) => verifyNever(() => repo.search(any())),
  );

  blocTest<ProductSearchBloc, ProductSearchState>(
    'does not refetch when the trimmed query has not changed',
    build: () => ProductSearchBloc(repo),
    seed: () => ProductSearchState(
      status: ProductSearchStatus.success,
      query: 'shoe',
      products: [shoe],
    ),
    act: (bloc) => bloc.add(const SearchQueryChanged('shoe ')),
    wait: wait,
    expect: () => <ProductSearchState>[],
    verify: (_) => verifyNever(() => repo.search(any())),
  );

  blocTest<ProductSearchBloc, ProductSearchState>(
    'drops results of an older request when a newer query arrives',
    setUp: () {
      when(() => repo.search('shoe')).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return [shoe];
      });
      when(() => repo.search('sock')).thenAnswer((_) async => [sock]);
    },
    build: () => ProductSearchBloc(repo),
    act: (bloc) async {
      bloc.add(const SearchQueryChanged('shoe'));
      await Future<void>.delayed(wait); // 'shoe' request is now in flight
      bloc.add(const SearchQueryChanged('sock'));
    },
    wait: const Duration(milliseconds: 900),
    expect: () => [
      const ProductSearchState(
        status: ProductSearchStatus.loading,
        query: 'shoe',
      ),
      const ProductSearchState(
        status: ProductSearchStatus.loading,
        query: 'sock',
      ),
      ProductSearchState(
        status: ProductSearchStatus.success,
        query: 'sock',
        products: [sock],
      ),
    ],
  );
}
