import 'package:flutter_bloc/flutter_bloc.dart';

class Product {
  Product(this.id, this.name, this.price);
  final String id;
  final String name;
  final double price;
}

class CartState {
  CartState({required this.items, this.checkoutDone = false});
  final List<Product> items;
  bool checkoutDone;
  double get total => items.fold(0, (s, p) => s + p.price);
}

class CartCubit extends Cubit<CartState> {
  CartCubit() : super(CartState(items: []));

  void add(Product p) {
    state.items.add(p);
    emit(state);
  }

  Future<void> checkout() async {
    await Future.delayed(const Duration(seconds: 2));
    emit(CartState(items: [], checkoutDone: true));
  }
}
