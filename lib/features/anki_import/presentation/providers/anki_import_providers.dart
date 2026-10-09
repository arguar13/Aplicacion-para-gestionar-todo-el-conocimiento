import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/anki_import/data/repositories/anki_import_repository_impl.dart';
import 'package:sinapsis/features/anki_import/data/services/isolate_anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/data/services/system_apkg_file_chooser.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/repositories/anki_import_repository.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/services/apkg_file_chooser.dart';
import 'package:sinapsis/features/anki_import/domain/usecases/import_anki_package_usecase.dart';
import 'package:sinapsis/features/capture/domain/services/file_chooser.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';

/// El selector del `.apkg`.
final apkgFileChooserProvider = Provider<ApkgFileChooser>(
  (ref) => const SystemApkgFileChooser(),
);

/// Quien lee el `.apkg`, en otro isolate para no congelar la pantalla.
final ankiPackageReaderProvider = Provider<AnkiPackageReader>(
  (ref) => const IsolateAnkiPackageReader(),
);

final ankiImportRepositoryProvider = Provider<AnkiImportRepository>(
  (ref) => AnkiImportRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final importAnkiPackageProvider = Provider<ImportAnkiPackageUseCase>(
  (ref) => ImportAnkiPackageUseCase(
    repository: ref.watch(ankiImportRepositoryProvider),
    library: ref.watch(libraryRepositoryProvider),
    organize: ref.watch(organizeRepositoryProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Dónde está la importación de Anki, de punta a punta.
@immutable
sealed class AnkiImportState {
  const AnkiImportState();
}

/// Todavía no se eligió ningún archivo.
class AnkiImportIdle extends AnkiImportState {
  const AnkiImportIdle();
}

/// Se está leyendo el archivo elegido.
class AnkiImportReading extends AnkiImportState {
  const AnkiImportReading();
}

/// El archivo se leyó: se muestra qué trae y se elige dónde cae.
class AnkiImportReady extends AnkiImportState {
  const AnkiImportReady({
    required this.package,
    required this.preview,
    required this.destination,
  });

  final AnkiImportedPackage package;
  final AnkiImportPreview preview;
  final AnkiImportDestination destination;

  AnkiImportReady withDestination(AnkiImportDestination destination) =>
      AnkiImportReady(
        package: package,
        preview: preview,
        destination: destination,
      );
}

/// Se están escribiendo las tarjetas.
class AnkiImportRunning extends AnkiImportState {
  const AnkiImportRunning({required this.done, required this.total});

  final int done;
  final int total;
}

/// Terminó bien.
class AnkiImportDone extends AnkiImportState {
  const AnkiImportDone(this.report);

  final AnkiImportReport report;
}

/// No se pudo: por un archivo que no se sabe leer ([exception]) o por un fallo
/// al escribir ([failure]). Si falló al escribir, no quedó nada a medias.
class AnkiImportFailed extends AnkiImportState {
  const AnkiImportFailed({this.exception, this.failure});

  final AnkiImportException? exception;
  final Failure? failure;
}

/// Maneja la importación de Anki que muestra su pantalla: elegir el archivo,
/// leerlo, mostrar qué trae, y traerlo.
class AnkiImportNotifier extends AutoDisposeNotifier<AnkiImportState> {
  @override
  AnkiImportState build() => const AnkiImportIdle();

  /// Abre el selector y lee lo que se elija. Cancelarlo deja todo como estaba.
  Future<void> pickAndRead() async {
    final chooser = ref.read(apkgFileChooserProvider);
    final String? path;
    try {
      path = await chooser.pick();
    } on FileAccessDeniedException {
      state = const AnkiImportFailed(
        exception: AnkiImportException(
          AnkiImportFailure.unreadable,
          'No hay permiso para leer los archivos del dispositivo.',
        ),
      );
      return;
    }
    if (path == null) return;

    state = const AnkiImportReading();
    try {
      final package = await ref.read(ankiPackageReaderProvider).readFile(path);
      final preview = await ref
          .read(importAnkiPackageProvider)
          .preview(package);
      state = AnkiImportReady(
        package: package,
        preview: preview,
        destination: AnkiImportDestination.perDeck,
      );
    } on AnkiImportException catch (e) {
      state = AnkiImportFailed(exception: e);
    } finally {
      await chooser.release();
    }
  }

  void chooseDestination(AnkiImportDestination destination) {
    final current = state;
    if (current is AnkiImportReady) {
      state = current.withDestination(destination);
    }
  }

  /// Escribe el paquete leído en el destino elegido.
  Future<void> start() async {
    final current = state;
    if (current is! AnkiImportReady) return;

    state = const AnkiImportRunning(done: 0, total: 0);
    final result = await ref
        .read(importAnkiPackageProvider)
        .import(
          current.package,
          destination: current.destination,
          onProgress: (done, total) =>
              state = AnkiImportRunning(done: done, total: total),
        );
    state = result.match(
      (failure) => AnkiImportFailed(failure: failure),
      AnkiImportDone.new,
    );
  }

  /// Vuelve al principio, para elegir otro archivo.
  void reset() => state = const AnkiImportIdle();
}

final ankiImportProvider =
    NotifierProvider.autoDispose<AnkiImportNotifier, AnkiImportState>(
      AnkiImportNotifier.new,
    );
