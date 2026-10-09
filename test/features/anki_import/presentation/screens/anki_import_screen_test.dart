import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/anki_import/data/repositories/anki_import_repository_impl.dart';
import 'package:sinapsis/features/anki_import/data/services/sqlite_anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_exception.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_import_plan.dart';
import 'package:sinapsis/features/anki_import/domain/entities/anki_imported_package.dart';
import 'package:sinapsis/features/anki_import/domain/repositories/anki_import_repository.dart';
import 'package:sinapsis/features/anki_import/domain/services/anki_package_reader.dart';
import 'package:sinapsis/features/anki_import/domain/services/apkg_file_chooser.dart';
import 'package:sinapsis/features/anki_import/presentation/providers/anki_import_providers.dart';
import 'package:sinapsis/features/anki_import/presentation/screens/anki_import_screen.dart';
import 'package:sinapsis/features/duplicates/domain/services/duplicate_suggestion_generator.dart';
import 'package:sinapsis/features/duplicates/presentation/providers/duplicate_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/anki_package_fixture.dart';
import '../../../../support/fake_id_generator.dart';
import '../../../../support/library_harness.dart';

/// La pantalla de «Importar de Anki» (F31, decisión 73): elegir el archivo,
/// ver qué trae, elegir dónde cae, importar, y los errores.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late _Chooser chooser;
  late _Reader reader;
  Future<void> Function()? beforeInsert;
  Object? insertError;

  setUp(() async {
    chooser = _Chooser();
    reader = _Reader(await _package());
    beforeInsert = null;
    insertError = null;
    harness = await LibraryHarness.create(
      extraOverrides: [
        // La búsqueda de duplicados de una nota nueva corre sin esperar, en la
        // zona de verdad: bajo el reloj de mentira de un `testWidgets` se
        // quedaría con la base y trabaría las lecturas de la prueba.
        duplicateSuggestionGeneratorProvider.overrideWithValue(_NoDuplicates()),
        apkgFileChooserProvider.overrideWithValue(chooser),
        ankiPackageReaderProvider.overrideWithValue(reader),
        ankiImportRepositoryProvider.overrideWith(
          (ref) => _Hooked(
            AnkiImportRepositoryImpl(
              database: ref.watch(appDatabaseProvider),
              ids: FakeIdGenerator(),
            ),
            before: () async => beforeInsert?.call(),
            error: () => insertError,
          ),
        ),
      ],
    );
    addTearDown(pumpEventQueue);
  });

  AppDatabase db() => harness.database;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Una pantalla alta: la lista construye solo lo que se ve.
    tester.view
      ..physicalSize = const Size(900, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.wrap(const AnkiImportScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('anki-import-pick')));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('anki-import-start')));
    await tester.tap(find.byKey(const Key('anki-import-start')));
    await tester.pumpAndSettle();
  }

  testWidgets('al principio explica qué hace y cómo exportar desde Anki', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text(es.ankiImportIntro), findsOneWidget);
    expect(find.text(es.ankiImportHowTo), findsOneWidget);
    expect(find.text(es.ankiImportPick), findsOneWidget);
  });

  testWidgets('cancelar el selector no cambia nada', (tester) async {
    chooser.path = null;
    await pumpScreen(tester);

    await pick(tester);

    expect(chooser.picks, 1);
    expect(find.text(es.ankiImportPick), findsOneWidget);
    expect(find.byKey(const Key('anki-import-summary')), findsNothing);
  });

  testWidgets('la vista previa cuenta mazos, formas, etapas, pausadas y '
      'avisa de los medios', (tester) async {
    await pumpScreen(tester);
    await pick(tester);

    expect(
      find.text(es.ankiImportSummary(5, 2)),
      findsOneWidget,
      reason: 'cinco tarjetas en dos mazos',
    );
    expect(find.text(es.ankiImportKindBasic(5)), findsOneWidget);
    expect(find.text(es.ankiImportStages(1, 1, 3)), findsOneWidget);
    expect(find.text(es.ankiImportSuspended(1)), findsOneWidget);
    expect(find.text(es.ankiImportPostponed(1)), findsOneWidget);
    expect(find.text(es.ankiImportMediaWarning(1, 0, 0)), findsOneWidget);
    expect(find.text(es.ankiImportStart(5)), findsOneWidget);
    // El selector de archivos soltó lo que había dejado.
    expect(chooser.releases, 1);
  });

  testWidgets('un mazo filtrado se avisa', (tester) async {
    // Leer el paquete usa archivos de verdad: fuera del reloj de mentira.
    reader.package = (await tester.runAsync(() => _package(filtered: true)))!;
    await pumpScreen(tester);
    await pick(tester);

    expect(find.text(es.ankiImportFilteredWarning(1)), findsOneWidget);
  });

  testWidgets('un elemento por mazo es lo elegido de entrada, y trae todo con '
      'su calendario', (tester) async {
    await pumpScreen(tester);
    await pick(tester);

    final perDeck = tester.widget<RadioListTile<AnkiImportDestination>>(
      find.byKey(const Key('anki-import-dest-per-deck')),
    );
    expect(perDeck.value, AnkiImportDestination.perDeck);
    await start(tester);

    expect(find.text(es.ankiImportDoneTitle), findsOneWidget);
    expect(find.text(es.ankiImportDoneCards(5)), findsOneWidget);
    expect(await db().select(db().flashcards).get(), hasLength(5));
    final titles = (await db().select(db().knowledgeEntries).get())
        .map((e) => e.title)
        .toSet();
    expect(titles, {'Default', 'Historia › Roma'});
    final suspended = (await db().select(db().flashcards).get()).where(
      (c) => c.suspended,
    );
    expect(suspended, hasLength(1));
  });

  testWidgets('todo en un solo elemento', (tester) async {
    await pumpScreen(tester);
    await pick(tester);

    await tester.tap(find.byKey(const Key('anki-import-dest-single')));
    await tester.pumpAndSettle();
    await start(tester);

    final items = await db().select(db().knowledgeEntries).get();
    expect(items.map((e) => e.title), [kAnkiImportedName]);
    expect(await db().select(db().flashcards).get(), hasLength(5));
  });

  testWidgets('mientras escribe muestra el avance', (tester) async {
    final gate = Completer<void>();
    beforeInsert = () => gate.future;
    await pumpScreen(tester);
    await pick(tester);

    await tester.ensureVisible(find.byKey(const Key('anki-import-start')));
    await tester.tap(find.byKey(const Key('anki-import-start')));
    await tester.pump();
    await tester.pump();

    expect(find.text(es.ankiImportRunning), findsOneWidget);
    expect(find.text(es.ankiImportProgress(0, 5)), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text(es.ankiImportDoneTitle), findsOneWidget);
  });

  testWidgets('volver a traer el mismo archivo no duplica y lo dice', (
    tester,
  ) async {
    await pumpScreen(tester);
    await pick(tester);
    await start(tester);
    expect(await db().select(db().flashcards).get(), hasLength(5));

    // Otra vez, desde cero.
    harness.container.read(ankiImportProvider.notifier).reset();
    await tester.pumpAndSettle();
    await pick(tester);

    expect(find.text(es.ankiImportAlready(5)), findsOneWidget);
    expect(find.text(es.ankiImportNothingNew), findsOneWidget);
    expect(find.byKey(const Key('anki-import-start')), findsNothing);
    expect(await db().select(db().flashcards).get(), hasLength(5));
  });

  testWidgets('un paquete del formato nuevo dice cómo exportarlo, y se puede '
      'probar con otro', (tester) async {
    reader.error = const AnkiImportException(
      AnkiImportFailure.newFormatOnly,
      'Este paquete es del formato nuevo de Anki. Exportalo de nuevo con '
      '«Compatibilidad con versiones antiguas».',
    );
    await pumpScreen(tester);
    await pick(tester);

    expect(find.text(es.ankiImportFailedTitle), findsOneWidget);
    expect(
      find.text(
        'Este paquete es del formato nuevo de Anki. Exportalo de nuevo con '
        '«Compatibilidad con versiones antiguas».',
      ),
      findsOneWidget,
    );
    expect(find.text(es.ankiImportHowTo), findsOneWidget);
    expect(chooser.releases, 1, reason: 'también se suelta al fallar');

    reader.error = null;
    await tester.tap(find.byKey(const Key('anki-import-try-again')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('anki-import-summary')), findsOneWidget);
  });

  testWidgets('un archivo que no es un paquete muestra el mensaje del lector', (
    tester,
  ) async {
    reader.error = const AnkiImportException(
      AnkiImportFailure.notAnApkg,
      'Ese archivo no es un paquete de Anki (.apkg).',
    );
    await pumpScreen(tester);
    await pick(tester);

    expect(
      find.text('Ese archivo no es un paquete de Anki (.apkg).'),
      findsOneWidget,
    );
    expect(find.text(es.ankiImportFailedWrite), findsNothing);
  });

  testWidgets('si escribir falla, no queda nada y se puede reintentar', (
    tester,
  ) async {
    insertError = StateError('se cortó el disco');
    await pumpScreen(tester);
    await pick(tester);
    await start(tester);

    expect(find.text(es.ankiImportFailedTitle), findsOneWidget);
    expect(find.text(es.ankiImportFailedWrite), findsOneWidget);
    expect(await db().select(db().flashcards).get(), isEmpty);
    expect(await db().select(db().knowledgeEntries).get(), isEmpty);

    insertError = null;
    await tester.tap(find.byKey(const Key('anki-import-try-again')));
    await tester.pumpAndSettle();
    await start(tester);
    expect(await db().select(db().flashcards).get(), hasLength(5));
  });

  testWidgets('la ruta /settings/anki-import abre la pantalla', (tester) async {
    expect(kRouteAnkiImport, '/settings/anki-import');
    await tester.pumpWidget(harness.wrapWithAppRouter());
    await tester.pumpAndSettle();
    harness.pushTo(kRouteAnkiImport);
    await tester.pumpAndSettle();

    expect(find.text(es.ankiImportTitle), findsOneWidget);
  });
}

