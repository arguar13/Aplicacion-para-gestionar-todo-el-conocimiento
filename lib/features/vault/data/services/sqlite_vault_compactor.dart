import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/chunk_invariant_verifier.dart';
import 'package:sinapsis/core/database/vault_counts.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_assessment.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_progress.dart';
import 'package:sinapsis/features/vault/domain/entities/compaction_result.dart';
import 'package:sinapsis/features/vault/domain/services/compaction_advisor.dart';
import 'package:sinapsis/features/vault/domain/services/vault_compactor.dart';

/// Compacta la base con SQLite: la primera vez la reescribe entera con
/// `VACUUM`, dejándola en modo incremental; las siguientes devuelve las páginas
/// libres de a tramos con `PRAGMA incremental_vacuum`.
///
/// Corre sobre la conexión abierta de la app, así que mientras compacta esa
/// conexión no atiende nada más: quien la llama tiene que ser una pantalla que
/// no deje al usuario tocar la bóveda hasta que termine. Tampoco puede correr
/// a la vez que una fusión, que arma tablas y disparadores temporales en esa
/// misma conexión; las dos son operaciones de pantalla completa y no coexisten.
class SqliteVaultCompactor implements VaultCompactor {
  SqliteVaultCompactor({
    required AppDatabase database,
    required CompactionAdvisor advisor,
    int stepPages = kIncrementalStepPages,
  }) : _database = database,
       _advisor = advisor,
       _stepPages = stepPages;

  final AppDatabase _database;
  final CompactionAdvisor _advisor;

  /// Cuántas páginas se devuelven por tramo. Es un parámetro solo para que una
  /// prueba pueda ver varios tramos sin armar una bóveda de decenas de MB.
  final int _stepPages;

  @override
  Future<CompactionResult> compact({
    void Function(CompactionProgress progress)? onProgress,
    CompactionCancellation? cancellation,
  }) async {
    final stopwatch = Stopwatch()..start();
    void report(CompactionProgress progress) => onProgress?.call(progress);
    bool cancelRequested() => cancellation?.isRequested ?? false;

    report(const CompactionProgress(CompactionPhase.checking));
    final before = await _advisor.assess();
    switch (before.verdict) {
      case CompactionVerdict.nothingToReclaim:
        return CompactionResult(
          bytesBefore: before.fileBytes,
          bytesAfter: before.fileBytes,
          elapsed: stopwatch.elapsed,
        );
      case CompactionVerdict.notEnoughSpace:
        throw VaultCompactionNoSpaceException(before);
      // Sin dato de disco se intenta: si falta lugar, SQLite lo detecta y el
      // paso se revierte.
      case CompactionVerdict.ready:
      case CompactionVerdict.spaceUnknown:
        break;
    }
    if (cancelRequested()) {
      return CompactionResult(
        bytesBefore: before.fileBytes,
        bytesAfter: before.fileBytes,
        elapsed: stopwatch.elapsed,
        wasCancelled: true,
      );
    }

    final countsBefore = await _countRows();

    var wasCancelled = false;
    try {
      if (before.needsFullRewrite) {
        report(const CompactionProgress(CompactionPhase.rewriting));
        await _rewriteWholeVault();
      } else {
        wasCancelled = await _returnPagesInSteps(
          totalPages: before.freePages,
          report: report,
          cancelRequested: cancelRequested,
        );
      }
    } on Object catch (error) {
      throw VaultCompactionFailedException(error);
    }

    report(const CompactionProgress(CompactionPhase.verifying));
    final differences = countsBefore.differencesWith(await _countRows());
    if (differences.isNotEmpty) {
      final detail = differences.entries
          .map((e) => '${e.key} ${e.value.$1} → ${e.value.$2}')
          .join(', ');
      throw VaultCompactionVerificationException(
        'cambió la cantidad de filas de ${differences.length} tablas: $detail',
      );
    }

    // Devolver un tramo no toca el contenido de ninguna página que se quede: si
    // se paró en el medio, con la cuenta de filas alcanza y no se hace esperar
    // a quien canceló.
    var sourcesVerified = 0;
    if (!wasCancelled) {
      final invariant = await verifyChunkInvariant(
        _database,
        onProgress: (checked, total) => report(
          CompactionProgress(
            CompactionPhase.verifying,
            done: checked,
            total: total,
          ),
        ),
      );
      if (!invariant.holds) {
        throw VaultCompactionVerificationException(
          'el texto de las fuentes ya no coincide con sus chunks: '
          '${invariant.summary()}',
        );
      }
      sourcesVerified = invariant.sourcesChecked;
    }

    final after = await _advisor.assess();
    return CompactionResult(
      bytesBefore: before.fileBytes,
      bytesAfter: after.fileBytes,
      elapsed: stopwatch.elapsed,
      wasCancelled: wasCancelled,
      sourcesVerified: sourcesVerified,
    );
  }

  /// `VACUUM`, dejando la base en modo incremental para que las próximas veces
  /// no haga falta reescribirla.
  Future<void> _rewriteWholeVault() async {
    await _database.customStatement('PRAGMA auto_vacuum = INCREMENTAL');
    // El SQLite del proyecto se compila con SQLITE_TEMP_STORE=2: por defecto
    // sus temporales viven en memoria, y la copia de trabajo de VACUUM es del
    // tamaño de todo lo que la bóveda tiene de verdad. Medido: sin esto, una
    // bóveda de 188 MB pedía 218 MB de RAM extra; con esto, 5 MB. En un
    // teléfono con una bóveda de 909 MB, lo primero es que el sistema mate la
    // app. En archivo, en cambio, cuesta disco —el doble de lo útil, que es lo
    // que `CompactionAssessment.requiredBytes` pide—.
    await _database.customStatement('PRAGMA temp_store = FILE');
    try {
      await _database.customStatement('VACUUM');
    } finally {
      // Lo demás de la app sigue con el valor de siempre.
      await _database.customStatement('PRAGMA temp_store = DEFAULT');
    }
  }

  /// Devuelve las páginas libres de a [_stepPages], hasta que no queden o se
  /// pida parar. Cada tramo es su propia transacción: parar entre dos deja la
  /// bóveda completa y más chica. Devuelve si se paró.
  Future<bool> _returnPagesInSteps({
    required int totalPages,
    required void Function(CompactionProgress progress) report,
    required bool Function() cancelRequested,
  }) async {
    report(CompactionProgress(CompactionPhase.returning, total: totalPages));
    var remaining = totalPages;
    while (remaining > 0) {
      if (cancelRequested()) return true;
      await _database.customStatement('PRAGMA incremental_vacuum($_stepPages)');
      final left = await _freePages();
      report(
        CompactionProgress(
          CompactionPhase.returning,
          done: totalPages - left,
          total: totalPages,
        ),
      );
      // Un tramo que no devolvió nada no lo va a hacer el siguiente: no girar
      // en vacío.
      if (left >= remaining) break;
      remaining = left;
    }
    return false;
  }

  Future<int> _freePages() async {
    final row = await _database
        .customSelect('PRAGMA freelist_count')
        .getSingle();
    return row.read<int>('freelist_count');
  }

  /// Las filas de cada tabla que el usuario creó, el modelo de conocimiento y
  /// las tablas de durabilidad: todo lo que una compactación tendría que dejar
  /// igual.
  Future<VaultCounts> _countRows() => captureVaultCounts(
    _database,
    tables: [
      ...VaultCounts.userDataTables,
      ...VaultCounts.modelTables,
      ...VaultCounts.durabilityTables,
    ],
  );
}
