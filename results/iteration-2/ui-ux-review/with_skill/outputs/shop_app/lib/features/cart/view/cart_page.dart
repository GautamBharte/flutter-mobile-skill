import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import '../../../main.dart';
import '../cubit/cart_cubit.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  Future<List<dynamic>> _recommendations() async {
    final res = await http.get(Uri.parse('$baseUrl/recommend?key=$apiKey'));
    return jsonDecode(res.body) as List<dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state.checkoutDone) {
            Navigator.of(context).pop();
          }
          return Column(
            children: [
              ...state.items.map((p) => ListTile(title: Text(p.name), trailing: Text('₹${p.price}'))),
              Text('Total: ₹${state.total}', style: TextStyle(color: Colors.black)),
              FutureBuilder(
                future: _recommendations(),
                builder: (context, snap) {
                  if (!snap.hasData) return CircularProgressIndicator();
                  return Column(children: snap.data!.map((r) => Text(r['name'])).toList());
                },
              ),
              ElevatedButton(
                onPressed: () => context.read<CartCubit>().checkout(),
                child: Text('Checkout'),
              ),
            ],
          );
        },
      ),
    );
  }
}
