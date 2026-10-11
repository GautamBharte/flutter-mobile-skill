import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';

import '../../cart/cubit/cart_cubit.dart' show Product;
import '../data/product_search_repository.dart';

part 'product_search_event.dart';
part 'product_search_state.dart';

const searchDebounce = Duration(milliseconds: 300);

/// Waits until the user stops typing, then cancels any in-flight search so
/// only the latest query's results are ever shown.
EventTransformer<E> _debounceRestartable<E>(Duration duration) =>
    (events, mapper) =>
        restartable<E>().call(events.debounce(duration), mapper);

class ProductSearchBloc extends Bloc<ProductSearchEvent, ProductSearchState> {
  ProductSearchBloc(this._repository) : super(const ProductSearchState()) {
    on<SearchQueryChanged>(
      _onQueryChanged,
      transformer: _debounceRestartable(searchDebounce),
    );
  }

  final ProductSearchRepository _repository;

  Future<void> _onQueryChanged(
    SearchQueryChanged event,
    Emitter<ProductSearchState> emit,
  ) async {
    final query = event.query.trim();

    if (query.isEmpty) {
      emit(const ProductSearchState());
      return;
    }

    // e.g. user typed a trailing space: same results, no need to refetch.
    if (query == state.query && state.status == ProductSearchStatus.success) {
      return;
    }

    // Keep the previous results on screen while loading to avoid flicker.
    emit(state.copyWith(
      status: ProductSearchStatus.loading,
      query: query,
      errorMessage: () => null,
    ));

    try {
      final products = await _repository.search(query);
      emit(state.copyWith(
        status: ProductSearchStatus.success,
        products: products,
      ));
    } on ProductSearchException catch (e) {
      emit(state.copyWith(
        status: ProductSearchStatus.failure,
        products: const [],
        errorMessage: () => e.message,
      ));
    }
  }
}
