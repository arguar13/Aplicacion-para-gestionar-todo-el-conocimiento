import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_queue.dart'
    show aiModelWaitFor, kAiModelRetryDelay;
import 'package:sinapsis/features/processed/domain/entities/process_outcome.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_repository.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/processed/domain/services/text_tidier.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

/// Cómo terminó un pedido de ordenar.
enum ProcessedTidyEnd {
  /// Se miraron todas las páginas.
  done,

  /// La IA dejó de estar armada —se borró Gemma, se sacó la cuenta—: el
  /// texto quedó como se extrajo.
  unavailable,
}

/// Lo que dejó ordenar con la IA el texto de un documento procesado (F45,
/// decisión B): lo que dice el aviso.
@immutable
class ProcessedTidyOutcome {
  const ProcessedTidyOutcome({
    required this.documentId,
    required this.title,
    required this.end,
    this.tidied = 0,
    this.kept = const {},
    this.unanswered = 0,
  });

  final String documentId;

  /// El título del documento, para decir de cuál se habla.
  final String title;
  final ProcessedTidyEnd end;

  /// Cuántos pedazos quedaron ordenados (o ya lo estaban).
  final int tidied;

  /// Cuántos se dejaron como se extrajeron, por qué.
  final Map<TidyProblem, int> kept;

  /// Cuántos se dejaron porque la IA no contestó algo que se pudiera usar.
  final int unanswered;

  int get keptCount => kept.values.fold(unanswered, (sum, n) => sum + n);
  int get total => tidied + keptCount;

  /// El motivo más común de lo que se dejó, si se dejó algo por la
  /// comprobación: lo que el aviso nombra.
  TidyProblem? get mainProblem {
    TidyProblem? main;
    for (final problem in TidyProblem.values) {
      if ((kept[problem] ?? 0) > (kept[main] ?? 0)) main = problem;
    }
    return main;
  }
}

/// La cola que ordena con la IA de turno el texto de lo que se acaba de
/// triar (F45, decisión B): une las columnas, saca los encabezados y los pies
/// repetidos, arregla los cortes de renglón y de palabra y deja los títulos
/// solos en su renglón.
///
/// - **La extracción es la base, y nunca se pierde una palabra.** Cada pedazo
///   que devuelve la IA se comprueba contra el que se le dio
///   ([checkTidiedText]): si inventó, resumió, recortó, tradujo o cambió el
///   orden, ese pedazo queda como se extrajo, y el aviso lo dice
///   ([outcomes]).
/// - **Por partes**, como el análisis para estudiar (F36): de a una página del
///   texto, y cada página en los pedazos que le entran a la ventana del
///   modelo ([TextTidier.tidyPartChars]); si uno igual no entra, se parte en
///   dos.
/// - **Solo lo que sigue siendo de la fuente**
///   (`ProcessedPart.isPristineCopy`): una página que la persona editó no se
///   toca. Lo ordenado queda como una
///   página editada —«Actualizar» desde la fuente no lo pisa—, y antes de
///   guardarla se vuelve a mirar que nadie la haya cambiado mientras tanto.
/// - **En segundo plano**, con el turno de la cola pero gastando como la
///   persona, que lo pidió (`LanguageModelTasks.requestedInBackground`):
///   espera a que la persona no use el modelo y le cede el paso.
/// - **Retomable**: el pedido y cuánto va se guardan ([ProcessedTidyStore])
///   después de cada página. Si la app se cierra, al abrirla sigue desde ahí
///   ([resume]); sin conexión o sin cuota, espera y vuelve a probar en
///   [retryDelay], desde la misma página.
/// - **Viva con la app minimizada**: mientras trabaja pide el servicio en
///   primer plano de F21 ([LongWorkOwner.tidying]), y «Lo que hizo la IA» la
///   muestra en vivo (`AiTaskKind.tidy`).
///
/// Sus dependencias se piden al usarlas, como las otras colas: cambiar de
/// modelo no la rearma ni pierde lo que espera.
class ProcessedTidyQueue {
  ProcessedTidyQueue({
    required ProcessedRepository Function() repository,
    required TextTidier Function() tidier,
    required ProcessedTidyStore store,
    LanguageModelStatusCheck Function()? readiness,
    LongWorkKeeper Function()? keeper,
    AiTaskTracker? tasks,
    String? Function()? modelName,
    Future<String?> Function(String documentId)? titleOf,
    void Function(Object error, StackTrace stackTrace)? onError,
    ProcessedWorker worker = runProcessedWork,
    this.retryDelay = kAiModelRetryDelay,
  }) : _repository = repository,
       _tidier = tidier,
       _store = store,
       _readiness = readiness,
       _keeperOf = keeper,
       _tasks = tasks,
       _modelName = modelName,
       _titleOf = titleOf,
       _onError = onError,
       _worker = worker;

  /// Cada cuánto se vuelve a probar cuando el modelo no puede contestar por
  /// ahora —sin conexión, sin cuota—.
  final Duration retryDelay;

