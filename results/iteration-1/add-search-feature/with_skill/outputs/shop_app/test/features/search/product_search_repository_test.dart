import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shop_app/features/search/data/product_search_repository.dart';

void main() {
  ProductSearchRepository repoWith(MockClientHandler handler) =>
      ProductSearchRepository(
        baseUrl: 'https://api.example.com/v1',
        client: MockClient(handler),
      );

  test('calls GET /products?q= with an encoded query and parses results',
      () async {
    late Uri requested;
    final repo = repoWith((request) async {
      requested = request.url;
      return http.Response(
        '[{"id": 7, "name": "Red shoe", "price": 1299}]',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    final products = await repo.search('red & blue');

    expect(requested.path, '/v1/products');
    expect(requested.queryParameters, {'q': 'red & blue'});
    expect(products, hasLength(1));
    expect(products.single.id, '7');
    expect(products.single.name, 'Red shoe');
    expect(products.single.price, 1299.0);
  });

  test('accepts a {"products": [...]} envelope', () async {
    final repo = repoWith((_) async => http.Response(
          '{"products": [{"id": "a", "name": "Hat", "price": 9.5}]}',
          200,
        ));
    expect((await repo.search('hat')).single.name, 'Hat');
  });

  test('throws ProductSearchException on a non-200 status', () {
    final repo = repoWith((_) async => http.Response('oops', 500));
    expect(repo.search('x'), throwsA(isA<ProductSearchException>()));
  });

  test('throws ProductSearchException on malformed JSON', () {
    final repo = repoWith((_) async => http.Response('{"nope": 1}', 200));
    expect(repo.search('x'), throwsA(isA<ProductSearchException>()));
  });

  test('throws ProductSearchException on network failure', () {
    final repo = repoWith((_) async => throw http.ClientException('offline'));
    expect(repo.search('x'), throwsA(isA<ProductSearchException>()));
  });
}
