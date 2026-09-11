import 'package:sinapsis/bootstrap.dart';
import 'package:sinapsis/core/config/app_flavor.dart';
import 'package:sinapsis/core/config/env_config.dart';

Future<void> main() async {
  EnvConfig.initialize(AppFlavor.prod);
  await bootstrap();
}
