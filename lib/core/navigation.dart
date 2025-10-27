import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

// Helper: navigate home by replacing the stack with HomeScreen
void goHome(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeScreen()),
    (route) => false,
  );
}
