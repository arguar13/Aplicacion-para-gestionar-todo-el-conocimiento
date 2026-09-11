import 'package:cristo_es_el_salvador/core/session/session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pantalla de arranque: no navega por sí misma. Solo dispara la lectura
/// del almacenamiento seguro; el router observa `sessionControllerProvider`
/// y decide a dónde ir en cuanto deja de estar en `unknown`.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(sessionControllerProvider.notifier).checkInitialSession();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
