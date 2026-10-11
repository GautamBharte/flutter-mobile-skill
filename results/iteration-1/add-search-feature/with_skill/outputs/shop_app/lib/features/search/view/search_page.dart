import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/product_search_bloc.dart';
import '../data/product_search_repository.dart';
import 'search_view.dart';

/// Provides the [ProductSearchBloc]. Push with:
/// `Navigator.of(context).push(SearchPage.route())`.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const SearchPage());

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ProductSearchBloc(context.read<ProductSearchRepository>()),
      child: const SearchView(),
    );
  }
}