class _NoDuplicates implements DuplicateSuggestionGenerator {
  @override
  Future<void> generate(KnowledgeItem item) async {}
}

class _Chooser implements ApkgFileChooser {
  String? path = 'mazo.apkg';
  int picks = 0;
  int releases = 0;

  @override
  Future<String?> pick() async {
    picks++;
    return path;
  }

  @override
  Future<void> release() async => releases++;
}

class _Reader implements AnkiPackageReader {
  _Reader(this.package);

  AnkiImportedPackage package;
  AnkiImportException? error;

  @override
  Future<AnkiImportedPackage> readFile(String path) async {
    final failure = error;
    if (failure != null) throw failure;
    return package;
  }

  @override
  Future<AnkiImportedPackage> readBytes(Uint8List bytes) =>
      throw UnimplementedError();
}

/// El repositorio de verdad, con un portón antes de escribir y un fallo a
/// pedido.
class _Hooked implements AnkiImportRepository {
  _Hooked(this._inner, {required this.before, required this.error});

  final AnkiImportRepository _inner;
  final Future<void> Function() before;
  final Object? Function() error;

  @override
  Future<Set<int>> alreadyImported(List<AnkiImportedCard> cards) =>
      _inner.alreadyImported(cards);

  @override
  Future<Map<String, bool>> existingItems(List<String> itemIds) =>
      _inner.existingItems(itemIds);

