import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../main.dart' show baseUrl;
import '../../cart/cubit/cart_cubit.dart';
import '../bloc/search_bloc.dart';
import '../data/product_search_repository.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.repository});

  /// Injectable for tests; defaults to a real HTTP-backed repository.
  final ProductSearchRepository? repository;

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const SearchPage());

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final ProductSearchRepository _repository =
      widget.repository ?? ProductSearchRepository(baseUrl: baseUrl);

  @override
  void dispose() {
    // Only close the HTTP client if this page created it.
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchBloc(repository: _repository),
      child: const SearchView(),
    );
  }
}

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // refresh clear-button visibility
    context.read<SearchBloc>().add(SearchQueryChanged(value));
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search products',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear),
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) => switch (state.status) {
          SearchStatus.initial => const _Message(
              icon: Icons.search,
              text: 'Start typing to search products',
            ),
          SearchStatus.loading when state.results.isEmpty =>
            const Center(child: CircularProgressIndicator()),
          SearchStatus.failure => _Message(
              icon: Icons.error_outline,
              text: 'Couldn’t load results',
              action: TextButton(
                onPressed: () =>
                    context.read<SearchBloc>().add(const SearchRetried()),
                child: const Text('Retry'),
              ),
            ),
          SearchStatus.success when state.results.isEmpty => _Message(
              icon: Icons.search_off,
              text: 'No products match “${state.query}”',
            ),
          _ => Column(
              children: [
                if (state.status == SearchStatus.loading)
                  const LinearProgressIndicator(minHeight: 2),
                Expanded(child: _Results(products: state.results)),
              ],
            ),
        },
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: products.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = products[i];
        return ListTile(
          title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('₹${p.price.toStringAsFixed(2)}'),
          trailing: IconButton(
            tooltip: 'Add to cart',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () {
              context.read<CartCubit>().add(p);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text('Added ${p.name} to cart')),
                );
            },
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
