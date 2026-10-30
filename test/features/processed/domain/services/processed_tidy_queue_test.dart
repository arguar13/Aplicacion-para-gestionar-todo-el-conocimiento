import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_task.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_task_tracker.dart';
import 'package:sinapsis/features/ai_models/domain/services/language_model_readiness.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';
import 'package:sinapsis/features/processed/domain/repositories/processed_tidy_store.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/domain/services/processed_text.dart';
import 'package:sinapsis/features/processed/domain/services/processed_tidy_queue.dart';
import 'package:sinapsis/features/processed/domain/services/text_tidier.dart';
import 'package:sinapsis/features/processed/domain/services/tidy_check.dart';
import 'package:sinapsis/features/transform/domain/services/long_work_keeper.dart';

import '../../processed_harness.dart';

/// Lo que hace la IA de mentira con cada pedazo.
typedef _Reply = FutureOr<String> Function(String text);

class _FakeTidier implements TextTidier {
  _FakeTidier(this.reply, {this.tidyPartChars = 3000});

  _Reply reply;

  @override
  final int tidyPartChars;

  /// Lo que se le pidió ordenar, en orden.
  final asked = <String>[];

  @override
  Future<String> tidyPart(String text) async {
    asked.add(text);
    return reply(text);
  }
}

class _MemoryStore implements ProcessedTidyStore {
  final jobs = <ProcessedTidyJob>[];

  @override
  Future<List<ProcessedTidyJob>> pending() async => [...jobs];

  @override
  Future<void> save(ProcessedTidyJob job) async {
    final index = jobs.indexWhere((j) => j.documentId == job.documentId);
    if (index < 0) {
      jobs.add(job);
    } else {
      jobs[index] = job;
    }
  }

  @override
  Future<void> remove(String documentId) async =>
      jobs.removeWhere((j) => j.documentId == documentId);
}

class _Keeper implements LongWorkKeeper {
  final calls = <String>[];

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => calls.add('$done/$total');

  @override
  void idle() => calls.add('idle');
}

Future<R> _inline<Q, R>(
  ComputeCallback<Q, R> work,
  Q message, {
  required int size,
}) async => work(message);

/// Un libro como sale de un PDF: renglones cortos, palabras partidas con
/// guion y el encabezado «Historia de Roma» arriba de cada tramo. Más de dos
/// páginas del texto de un procesado (`kProcessedTextPageChars`).
String _book() {
  final out = StringBuffer();
  for (var chapter = 0; out.length < kProcessedTextPageChars * 2.5; chapter++) {
    out.write('Historia de Roma\n\n');
    for (var paragraph = 0; paragraph < 4; paragraph++) {
      out.write(
        'En el año $chapter$paragraph el imperio se exten-\ndió\npor las '
        'costas del mar\ny los pueblos vecinos\npagaron tributo a la '
        'ciudad\nmientras el Senado\ndiscutía las leyes\nde la república '
        'durante\nlargas sesiones.\n\n',
      );
    }
  }
  return out.toString();
}

/// Lo que haría una IA que ordena bien: saca el encabezado, junta lo partido
/// con guion y une los renglones de cada párrafo.
String _order(String text) => text
    .split('\n')
    .where((line) => line.trim() != 'Historia de Roma')
    .join('\n')
    .replaceAll('-\n', '')
    .replaceAll(RegExp(r'(?<!\n)\n(?!\n)'), ' ')
    .trim();