  final ProcessedRepository Function() _repository;
  final TextTidier Function() _tidier;
  final ProcessedTidyStore _store;
  final LanguageModelStatusCheck Function()? _readiness;
  final LongWorkKeeper Function()? _keeperOf;
  final AiTaskTracker? _tasks;
  final String? Function()? _modelName;
  final Future<String?> Function(String documentId)? _titleOf;
  final void Function(Object error, StackTrace stackTrace)? _onError;
  final ProcessedWorker _worker;

  LongWorkKeeper? _keeper;
  final _outcomes = StreamController<ProcessedTidyOutcome>.broadcast();

  var _draining = false;
  var _wokenWhileDraining = false;
  var _disposed = false;
  Timer? _retry;

  /// El documento que se está ordenando ahora, si hay uno.
  String? _running;

  /// Los documentos que se volvieron a pedir mientras se ordenaban: se
  /// empiezan de nuevo, con lo que tienen ahora.
  final _restarted = <String>{};

  /// Cómo terminó cada pedido, a medida que terminan: lo que dice el aviso.
  Stream<ProcessedTidyOutcome> get outcomes => _outcomes.stream;

  /// Si el texto de [documentId] se está ordenando ahora.
  bool isTidying(String documentId) => _running == documentId;

  /// Pide ordenar el texto de [documentId]. Si ya estaba pedido, empieza de
  /// nuevo: lo que se acaba de triar puede tener otras páginas.
  Future<void> enqueue(String documentId) async {
    if (_disposed) return;
    await _store.save(ProcessedTidyJob(documentId: documentId));
    if (_running == documentId) _restarted.add(documentId);
    _wake();
  }

  /// Retoma lo que quedó esperando o a medias de una sesión anterior. Se
  /// llama al abrir la app, junto con la cola de procesamiento.
  Future<void> resume() async => _wake();

