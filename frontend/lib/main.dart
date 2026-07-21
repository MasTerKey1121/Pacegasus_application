import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_theme.dart';
import 'screens/auth/login_screen.dart';

void main() {
  runApp(const ProviderScope(child: PacegasusApp()));
}

class PacegasusApp extends StatelessWidget {
  const PacegasusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pacegasus',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const LoginScreen(),
    );
  }
}
