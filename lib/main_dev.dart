import 'package:cristo_es_el_salvador/bootstrap.dart';
import 'package:cristo_es_el_salvador/core/config/app_flavor.dart';
import 'package:cristo_es_el_salvador/core/config/env_config.dart';

Future<void> main() async {
  EnvConfig.initialize(AppFlavor.dev);
  await bootstrap();
}