  /// Deja de trabajar: lo que va a medias queda guardado, y el próximo
  /// [resume] lo retoma desde la página en que iba.
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _keeper?.idle();
    unawaited(_outcomes.close());
  }

  void _wake() {
    if (_disposed) return;
    if (_draining) {
      _wokenWhileDraining = true;
      return;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      do {
        _wokenWhileDraining = false;
        while (!_disposed) {
          final pending = await _store.pending();
          if (pending.isEmpty) break;
          // `false`: el modelo no puede por ahora; se vuelve a probar en
          // [retryDelay] y, mientras, no se toma otro.
          if (!await _run(pending.first)) {
            _retry?.cancel();
            _retry = Timer(retryDelay, _wake);
            break;
          }
        }
      } while (_wokenWhileDraining && !_disposed);
      // Una cola que no puede seguir no tumba la app: se registra y la
      // próxima apertura lo vuelve a intentar.
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      _onError?.call(e, stackTrace);
    } finally {
      _draining = false;
      _running = null;
      _keeper?.idle();
    }
  }

  /// Ordena el texto de [job] desde donde iba. Devuelve `false` si el modelo
  /// no puede contestar por ahora: el pedido queda guardado donde iba.
  Future<bool> _run(ProcessedTidyJob job) async {
    final documentId = job.documentId;
    final status = await _readiness?.call()();
    if (status != null && !status.isReady) {
      switch (status) {
        case LanguageModelNeedsDownload() || LanguageModelNeedsAccount():
          // Sin IA armada no hay qué esperar: el texto queda como se
          // extrajo, y se dice.
          await _store.remove(documentId);
          await _announce(job, ProcessedTidyEnd.unavailable);
          return true;
        default:
          return false;
      }
    }

    final repository = _repository();
    final pages = await _pagesOf(repository, documentId);
    if (pages == null) {
      // El documento ya no está —se deshizo el triado, se borró—: nada que
      // ordenar ni que avisar.
      await _store.remove(documentId);
      return true;
    }

    _running = documentId;
    final tidier = _tidier();
    final joined = pages.map((page) => page.content).join();
    final margins = TidyMargins.fromLists(
      await _worker(_marginsOf, joined, size: joined.length),
    );
    final handle = _tasks?.begin(
      kind: AiTaskKind.tidy,
      title: await _titleOf?.call(documentId) ?? '',
      itemId: documentId,
      model: _modelName?.call(),
    );
    var current = job;
    try {
      for (var index = current.nextPage; index < pages.length; index++) {
        if (_disposed) return true;
        if (_restarted.remove(documentId)) return true;
        handle?.parts(index, pages.length);
        _working(index, pages.length);
        final page = pages[index];
        final tally = _PageTally();
        if (page.isPristineCopy) {
          final content = await _tidyText(
            page.content,
            tidier,
            margins,
            tally,
            handle,
          );
          if (_disposed) return true;
          if (content != page.content && await _stillAsRead(repository, page)) {
            final edited = await repository.editPart(page.id, content);
            if (edited.getLeft().toNullable() case final failure?) {
              _onError?.call(failure, StackTrace.current);
            }
          }
        }
        // Si se volvió a pedir mientras tanto, lo guardado es el pedido
        // nuevo: no se pisa con lo de este.
        if (_restarted.remove(documentId)) return true;
        current = current.advanced(
          tidiedNow: tally.tidied,
          keptNow: tally.kept,
          unansweredNow: tally.unanswered,
        );
        await _store.save(current);
      }
    } on _ModelWait {
      // Lo de esta página no se guardó: se repite entera al volver. Si se
      // volvió a pedir, lo guardado ya es el pedido nuevo.
      if (!_restarted.remove(documentId)) await _store.save(current);
      return false;
    } finally {
      handle?.end();
      _running = null;
    }
    await _store.remove(documentId);
    await _announce(current, ProcessedTidyEnd.done);
    return true;
  }

  /// Las páginas del texto de [documentId], en orden; `null` si el documento
  /// ya no está a la vista.
  Future<List<ProcessedPart>?> _pagesOf(
    ProcessedRepository repository,
    String documentId,
  ) async {
    final status = (await repository.statusOf(documentId)).toNullable();
    if (status != ProcessedDocumentStatus.active) return null;
    final parts = (await repository.partsOf(
      documentId,
      sections: const {ProcessedSection.text},
    )).toNullable();
    if (parts == null) return null;
    return [...parts]..sort((a, b) => a.position.compareTo(b.position));
  }

  /// Si [page] sigue en la base tal como se leyó: nadie la editó, la quitó ni
  /// deshizo el triado mientras la IA la ordenaba.
  Future<bool> _stillAsRead(
    ProcessedRepository repository,
    ProcessedPart page,
  ) async {
    final now = await repository
        .watchParts(
          page.documentId,
          ProcessedSection.text,
          offset: page.position,
          limit: 1,
        )
        .first;
    return now.length == 1 &&
        now.single.id == page.id &&
        now.single.content == page.content &&
        now.single.isPristineCopy;
  }

  /// [text] ordenado de a pedazos que entran en la ventana, cada uno
  /// comprobado: lo que no pasa la comprobación queda como estaba. Si un
  /// pedazo no entra, se parte en dos, hasta [depth] veces.
  Future<String> _tidyText(
    String text,
    TextTidier tidier,
    TidyMargins margins,
    _PageTally tally,
    AiTaskHandle? handle, {
    int? maxChars,
    int depth = 3,
  }) async {
    final out = StringBuffer();
    for (final piece in tidyPieces(text, maxChars ?? tidier.tidyPartChars)) {
      final core = piece.text.trim();
      if (!_hasWords(core)) {
        out.write(piece.text);
        continue;
      }
      String reply;
      try {
        reply =
            await (handle?.run(() => tidier.tidyPart(core)) ??
                tidier.tidyPart(core));
      } on TidyPartTooLong {
        if (depth == 0 || core.length < 400) {
          tally.unanswered++;
          out.write(piece.text);
        } else {
          final halves = await _tidyText(
            core,
            tidier,
            margins,
            tally,
            handle,
            maxChars: core.length ~/ 2 + 1,
            depth: depth - 1,
          );
          out.write(withTidiedCore(piece.text, halves));
        }
        continue;
        // Lo que el modelo no contesta por ahora corta la pasada; lo demás
        // es de este pedazo, que queda como estaba.
        // ignore: avoid_catches_without_on_clauses
      } catch (e, stackTrace) {
        if (aiModelWaitFor(e) != null) throw const _ModelWait();
        _onError?.call(e, stackTrace);
        tally.unanswered++;
        out.write(piece.text);
        continue;
      }
      final tidied = cleanTidyReply(reply);
      final check = checkTidiedText(core, tidied, margins: margins);
      if (check.problem case final problem?) {
        tally.kept[problem] = (tally.kept[problem] ?? 0) + 1;
        out.write(piece.text);
      } else {
        tally.tidied++;
        out.write(withTidiedCore(piece.text, tidied));
      }
    }
    return out.toString();
  }

  Future<void> _announce(ProcessedTidyJob job, ProcessedTidyEnd end) async {
    if (_disposed) return;
    final title = await _titleOf?.call(job.documentId) ?? '';
    if (_disposed) return;
    _outcomes.add(
      ProcessedTidyOutcome(
        documentId: job.documentId,
        title: title,
        end: end,
        tidied: job.tidied,
        kept: job.kept,
        unanswered: job.unanswered,
      ),
    );
  }

  void _working(int done, int total) {
    final keeper = _keeper ??= _keeperOf?.call();
    keeper?.working(done: done, total: total);
  }
}

/// El modelo no puede contestar por ahora: la pasada se corta y se retoma.
class _ModelWait implements Exception {
  const _ModelWait();
}

/// Lo que dio una página: cuántos pedazos se ordenaron y cuántos se dejaron.
class _PageTally {
  int tidied = 0;
  int unanswered = 0;
  final kept = <TidyProblem, int>{};
}

final _anyWord = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _hasWords(String text) => _anyWord.hasMatch(text);

/// Los márgenes del texto entero, como listas: lo que vuelve de otro hilo.
({List<String> exact, List<String> numbered}) _marginsOf(String text) =>
    TidyMargins.of(text).toLists();
