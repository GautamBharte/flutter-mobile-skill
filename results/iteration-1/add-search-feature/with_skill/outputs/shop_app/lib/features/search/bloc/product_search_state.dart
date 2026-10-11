part of 'product_search_bloc.dart';

enum ProductSearchStatus { initial, loading, success, failure }

final class ProductSearchState extends Equatable {
  const ProductSearchState({
    this.status = ProductSearchStatus.initial,
    this.query = '',
    this.products = const [],
    this.errorMessage,
  });

  final ProductSearchStatus status;

  /// The trimmed query that [products] / [errorMessage] belong to.
  final String query;
  final List<Product> products;
  final String? errorMessage;

  ProductSearchState copyWith({
    ProductSearchStatus? status,
    String? query,
    List<Product>? products,
    String? Function()? errorMessage,
  }) {
    return ProductSearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      products: products ?? this.products,
      // A function so callers can explicitly clear it with `() => null`.
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, query, products, errorMessage];
}
