import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  File? _avatar;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera);
    if (x != null) setState(() => _avatar = File(x.path));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Opacity(
            opacity: 0.5 + _pulse.value / 2,
            child: GestureDetector(
              onTap: _pick,
              child: CircleAvatar(radius: 48, backgroundImage: _avatar != null ? FileImage(_avatar!) : null),
            ),
          ),
        ),
      ),
    );
  }
}
