import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_backfill.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_backfill_keeper.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_indexer.dart';
import 'package:sinapsis/features/processed/domain/services/headings/headings_extractor.dart';
import 'package:sinapsis/features/processed/presentation/providers/pdf_outline_providers.dart';

/// De dónde salen los títulos de un documento procesado para el Índice (F46):
/// el lector del paso 1, en otro hilo si el texto es largo.
final headingsExtractorProvider = Provider<HeadingsExtractor>(
  (ref) => const ReadingHeadingsExtractor(),
);

/// Quien escribe las entradas de texto del Índice con el texto de cada
/// documento procesado, en la misma transacción (F46, paso 2).
final processedHeadingsIndexerProvider = Provider<ProcessedHeadingsIndexer>(
  (ref) => ProcessedHeadingsIndexer(
    database: ref.watch(appDatabaseProvider),
    extractor: ref.watch(headingsExtractorProvider),
    outlines: ref.watch(pdfOutlineReaderProvider),
    files: ref.watch(fileStoreProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// El relleno del Índice: lo que quedó sin indexar y las imágenes sin titular.
final processedHeadingsBackfillProvider = Provider<ProcessedHeadingsBackfill>(
  (ref) => ProcessedHeadingsBackfill(
    database: ref.watch(appDatabaseProvider),
    indexer: ref.watch(processedHeadingsIndexerProvider),
  ),
);

/// Hace correr el relleno mientras viva: se lee una vez, al abrirse la bóveda
/// (`SinapsisApp`), y desde ahí mira la base solo.
final processedHeadingsBackfillKeeperProvider =
    Provider<ProcessedHeadingsBackfillKeeper>((ref) {
      final keeper = ProcessedHeadingsBackfillKeeper(
        database: ref.watch(appDatabaseProvider),
        backfill: ref.watch(processedHeadingsBackfillProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      )..start();
      ref.onDispose(() => unawaited(keeper.stop()));
      return keeper;
    });
