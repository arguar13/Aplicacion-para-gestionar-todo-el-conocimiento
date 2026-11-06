import 'dart:async';

import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/watching_query.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/processed/data/services/processed_headings_backfill.dart';

/// Quien hace correr el relleno del Índice (F46, paso 2) cuando hace falta:
/// al abrirse la bóveda, si quedó algo de antes, y cada vez que algo queda
/// «sin indexar» sin que nadie lo rehaga en el acto —lo que trae la unión de
/// bóvedas, lo que devuelve la papelera del contenido, un documento que el
/// lector no pudo indexar al guardarlo—.
///
/// Mira la base —no un aviso de quien escribe—: lo que falta es lo que la base
/// dice que falta. Una pasada a la vez; lo que llega mientras corre lo toma la
/// misma pasada o la siguiente.
class ProcessedHeadingsBackfillKeeper {
  ProcessedHeadingsBackfillKeeper({
    required AppDatabase database,
    required ProcessedHeadingsBackfill backfill,
    required TelemetryService telemetry,
  }) : _db = database,
       _backfill = backfill,
       _telemetry = telemetry;

  final AppDatabase _db;
  final ProcessedHeadingsBackfill _backfill;
  final TelemetryService _telemetry;

  StreamSubscription<bool>? _pending;
  var _stopped = false;

  /// La pasada en curso, si hay: para quien necesita esperarla (las pruebas,
  /// y [stop]).
  Future<void>? get current => _current;
  Future<void>? _current;

  /// Empieza a mirar. Llamarlo dos veces no hace nada.
  void start() {
    if (_pending != null || _stopped) return;
    _pending =
        watchQuery(
          db: _db,
          tables: [
            _db.processedDocuments,
            _db.processedParts,
            _db.processedOriginals,
            _db.processedImages,
            _db.processedHeadings,
          ],
          read: _backfill.hasPendingWork,
          telemetry: _telemetry,
          hint: 'ProcessedHeadingsBackfillKeeper',
        ).listen((pending) {
          if (pending) _kick();
        });
  }

  void _kick() {
    if (_stopped || _current != null) return;
    _current = _drain().whenComplete(() => _current = null);
  }

  /// Corre el relleno hasta que no quede nada: también lo que llegó mientras
  /// corría y la pasada ya no vio.
  Future<void> _drain() async {
    try {
      do {
        await _backfill.run(shouldStop: () => _stopped);
      } while (!_stopped && await _backfill.hasPendingWork());
      // Una falla de la base no tiene por qué tirar la app: se anota, y la
      // próxima escritura que deje algo sin indexar lo vuelve a intentar.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _telemetry.recordError(
        e,
        stackTrace,
        hint: 'ProcessedHeadingsBackfillKeeper',
      );
    }
  }

  /// Deja de mirar, y la pasada en curso se corta en el documento siguiente.
  Future<void> stop() async {
    _stopped = true;
    await _pending?.cancel();
    _pending = null;
    await _current;
  }
}
