import 'package:flutter/material.dart';

/// Placeholder temporal para verificar que el router arranca. Se reemplaza
/// por la pantalla real del primer feature — no es diseño de UI definitivo.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(title)));
  }
}