  @override
  Future<int> insertCards(List<AnkiPlannedCard> cards) async {
    await before();
    final failure = error();
    // Tira lo que la prueba pida, sea una excepción o un error.
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    return _inner.insertCards(cards);
  }
}

/// Cinco tarjetas básicas en dos mazos: una nueva con una imagen, una de
/// repaso, una aprendiéndose, una pausada y una pospuesta.
Future<AnkiImportedPackage> _package({bool filtered = false}) {
  final collection = collectionBytes(
    crt: DateTime(2026, 1, 1, 4).millisecondsSinceEpoch ~/ 1000,
    models: [basicModel(10)],
    decks: [deck(1, 'Default'), deck(2, 'Historia::Roma')],
    notes: [
      const FixtureNote(
        id: 101,
        modelId: 10,
        fields: ['Mirá <img src="mapa.png">', 'Roma'],
        guid: 'g101',
      ),
      for (var i = 2; i <= 5; i++)
        FixtureNote(
          id: 100 + i,
          modelId: 10,
          fields: ['Pregunta $i', 'Respuesta $i'],
          guid: 'g${100 + i}',
        ),
    ],
    cards: [
      const FixtureCard(id: 1700000001001, noteId: 101, due: 3),
      const FixtureCard(
        id: 1700000001002,
        noteId: 102,
        deckId: 2,
        type: 2,
        queue: 2,
        due: 280,
        ivl: 30,
        factor: 2500,
        reps: 5,
      ),
      const FixtureCard(
        id: 1700000001003,
        noteId: 103,
        deckId: 2,
        type: 1,
        queue: 1,
        due: 1790000000,
        reps: 1,
        left: 2002,
      ),
      const FixtureCard(
        id: 1700000001004,
        noteId: 104,
        deckId: 2,
        type: 2,
        queue: -1,
        due: 300,
        ivl: 12,
        factor: 2300,
        reps: 3,
      ),
      FixtureCard(
        id: 1700000001005,
        noteId: 105,
        deckId: 2,
        type: 2,
        queue: -2,
        due: 290,
        ivl: 20,
        factor: 2500,
        reps: 4,
        odid: filtered ? 1 : 0,
        odue: filtered ? 290 : 0,
      ),
    ],
  );
  return const SqliteAnkiPackageReader().readBytes(
    apkgOf(collection, media: '{"0": "mapa.png"}'),
  );
}
