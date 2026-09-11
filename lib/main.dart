// Entry point por defecto usado por `flutter run` sin --target explícito
// (IDEs, `flutter test`, etc.). Equivale a main_dev.dart.
import 'package:sinapsis/bootstrap.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';

Future<void> main() async {
  EnvConfig.initialize(AppFlavor.dev);
  await bootstrap();
}
