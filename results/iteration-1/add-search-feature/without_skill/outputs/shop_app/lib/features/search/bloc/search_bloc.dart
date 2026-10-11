import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cart/cubit/cart_cubit.dart';
import '../data/product_search_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class SearchEvent {
  const SearchEvent();
}

/// Fired on every keystroke. Debounced; in-flight searches for older queries
/// are cancelled so stale results never overwrite newer ones.
final class SearchQueryChanged extends SearchEvent {
  const SearchQueryChanged(this.query);
  final String query;
}

/// Re-runs the current query (e.g. "Retry" after an error). Not debounced.
final class SearchRetried extends SearchEvent {
  const SearchRetried();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum SearchStatus { initial, loading, success, failure }

final class SearchState {
  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.results = const [],
  });

  final SearchStatus status;
  final String query;
  final List<Product> results;

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<Product>? results,
  }) =>
      SearchState(
        status: status ?? this.status,
        query: query ?? this.query,
        results: results ?? this.results,
      );
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({
    required ProductSearchRepository repository,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _repository = repository,
        super(const SearchState()) {
    on<SearchQueryChanged>(
      _onQueryChanged,
      transformer: debounceRestartable(debounce),
    );
    on<SearchRetried>(_onRetried, transformer: restartable());
  }

  final ProductSearchRepository _repository;

  Future<void> _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query.trim();
    if (query == state.query && state.status == SearchStatus.success) return;
    await _search(query, emit);
  }

  Future<void> _onRetried(SearchRetried event, Emitter<SearchState> emit) =>
      _search(state.query, emit);

  Future<void> _search(String query, Emitter<SearchState> emit) async {
    if (query.isEmpty) {
      emit(const SearchState());
      return;
    }
    emit(state.copyWith(status: SearchStatus.loading, query: query));
    try {
      final results = await _repository.search(query);
      emit(SearchState(
        status: SearchStatus.success,
        query: query,
        results: results,
      ));
    } on ProductSearchException {
      emit(SearchState(status: SearchStatus.failure, query: query));
    }
  }
}

// ---------------------------------------------------------------------------
// Event transformers (kept local to avoid adding bloc_concurrency/rxdart).
// ---------------------------------------------------------------------------

/// Cancels the previous handler when a new event arrives (switchMap).
EventTransformer<E> restartable<E>() =>
    (events, mapper) => _switchMap(events, mapper);

/// Waits [duration] of quiet before handling the latest event, and cancels
/// any handler still running for an earlier event.
EventTransformer<E> debounceRestartable<E>(Duration duration) =>
    (events, mapper) => _switchMap(_debounce(events, duration), mapper);

Stream<T> _debounce<T>(Stream<T> source, Duration duration) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? timer;

  controller = StreamController<T>(
    sync: true,
    onListen: () {
      sub = source.listen(
        (e) {
          timer?.cancel();
          timer = Timer(duration, () => controller.add(e));
        },
        onError: controller.addError,
        onDone: () {
          // Flush nothing on close: pending debounced input is dropped.
          timer?.cancel();
          controller.close();
        },
      );
    },
    onCancel: () {
      timer?.cancel();
      return sub?.cancel();
    },
  );
  return controller.stream;
}

Stream<R> _switchMap<T, R>(Stream<T> source, Stream<R> Function(T) mapper) {
  late StreamController<R> controller;
  StreamSubscription<T>? outer;
  StreamSubscription<R>? inner;
  var outerDone = false;

  controller = StreamController<R>(
    sync: true,
    onListen: () {
      outer = source.listen(
        (e) {
          inner?.cancel();
          inner = mapper(e).listen(
            controller.add,
            onError: controller.addError,
            onDone: () {
              inner = null;
              if (outerDone) controller.close();
            },
          );
        },
        onError: controller.addError,
        onDone: () {
          outerDone = true;
          if (inner == null) controller.close();
        },
      );
    },
    onCancel: () async {
      await inner?.cancel();
      await outer?.cancel();
    },
  );
  return controller.stream;
}
