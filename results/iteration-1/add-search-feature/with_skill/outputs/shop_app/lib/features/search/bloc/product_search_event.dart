part of 'product_search_bloc.dart';

sealed class ProductSearchEvent extends Equatable {
  const ProductSearchEvent();

  @override
  List<Object?> get props => [];
}

/// The text in the search box changed (also used by the Retry button).
final class SearchQueryChanged extends ProductSearchEvent {
  const SearchQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}
