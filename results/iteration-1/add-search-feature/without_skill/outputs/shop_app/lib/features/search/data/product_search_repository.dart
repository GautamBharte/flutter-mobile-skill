import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../cart/cubit/cart_cubit.dart';

/// Thrown when the search request fails or returns an unexpected payload.
class ProductSearchException implements Exception {
  ProductSearchException(this.message);
  final String message;

  @override
  String toString() => 'ProductSearchException: $message';
}

/// Talks to `GET $baseUrl/products?q=<query>`.
class ProductSearchRepository {
  ProductSearchRepository({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  Future<List<Product>> search(String query) async {
    final uri = Uri.parse('$baseUrl/products')
        .replace(queryParameters: {'q': query});

    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on Exception catch (e) {
      throw ProductSearchException('Network error: $e');
    }

    if (res.statusCode != 200) {
      throw ProductSearchException('HTTP ${res.statusCode}');
    }

    final Object? body;
    try {
      body = jsonDecode(res.body);
    } on FormatException {
      throw ProductSearchException('Invalid JSON');
    }

    // Accept either a bare list or `{ "products": [...] }`.
    final List<dynamic>? list = switch (body) {
      List<dynamic> l => l,
      {'products': List<dynamic> l} => l,
      _ => null,
    };
    if (list == null) {
      throw ProductSearchException('Unexpected response shape');
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(_productFromJson)
        .whereType<Product>()
        .toList(growable: false);
  }

  static Product? _productFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final price = json['price'];
    if (id == null || name is! String) return null;
    final parsedPrice = switch (price) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    if (parsedPrice == null) return null;
    return Product(id.toString(), name, parsedPrice);
  }

  void dispose() => _client.close();
}