/// El texto ordenar con la IA de turno (F45, decisión B): por partes, cada
/// pedazo comprobado contra la extracción, retomable, y solo sobre lo que
/// sigue siendo de la fuente. Contra el repositorio y SQLite reales.
void main() {
  late ProcessedHarness h;
  late _MemoryStore store;
  late _Keeper keeper;
  late AiTaskTracker tasks;
  final docId = processedDocumentIdFor('libro');
  final book = _book();

  setUp(() async {
    h = await ProcessedHarness.create();
    await h.vault.saveSource('libro', title: 'Roma', text: book);
    final processed = await h.process('libro', {
      ProcessedSection.text: SectionEdit.add(const SectionInput.fromSource()),
    });
    expect(processed.isRight(), isTrue);
    store = _MemoryStore();
    keeper = _Keeper();
    tasks = AiTaskTracker(clock: () => h.vault.now);
  });
  tearDown(() => h.close());

  ProcessedTidyQueue queueWith(
    TextTidier tidier, {
    LanguageModelStatus status = const LanguageModelReady(
      provider: AiProvider.gemma,
    ),
  }) {
    final queue = ProcessedTidyQueue(
      repository: () => h.repository,
      tidier: () => tidier,
      store: store,
      readiness: () =>
          ({bool background = false}) async => status,
      keeper: () => keeper,
      tasks: tasks,
      modelName: () => 'gemma-4-e4b',
      titleOf: (_) async => 'Roma',
      worker: _inline,
      retryDelay: const Duration(milliseconds: 1),
    );
    addTearDown(queue.dispose);
    return queue;
  }

  Future<List<ProcessedPart>> pages() async => [
    ...(await h.repository.partsOf(
      docId,
      sections: const {ProcessedSection.text},
    )).toNullable()!,
  ]..sort((a, b) => a.position.compareTo(b.position));

  Future<ProcessedTidyOutcome> tidy(ProcessedTidyQueue queue) async {
    final outcome = queue.outcomes.first;
    await queue.enqueue(docId);
    return outcome.timeout(const Duration(seconds: 20));
  }

  test('con una IA que ordena bien, cada página queda ordenada, sin el '
      'encabezado repetido, y la fuente no se toca', () async {
    final before = await pages();
    expect(before.length, greaterThan(2));
    final source = await h.sourceSnapshot('libro');
    final tidier = _FakeTidier(_order);

    final outcome = await tidy(queueWith(tidier));

    expect(outcome.end, ProcessedTidyEnd.done);
    expect(outcome.title, 'Roma');
    expect(outcome.keptCount, 0);
    expect(outcome.tidied, tidier.asked.length);
    final after = await pages();
    expect(after.length, before.length);
    for (final (index, page) in after.indexed) {
      expect(page.edited, isTrue, reason: 'página $index');
      expect(page.content, isNot(contains('Historia de Roma')));
      expect(page.content, isNot(contains('exten-')));
      expect(page.content, contains('se extendió por las costas'));
      // Lo ordenado es la extracción, palabra por palabra.
      expect(
        checkTidiedText(
          before[index].content,
          page.content,
          margins: TidyMargins.of(book),
        ),
        TidyCheck.faithful,
      );
    }
    expect(await h.sourceSnapshot('libro'), source);
    expect(store.jobs, isEmpty);
    expect(keeper.calls.last, 'idle');
  });

  test('el encabezado se reconoce en todo el documento: en cada pedazo está '
      'menos veces de las que hacen falta para saberlo', () async {
    final tidier = _FakeTidier(_order, tidyPartChars: 1200);
    final outcome = await tidy(queueWith(tidier));

    expect(tidier.asked, hasLength(greaterThan(10)));
    for (final asked in tidier.asked) {
      expect(
        'Historia de Roma'.allMatches(asked).length,
        lessThan(TidyMargins.minRepeats),
      );
    }
    expect(outcome.keptCount, 0);
    for (final page in await pages()) {
      expect(page.content, isNot(contains('Historia de Roma')));
    }
  });

  test('de a pedazos que entran en la ventana: ninguno pasa de lo que el '
      'modelo lee de una vez, y juntos son cada página', () async {
    final before = await pages();
    final tidier = _FakeTidier((text) => text, tidyPartChars: 1000);

    await tidy(queueWith(tidier));

    expect(tidier.asked, isNotEmpty);
    for (final asked in tidier.asked) {
      expect(asked.length, lessThanOrEqualTo(1000));
    }
    final total = before.fold<int>(0, (sum, p) => sum + p.content.length);
    expect(tidier.asked.length, greaterThanOrEqualTo(total ~/ 1000));
    // Lo que la IA devolvió igual deja la página igual: no se edita nada.
    for (final page in await pages()) {
      expect(page.isPristineCopy, isTrue);
    }
  });

  test('si la IA inventa, cada pedazo queda como se extrajo y el aviso lo '
      'dice', () async {
    final before = await pages();
    final tidier = _FakeTidier((text) => 'Resumen: ${_order(text)}');

    final outcome = await tidy(queueWith(tidier));

    expect(outcome.tidied, 0);
    expect(outcome.kept, {TidyProblem.invented: tidier.asked.length});
    expect(outcome.mainProblem, TidyProblem.invented);
    final after = await pages();
    for (final (index, page) in after.indexed) {
      expect(page.content, before[index].content);
      expect(page.isPristineCopy, isTrue);
    }
  });

  test('si traduce, recorta o cambia el orden, también', () async {
    for (final (reply, problem) in <(_Reply, TidyProblem)>[
      (
        (_) => 'The empire spread across the sea coasts.',
        TidyProblem.rewritten,
      ),
      (
        (text) {
          final words = _order(text).split(' ');
          return words.take(words.length ~/ 2).join(' ');
        },
        TidyProblem.missing,
      ),
      (
        (text) => _order(text).split(' ').reversed.join(' '),
        TidyProblem.reordered,
      ),
    ]) {
      store.jobs.clear();
      final outcome = await tidy(queueWith(_FakeTidier(reply)));
      expect(outcome.mainProblem, problem);
      expect(outcome.tidied, 0);
      for (final page in await pages()) {
        expect(page.isPristineCopy, isTrue);
      }
    }
  });

  test('lo que pasa la comprobación se queda y lo que no, no: pedazo por '
      'pedazo', () async {
    // Inventa solo en el pedazo que tiene «año 00».
    final tidier = _FakeTidier(
      (text) => text.contains('año 00') ? 'Inventado. $text' : _order(text),
      tidyPartChars: 1500,
    );

    final outcome = await tidy(queueWith(tidier));

    expect(outcome.kept, {TidyProblem.invented: 1});
    expect(outcome.tidied, tidier.asked.length - 1);
    final first = (await pages()).first;
    expect(first.content, contains('año 00 el imperio se exten-\ndió'));
    expect(first.content, contains('se extendió por las costas'));
  });

  test('una página que la persona editó no se toca', () async {
    final first = (await pages()).first;
    await h.repository.editPart(first.id, 'Lo escribí yo.');
    final tidier = _FakeTidier(_order);

    await tidy(queueWith(tidier));

    expect(tidier.asked.any((text) => text.contains('Lo escribí yo')), isFalse);
    expect((await pages()).first.content, 'Lo escribí yo.');
  });

  test('si la persona edita la página mientras la IA la ordena, gana la '
      'persona', () async {
    final first = (await pages()).first;
    var edited = false;
    final tidier = _FakeTidier((text) async {
      if (!edited) {
        edited = true;
        await h.repository.editPart(first.id, 'Lo cambié a mitad.');
      }
      return _order(text);
    });

    await tidy(queueWith(tidier));

    expect((await pages()).first.content, 'Lo cambié a mitad.');
  });

  test('un pedazo que no entra en la ventana se parte en dos', () async {
    final tidier = _FakeTidier((text) {
      if (text.length > 700) throw const TidyPartTooLong();
      return _order(text);
    }, tidyPartChars: 2000);

    final outcome = await tidy(queueWith(tidier));

    expect(outcome.keptCount, 0);
    expect(tidier.asked.where((text) => text.length <= 700), isNotEmpty);
    for (final page in await pages()) {
      expect(page.edited, isTrue);
    }
  });

  test('sin conexión espera y sigue desde la página en que iba', () async {
    var failures = 2;
    final tidier = _FakeTidier((text) {
      if (failures > 0) {
        failures--;
        throw const CloudModelException(CloudModelFailure.network);
      }
      return _order(text);
    });
    final queue = queueWith(tidier);

    final outcome = await tidy(queue);

    expect(failures, 0);
    expect(outcome.keptCount, 0);
    expect(outcome.unanswered, 0);
    for (final page in await pages()) {
      expect(page.edited, isTrue);
    }
  });

  test('un pedido que falla por otra cosa deja ese pedazo como estaba y '
      'sigue', () async {
    var calls = 0;
    final tidier = _FakeTidier((text) {
      if (calls++ == 0) throw StateError('Gemma se trabó');
      return _order(text);
    });

    final outcome = await tidy(queueWith(tidier));

    expect(outcome.unanswered, 1);
    expect(outcome.mainProblem, isNull);
    expect(outcome.tidied, tidier.asked.length - 1);
  });

  test('se retoma desde la página guardada', () async {
    store.jobs.add(ProcessedTidyJob(documentId: docId, nextPage: 1));
    final tidier = _FakeTidier(_order);
    final queue = queueWith(tidier);
    final outcome = queue.outcomes.first;

    await queue.resume();
    await outcome.timeout(const Duration(seconds: 20));

    final after = await pages();
    expect(after.first.isPristineCopy, isTrue);
    for (final page in after.skip(1)) {
      expect(page.edited, isTrue);
    }
  });

  test(
    'sin IA armada no ordena nada y avisa que quedó como se extrajo',
    () async {
      final tidier = _FakeTidier(_order);
      final outcome = await tidy(
        queueWith(tidier, status: const LanguageModelNeedsDownload()),
      );

      expect(outcome.end, ProcessedTidyEnd.unavailable);
      expect(tidier.asked, isEmpty);
      expect(store.jobs, isEmpty);
    },
  );

  test('sin cuota por ahora, espera sin descartar el pedido', () async {
    final tidier = _FakeTidier(_order);
    final queue = queueWith(
      tidier,
      status: const LanguageModelOutOfQuota(
        provider: AiProvider.gemini,
        accounts: 1,
      ),
    );

    await queue.enqueue(docId);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(tidier.asked, isEmpty);
    expect(store.jobs.single.documentId, docId);
  });

  test('si el documento ya no está, se olvida el pedido sin avisar', () async {
    final tidier = _FakeTidier(_order);
    final queue = queueWith(tidier);
    var announced = false;
    queue.outcomes.listen((_) => announced = true);

    await queue.enqueue(processedDocumentIdFor('otro'));
    for (var i = 0; i < 100 && store.jobs.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(store.jobs, isEmpty);
    expect(tidier.asked, isEmpty);
    expect(announced, isFalse);
  });

  test('«Lo que hizo la IA» la muestra mientras trabaja, con el modelo y la '
      'página que va', () async {
    final seen = <AiTask>[];
    final tidier = _FakeTidier((text) {
      seen.addAll(tasks.tasks.value);
      return _order(text);
    });

    await tidy(queueWith(tidier));

    expect(seen, isNotEmpty);
    expect(seen.first.kind, AiTaskKind.tidy);
    expect(seen.first.title, 'Roma');
    expect(seen.first.model, 'gemma-4-e4b');
    expect(seen.last.partProgress?.total, (await pages()).length);
    expect(tasks.tasks.value, isEmpty);
  });
}
