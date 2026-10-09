import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/card_browser_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/card_browser_repository.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';

/// Mirar, buscar y ordenar todas las tarjetas (F31, ola 2, decisión 72).
final cardBrowserRepositoryProvider = Provider<CardBrowserRepository>((ref) {
  return CardBrowserRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    clock: ref.watch(clockProvider),
    resolver: ref.watch(studyScopeResolverProvider),
  );
});
