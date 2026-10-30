import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';

/// [ProcessedTidyStore] en las preferencias del teléfono (F45, decisión B).
///
/// En el teléfono y no en la base, a propósito: ordenar es trabajo de la IA
/// de **este** dispositivo, como lo oculto del original
/// (`OriginalLayers`). No viaja con la copia de la bóveda ni se une
/// con la de otro dispositivo, que no tiene cómo seguirlo. Lo que deja —las
/// páginas ordenadas— sí está en la base, como cualquier página editada.
///
/// Son pocos pedidos —los de lo que se acaba de triar—, guardados juntos en
/// una lista, cada uno con cuánto va.
class PrefsProcessedTidyStore implements ProcessedTidyStore {
  const PrefsProcessedTidyStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'processed_tidy_jobs_v1';

  @override
  Future<List<ProcessedTidyJob>> pending() async => _read();

  @override
  Future<void> save(ProcessedTidyJob job) async {
    final jobs = _read();
    final index = jobs.indexWhere((j) => j.documentId == job.documentId);
    if (index < 0) {
      jobs.add(job);
    } else {
      jobs[index] = job;
    }
    await _write(jobs);
  }

  @override
  Future<void> remove(String documentId) async {
    final jobs = _read();
    final before = jobs.length;
    jobs.removeWhere((j) => j.documentId == documentId);
    if (jobs.length != before) await _write(jobs);
  }

  List<ProcessedTidyJob> _read() {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    // Lo guardado roto no tumba la cola: se empieza sin pedidos.
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List<Object?>) return [];
    return [
      for (final entry in decoded)
        if (_decode(entry) case final job?) job,
    ];
  }

  Future<void> _write(List<ProcessedTidyJob> jobs) async {
    if (jobs.isEmpty) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(
      key,
      jsonEncode([for (final job in jobs) _encode(job)]),
    );
  }

  static Map<String, Object?> _encode(ProcessedTidyJob job) => {
    'document': job.documentId,
    'next': job.nextPage,
    'tidied': job.tidied,
    'unanswered': job.unanswered,
    'kept': {
      for (final MapEntry(:key, :value) in job.kept.entries) key.name: value,
    },
  };

  static int _count(Object? value) => value is int && value > 0 ? value : 0;

  static ProcessedTidyJob? _decode(Object? entry) {
    if (entry is! Map<String, Object?>) return null;
    final documentId = entry['document'];
    if (documentId is! String) return null;
    final kept = entry['kept'];
    return ProcessedTidyJob(
      documentId: documentId,
      nextPage: _count(entry['next']),
      tidied: _count(entry['tidied']),
      unanswered: _count(entry['unanswered']),
      kept: {
        if (kept is Map<String, Object?>)
          for (final problem in TidyProblem.values)
            if (kept[problem.name] case final int n when n > 0) problem: n,
      },
    );
  }
}
