import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../cart/view/cart_page.dart';

class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;

  Future<void> _login() async {
    setState(() => loading = true);
    final res = await http.post(Uri.parse('$baseUrl/login'),
        body: {'email': emailController.text, 'password': passwordController.text});
    final data = jsonDecode(res.body);
    print('login response: $data');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token']);
    setState(() => loading = false);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const CartPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: emailController, decoration: InputDecoration(labelText: 'Email')),
            TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Password')),
            SizedBox(height: 24),
            GestureDetector(
              onTap: loading ? null : _login,
              child: Container(
                height: 36,
                color: Colors.blue,
                alignment: Alignment.center,
                child: loading ? CircularProgressIndicator() : Text('Login', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
