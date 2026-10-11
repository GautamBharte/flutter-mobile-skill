import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../cart/cubit/cart_cubit.dart' show Product;

/// Thrown when a search request fails. [message] is safe to show to the user.
class ProductSearchException implements Exception {
  const ProductSearchException(this.message);

  final String message;

  @override
  String toString() => 'ProductSearchException: $message';
}

/// Talks to `GET $baseUrl/products?q=<query>` and returns [Product]s.
class ProductSearchRepository {
  ProductSearchRepository({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  Future<List<Product>> search(String query) async {
    // Uri.replace encodes the query, so "red shoes & socks" is sent safely.
    final uri =
        Uri.parse('$_baseUrl/products').replace(queryParameters: {'q': query});

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ProductSearchException(
          'The search took too long. Try again.');
    } on http.ClientException {
      throw const ProductSearchException(
        'Could not reach the server. Check your connection.',
      );
    }

    if (response.statusCode != 200) {
      throw ProductSearchException(
        'Search failed (error ${response.statusCode}). Try again.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      // Accept either a bare list or { "products": [...] }.
      final list = decoded is Map<String, dynamic>
          ? decoded['products'] as List<dynamic>
          : decoded as List<dynamic>;
      return [
        for (final item in list) _productFromJson(item as Map<String, dynamic>),
      ];
    } on Object catch (_) {
      // FormatException from jsonDecode, or TypeError from an unexpected shape.
      throw const ProductSearchException('Got an unexpected response.');
    }
  }

  Product _productFromJson(Map<String, dynamic> json) => Product(
        json['id'].toString(),
        json['name'] as String,
        (json['price'] as num).toDouble(),
      );
}
