import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shop_app/features/search/bloc/search_bloc.dart';
import 'package:shop_app/features/search/data/product_search_repository.dart';

const _debounce = Duration(milliseconds: 20);

ProductSearchRepository _repo(MockClientHandler handler) =>
    ProductSearchRepository(baseUrl: 'https://x.test/v1', client: MockClient(handler));

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  group('ProductSearchRepository', () {
    test('calls /products with encoded q and parses list', () async {
      late Uri requested;
      final repo = _repo((req) async {
        requested = req.url;
        return _json([
          {'id': 1, 'name': 'Tea & Biscuits', 'price': 49.5},
          {'id': '2', 'name': 'Bad', 'price': null}, // dropped
        ]);
      });
      final res = await repo.search('tea & b');
      expect(requested.path, '/v1/products');
      expect(requested.queryParameters['q'], 'tea & b');
      expect(res.single.id, '1');
      expect(res.single.price, 49.5);
    });

    test('accepts {"products": [...]} envelope', () async {
      final repo = _repo((_) async => _json({
            'products': [
              {'id': 'a', 'name': 'Mug', 'price': '199'}
            ]
          }));
      expect((await repo.search('mug')).single.name, 'Mug');
    });

    test('throws on non-200', () {
      final repo = _repo((_) async => http.Response('nope', 500));
      expect(repo.search('x'), throwsA(isA<ProductSearchException>()));
    });
  });

  group('SearchBloc', () {
    test('debounces keystrokes into a single request', () async {
      final queries = <String>[];
      final bloc = SearchBloc(
        debounce: _debounce,
        repository: _repo((req) async {
          queries.add(req.url.queryParameters['q']!);
          return _json([
            {'id': 1, 'name': 'Shoe', 'price': 10}
          ]);
        }),
      );
      bloc
        ..add(const SearchQueryChanged('s'))
        ..add(const SearchQueryChanged('sh'))
        ..add(const SearchQueryChanged('sho'));
      await _settle();
      expect(queries, ['sho']);
      expect(bloc.state.status, SearchStatus.success);
      expect(bloc.state.results.single.name, 'Shoe');
      await bloc.close();
    });

    test('stale response does not overwrite newer query', () async {
      final slow = Completer<http.Response>();
      final bloc = SearchBloc(
        debounce: _debounce,
        repository: _repo((req) {
          final q = req.url.queryParameters['q'];
          if (q == 'old') return slow.future;
          return Future.value(_json([
            {'id': 2, 'name': 'New', 'price': 1}
          ]));
        }),
      );
      bloc.add(const SearchQueryChanged('old'));
      await _settle(); // 'old' request now in flight
      bloc.add(const SearchQueryChanged('new'));
      await _settle();
      slow.complete(_json([
        {'id': 1, 'name': 'Old', 'price': 1}
      ]));
      await _settle();
      expect(bloc.state.query, 'new');
      expect(bloc.state.results.single.name, 'New');
      await bloc.close();
    });

    test('empty query resets to initial without a request', () async {
      var calls = 0;
      final bloc = SearchBloc(
        debounce: _debounce,
        repository: _repo((_) async {
          calls++;
          return _json([]);
        }),
      );
      bloc.add(const SearchQueryChanged('   '));
      await _settle();
      expect(calls, 0);
      expect(bloc.state.status, SearchStatus.initial);
      await bloc.close();
    });

    test('failure then retry succeeds', () async {
      var fail = true;
      final bloc = SearchBloc(
        debounce: _debounce,
        repository: _repo((_) async => fail
            ? http.Response('err', 503)
            : _json([
                {'id': 1, 'name': 'Hat', 'price': 5}
              ])),
      );
      bloc.add(const SearchQueryChanged('hat'));
      await _settle();
      expect(bloc.state.status, SearchStatus.failure);
      fail = false;
      bloc.add(const SearchRetried());
      await _settle();
      expect(bloc.state.status, SearchStatus.success);
      expect(bloc.state.results.single.name, 'Hat');
      await bloc.close();
    });
  });
}
