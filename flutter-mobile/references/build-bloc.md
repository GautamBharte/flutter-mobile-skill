# Build mode (BLoC / Cubit)

Goal: write feature code that compiles, matches the project's existing style, and is easy to test. When the project already has a convention that differs from this file, **follow the project** — consistency beats this guide.

## Cubit or Bloc?

- **Cubit** for most screens: simple methods (`load()`, `toggleFavorite(id)`), less boilerplate. Default to this.
- **Bloc** when you need event transformers (debounce search, `droppable` for submit buttons, `restartable` for latest-wins), or an explicit event log is valuable.

## Feature folder layout

```
lib/features/<feature>/
  data/
    <feature>_repository.dart      # talks to API/DB, returns domain models, throws typed exceptions
    models/<model>.dart
  bloc/   (or cubit/)
    <feature>_cubit.dart
    <feature>_state.dart
  view/
    <feature>_page.dart            # provides the cubit (BlocProvider)
    <feature>_view.dart            # consumes it (BlocBuilder / BlocListener)
    widgets/...
test/features/<feature>/...
```

Splitting Page (provides) from View (consumes) means the View can be tested with a mock cubit.

## State

Prefer a single state class with a status enum — easy to copy, works with `buildWhen`:

```dart
enum TodosStatus { initial, loading, success, failure }

final class TodosState extends Equatable {
  const TodosState({
    this.status = TodosStatus.initial,
    this.todos = const [],
    this.errorMessage,
  });

  final TodosStatus status;
  final List<Todo> todos;
  final String? errorMessage;

  TodosState copyWith({
    TodosStatus? status,
    List<Todo>? todos,
    String? errorMessage,
  }) {
    return TodosState(
      status: status ?? this.status,
      todos: todos ?? this.todos,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, todos, errorMessage];
}
```

Sealed classes (`sealed class TodosState`, `TodosLoading`, `TodosLoaded`…) are fine too, and nice with `switch` pattern matching — use them if the project already does. If the project uses `freezed`, use freezed.

Always emit **new** collections: `emit(state.copyWith(todos: [...state.todos, todo]))`, never mutate `state.todos`.

## Cubit

```dart
class TodosCubit extends Cubit<TodosState> {
  TodosCubit(this._repository) : super(const TodosState());

  final TodosRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: TodosStatus.loading));
    try {
      final todos = await _repository.fetchTodos();
      emit(state.copyWith(status: TodosStatus.success, todos: todos));
    } on TodosException catch (e) {
      emit(state.copyWith(status: TodosStatus.failure, errorMessage: e.message));
    }
  }
}
```

Catch typed exceptions from the repository; let truly unexpected errors surface (they'll reach `BlocObserver.onError` and crash reporting).

## Bloc with transformers

```dart
// pubspec: bloc_concurrency, stream_transform
EventTransformer<E> debounceRestartable<E>(Duration d) =>
    (events, mapper) => restartable<E>().call(events.debounce(d), mapper);

on<SearchQueryChanged>(_onQueryChanged,
    transformer: debounceRestartable(const Duration(milliseconds: 300)));
on<CheckoutSubmitted>(_onSubmit, transformer: droppable()); // ignore double-taps
```

## UI wiring

```dart
class TodosPage extends StatelessWidget {
  const TodosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TodosCubit(context.read<TodosRepository>())..load(),
      child: const TodosView(),
    );
  }
}

class TodosView extends StatelessWidget {
  const TodosView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TodosCubit, TodosState>(
      listenWhen: (p, c) => p.status != c.status && c.status == TodosStatus.failure,
      listener: (context, state) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(state.errorMessage ?? 'Something went wrong'))),
      builder: (context, state) => switch (state.status) {
        TodosStatus.initial || TodosStatus.loading =>
          const Center(child: CircularProgressIndicator.adaptive()),
        TodosStatus.failure when state.todos.isEmpty =>
          _ErrorRetry(onRetry: context.read<TodosCubit>().load),
        _ => RefreshIndicator.adaptive(
            onRefresh: context.read<TodosCubit>().load,
            child: ListView.builder(
              itemCount: state.todos.length,
              itemBuilder: (context, i) => TodoTile(todo: state.todos[i]),
            ),
          ),
      },
    );
  }
}
```

Key points: side effects (snackbar, navigation) in `listener`, never in `builder`; `context.read` for calling methods, `context.watch`/`BlocBuilder`/`BlocSelector` for rebuilding; every screen handles loading, empty, error, and success.

Provide repositories app-wide with `RepositoryProvider` / `MultiRepositoryProvider` near `MaterialApp` (or get_it, if the project uses it).

## Tests

Every cubit/bloc you write gets `bloc_test` tests covering success and failure. Use `mocktail` for repositories.

```dart
class _MockRepo extends Mock implements TodosRepository {}

void main() {
  late TodosRepository repo;
  setUp(() => repo = _MockRepo());

  blocTest<TodosCubit, TodosState>(
    'emits [loading, success] when fetch succeeds',
    setUp: () => when(() => repo.fetchTodos()).thenAnswer((_) async => [todo]),
    build: () => TodosCubit(repo),
    act: (cubit) => cubit.load(),
    expect: () => [
      const TodosState(status: TodosStatus.loading),
      TodosState(status: TodosStatus.success, todos: [todo]),
    ],
  );
}
```

## Finishing

1. Add any new dependencies with `flutter pub add <pkg>` (don't invent version numbers).
2. Run `flutter analyze` and `flutter test`; fix what you broke.
3. Tell the user which files you created, how the pieces connect, and anything they must do manually (e.g. add a route, add a permission string).
