import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/auth/login_page.dart';
import 'features/cart/cubit/cart_cubit.dart';

const apiKey = 'DEMO_SECRET_KEY_NOT_REAL_123456';
const baseUrl = 'http://api.myshop.in/v1';

void main() {
  runApp(const ShopApp());
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: CartCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: true,
        title: 'Shop',
        home: LoginPage(),
      ),
    );
  }
}
