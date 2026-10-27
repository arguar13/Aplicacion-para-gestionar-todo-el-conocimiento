import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/readable_registry.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/viewer/presentation/screens/document_reader_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/memory_study_repository.dart';
import '../../../../support/read_aloud_test_support.dart';

/// El lector de libros con el lector flotante (F25, y el pedido del dueño de
/// escuchar dentro del documento): ofrece el libro entero —con lo estudiado,
/// el mismo documento que «Escuchar» de la tarjeta—, empieza a leer en la
/// página que se ve, resalta lo que suena y sigue la lectura mientras la
/// persona no se mueva.
void main() {
  final es = AppLocalizationsEs();
  late ProviderContainer container;
  late MemoryStudyRepository studies;

  final book = [
    for (var i = 0; i < 3; i++) 'Página número $i.',
  ].join('\n\n---\n\n');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    studies = MemoryStudyRepository(DocumentStudy.notStarted);
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        readAloudControllerProvider.overrideWith(_RecordingReadAloud.new),
        studyRepositoryProvider.overrideWithValue(studies),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpReader(
    WidgetTester tester, {
    bool withStudy = false,
    String? content,
  }) async {
    final text = content ?? book;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DocumentReaderScreen(
            title: 'Un libro',
            content: text,
            study: withStudy
                ? (
                    itemId: 'item-1',
                    renditionId: 'r1',
                    content: text,
                    markdown: true,
                  )
                : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReadableDocument? offered() => container.read(currentReadableProvider);

  /// Saca al lector de la pantalla y deja que retire lo que ofrecía: lo
  /// retira después del cuadro en que se desmonta, y la prueba no termina
  /// con eso pendiente.
  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();
  }

  _RecordingReadAloud reader() =>
      container.read(readAloudControllerProvider.notifier)
          as _RecordingReadAloud;

  Finder pageLabel(int page) => find.text(es.documentReaderPageOf(page, 3));
  final backToReading = find.text(es.readAloudBackToReading);

  bool pillShown(WidgetTester tester) =>
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: backToReading,
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity ==
      1;

  testWidgets('ofrece el libro entero, con las posiciones del texto: no solo '
      'la página que se ve', (tester) async {
    await pumpReader(tester);

    final document = offered()!;
    expect(document.title, 'Un libro');
    final key = document.segments.first.sourceKey;
    expect(document.id, key);
    expect(
      document.segments,
      buildReadableSegments(book, sourceKey: key, markdown: true),
    );
    expect(document.segments.map((s) => s.spoken), [
      for (var i = 0; i < 3; i++) 'Página número $i.',
    ]);
    expect(document.segments[2].start, book.indexOf('Página número 2'));

    await closeReader(tester);
  });

  testWidgets('lo que se lee se ve en amarillo, y cuando el lector pasa a la '
      'página siguiente, la da vuelta', (tester) async {
    await pumpReader(tester);
    final document = offered()!;

    reader().readAt(document, 0);
    await tester.pumpAndSettle();
    expect(readAloudHighlights(tester), ['Página número 0.']);

    reader().readAt(document, 1);
    await tester.pumpAndSettle();
    expect(pageLabel(2), findsOneWidget);
    expect(readAloudHighlights(tester), ['Página número 1.']);

    // Más lejos, de un salto.
    reader().readAt(document, 0);
    await tester.pumpAndSettle();
    reader().readAt(document, 2);
    await tester.pumpAndSettle();
    expect(pageLabel(3), findsOneWidget);

    await closeReader(tester);
  });

  testWidgets('abierto mientras se lee, va a la página de lo que suena', (
    tester,
  ) async {
    reader().readAt(
      ReadableDocument(
        id: 'otro',
        title: 'Otro',
        segments: [
          ReadableSegment(
            sourceKey: 'reader:${book.hashCode}',
            start: book.indexOf('Página número 2'),
            end: book.length,
            spoken: 'Página número 2.',
          ),
        ],
      ),
      0,
    );
    await pumpReader(tester);

    expect(pageLabel(3), findsOneWidget);
    expect(readAloudHighlights(tester), ['Página número 2.']);

    await closeReader(tester);
  });

  testWidgets('empieza a leer en la página que se ve, no en la portada', (
    tester,
  ) async {
    await pumpReader(tester);
    expect(offered()!.startIndexOf(ReadScope.all), 0);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    // El mismo documento: la vista se pregunta al empezar.
    expect(offered()!.startIndexOf(ReadScope.all), 2);

    await closeReader(tester);
  });

  group('sigue la lectura mientras la persona no se mueva', () {
    testWidgets('pasar de página a mano lo deja tranquilo, con «Volver a la '
        'lectura»; tocarla vuelve a lo que suena', (tester) async {
      await pumpReader(tester);
      final document = offered()!;
      reader().readAt(document, 0);
      await tester.pumpAndSettle();
      expect(pillShown(tester), isFalse);

      // A la última página, a mano.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(pillShown(tester), isTrue);

      // Lo que suena pasa a la segunda página: el lector no se mueve.
      reader().readAt(document, 1);
      await tester.pumpAndSettle();
      expect(pageLabel(3), findsOneWidget);

      await tester.tap(backToReading);
      await tester.pumpAndSettle();
      expect(pageLabel(2), findsOneWidget);
      expect(pillShown(tester), isFalse);

      // Y vuelve a seguir.
      reader().readAt(document, 2);
      await tester.pumpAndSettle();
      expect(pageLabel(3), findsOneWidget);

      await closeReader(tester);
    });

    testWidgets('volver a mano a la página de lo que suena también lo '
        'retoma', (tester) async {
      await pumpReader(tester);
      final document = offered()!;
      reader().readAt(document, 0);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(pillShown(tester), isTrue);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(pillShown(tester), isFalse);

      reader().readAt(document, 1);
      await tester.pumpAndSettle();
      expect(pageLabel(2), findsOneWidget);

      await closeReader(tester);
    });

    testWidgets('otra lectura —otra parte, otro documento— lo retoma', (
      tester,
    ) async {
      await pumpReader(tester);
      final document = offered()!;
      reader().readAt(document, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(pillShown(tester), isTrue);

      reader().readAt(
        ReadableDocument(
          id: 'otra lectura',
          title: 'Un libro',
          segments: document.segments,
        ),
        0,
      );
      await tester.pumpAndSettle();

      expect(pillShown(tester), isFalse);
      expect(pageLabel(1), findsOneWidget);

      await closeReader(tester);
    });

    testWidgets('sin nada que suene, pasar de página no ofrece volver', (
      tester,
    ) async {
      await pumpReader(tester);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(pillShown(tester), isFalse);

      await closeReader(tester);
    });

    testWidgets('dentro de una página más alta que la pantalla, se desplaza '
        'hasta la línea; desplazarla a mano lo deja tranquilo', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Lugar de sobra arriba y abajo de lo que suena: nada lo acota.
      final long = [for (var i = 0; i < 120; i++) 'Renglón $i.'].join('\n');
      await pumpReader(tester, content: long);
      final document = offered()!;
      // La de la página: el texto tiene la suya, de un renglón.
      final page = find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      ScrollPosition position() => tester.state<ScrollableState>(page).position;
      expect(position().maxScrollExtent, greaterThan(0));

      reader().readAt(document, 3);
      await tester.pumpAndSettle();
      expect(position().pixels, 0, reason: 'el renglón 3 ya se ve');

      reader().readAt(document, 50);
      await tester.pumpAndSettle();
      final followed = position().pixels;
      expect(followed, greaterThan(0));
      expect(readAloudHighlights(tester), ['Renglón 50.']);

      // La línea quedó cerca de arriba, con lugar de los dos lados: la de
      // antes y las que siguen se leen sin mover nada.
      for (final line in [49, 51, 52]) {
        reader().readAt(document, line);
        await tester.pumpAndSettle();
        expect(position().pixels, followed, reason: 'renglón $line');
      }

      await tester.drag(page, const Offset(0, 300));
      await tester.pumpAndSettle();
      final byHand = position().pixels;
      expect(byHand, lessThan(followed));
      expect(pillShown(tester), isTrue);

      reader().readAt(document, 55);
      await tester.pumpAndSettle();
      expect(position().pixels, byHand, reason: 'no pelea con la persona');

      await tester.tap(backToReading);
      await tester.pumpAndSettle();
      expect(position().pixels, greaterThan(byHand));
      expect(pillShown(tester), isFalse);

      await closeReader(tester);
    });
  });

  group('escuchar lo seleccionado', () {
    testWidgets('en otra página, lee esas líneas, con sus posiciones del '
        'texto entero', (tester) async {
      await pumpReader(tester);
      final book = offered()!;
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable
        ..userUpdateTextEditingValue(
          editable.textEditingValue.copyWith(
            selection: const TextSelection(baseOffset: 0, extentOffset: 6),
          ),
          SelectionChangedCause.tap,
        )
        ..showToolbar();
      await tester.pumpAndSettle();
      // Va en «Más»: no entra en la barra.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.readAloudTooltip));
      await tester.pumpAndSettle();

      final opened = reader().opened!;
      expect(opened.segments, [book.segments[1]]);
      expect(opened.segments.single.start, book.segments[1].start);

      await closeReader(tester);
    });
  });

  group('lo estudiado (F39)', () {
    StudyMark mark(String id, StudyMarkKind kind, String part, {int from = 0}) {
      final start = book.indexOf(part, from);
      return StudyMark(
        id: id,
        kind: kind,
        origin: ContentOrigin.ai,
        start: start,
        end: start + part.length,
      );
    }

    void study() => studies.set(
      DocumentStudy(
        marks: [
          mark('s1', StudyMarkKind.summary, 'Página número 1.'),
          mark(
            'k1',
            StudyMarkKind.keyword,
            'número',
            from: book.indexOf('Página número 2'),
          ),
        ],
        analyzedUntil: book.length,
        complete: true,
      ),
    );

    testWidgets('es el mismo documento que «Escuchar» de la tarjeta de '
        'estudiar: el mismo id, los mismos pedazos y lo estudiado en sus '
        'posiciones del texto', (tester) async {
      study();
      await pumpReader(tester, withStudy: true);

      final document = offered()!;
      expect(document.id, studyReadableId('r1'));
      expect(
        document.segments,
        buildReadableSegments(book, sourceKey: 'r1', markdown: true),
      );
      final start = book.indexOf('Página número 1');
      expect(document.segmentsOf(ReadScope.summary), [
        ReadableSegment(
          sourceKey: 'r1',
          start: start,
          end: start + 16,
          spoken: 'Página número 1.',
        ),
      ]);
      final keyword = book.indexOf('número', book.indexOf('Página número 2'));
      expect(document.segmentsOf(ReadScope.keywords), [
        ReadableSegment(
          sourceKey: 'r1',
          start: keyword,
          end: keyword + 6,
          spoken: 'número',
        ),
      ]);
      expect(document.offers(ReadScope.synthesis), isFalse);

      await closeReader(tester);
    });

    testWidgets('lo estudiado se lee en su página: la da vuelta y resalta '
        'la oración; una palabra clave, solo la palabra', (tester) async {
      study();
      await pumpReader(tester, withStudy: true);

      reader().readAt(offered()!, 0, scope: ReadScope.summary);
      await tester.pumpAndSettle();
      expect(pageLabel(2), findsOneWidget);
      expect(readAloudHighlights(tester), ['Página número 1.']);

      reader().readAt(offered()!, 0, scope: ReadScope.keywords);
      await tester.pumpAndSettle();
      expect(pageLabel(3), findsOneWidget);
      expect(readAloudHighlights(tester), ['número']);

      await closeReader(tester);
    });

    testWidgets('el resumen empieza por lo que sigue a la página que se ve', (
      tester,
    ) async {
      study();
      await pumpReader(tester, withStudy: true);
      expect(offered()!.startIndexOf(ReadScope.keywords), 0);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      // Pasado el resumen, que está en la segunda: desde el principio.
      expect(offered()!.startIndexOf(ReadScope.summary), 0);
      expect(offered()!.startIndexOf(ReadScope.all), 2);

      await closeReader(tester);
    });

    testWidgets('si lo estudiado cambia con el lector abierto, lo ofrecido '
        'cambia con ello', (tester) async {
      await pumpReader(tester, withStudy: true);
      expect(offered()!.offers(ReadScope.summary), isFalse);

      study();
      await tester.pumpAndSettle();

      expect(offered()!.offers(ReadScope.summary), isTrue);

      await closeReader(tester);
    });

    testWidgets('un texto que no se estudia no ofrece elegir la parte', (
      tester,
    ) async {
      await pumpReader(tester);

      expect(offered()!.hasScopes, isFalse);

      await closeReader(tester);
    });
  });
}

/// Un lector flotante sin motor de voz que además anota qué se le pidió leer
/// con el botón o desde una selección.
class _RecordingReadAloud extends FakeReadAloudController {
  ReadableDocument? opened;

  @override
  Future<void> open(
    ReadableDocument document, {
    int? fromSegment,
    ReadScope? scope,
  }) async => opened = document;
}
