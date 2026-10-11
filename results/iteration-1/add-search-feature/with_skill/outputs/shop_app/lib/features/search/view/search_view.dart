import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cart/cubit/cart_cubit.dart' show Product;
import '../bloc/product_search_bloc.dart';

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

  void _onChanged(String text) {
    context.read<ProductSearchBloc>().add(SearchQueryChanged(text));
    setState(() {}); // show/hide the clear button
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
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
      body: BlocBuilder<ProductSearchBloc, ProductSearchState>(
        builder: (context, state) => switch (state.status) {
          ProductSearchStatus.initial => const _Message(
              icon: Icons.search,
              text: 'Start typing to search for products',
            ),
          ProductSearchStatus.loading when state.products.isEmpty =>
            const Center(child: CircularProgressIndicator.adaptive()),
          ProductSearchStatus.failure => _Message(
              icon: Icons.error_outline,
              text: state.errorMessage ?? 'Something went wrong',
              action: TextButton(
                onPressed: () => context
                    .read<ProductSearchBloc>()
                    .add(SearchQueryChanged(state.query)),
                child: const Text('Retry'),
              ),
            ),
          ProductSearchStatus.success when state.products.isEmpty => _Message(
              icon: Icons.search_off,
              text: 'No products found for "${state.query}"',
            ),
          _ => _Results(
              products: state.products,
              isRefreshing: state.status == ProductSearchStatus.loading,
            ),
        },
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.products, required this.isRefreshing});

  final List<Product> products;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Thin bar while a newer query loads, so old results don't vanish.
        SizedBox(
          height: 2,
          child: isRefreshing ? const LinearProgressIndicator() : null,
        ),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: products.length,
            itemBuilder: (context, i) {
              final product = products[i];
              return ListTile(
                title: Text(product.name),
                trailing: Text('₹${product.price.toStringAsFixed(2)}'),
              );
            },
          ),
        ),
      ],
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
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
