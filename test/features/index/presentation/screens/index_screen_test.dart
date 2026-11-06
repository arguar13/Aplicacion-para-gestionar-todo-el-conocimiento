import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/domain/extract_place.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_leader_line.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_panels.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_images_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/images/processed_image_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/fake_index_repository.dart';
import 'index_screen_harness.dart';

/// La pantalla del Índice (F46, paso 3): el árbol por tema y por documento,
/// los niveles, el buscador, lo fijo arriba, los dos paneles, «Nuevo», lo que
/// cambia en vivo y lo que abre cada entrada.
void main() {
  final es = AppLocalizationsEs();
  late FakeIndexRepository repo;
  late IndexScreenHarness harness;

  setUp(() {
    repo = FakeIndexRepository();
    harness = IndexScreenHarness(repo);
  });
  tearDown(() => repo.dispose());

  /// Una biblioteca chica: Roma y Egipto, un libro en los dos, un PDF con
  /// marcadores, uno sin tema y uno que todavía no se indexó.
  void library() {
    repo.spaces.addAll({'roma': 'Roma', 'egipto': 'Egipto'});
    repo.documents.addAll([
      indexDocument(
        'historia',
        'Historia de Roma',
        spaces: ['roma'],
        chapters: 4,
      ),
      indexDocument(
        'cleopatra',
        'Cleopatra',
        spaces: ['roma', 'egipto'],
        kind: SourceKind.webPage,
        chapters: 1,
      ),
      indexDocument('piramides', 'Pirámides', spaces: ['egipto'], chapters: 2),
      indexDocument('suelto', 'Apuntes sueltos'),
    ]);
    repo.entries['historia'] = indexChapters('historia', [
      (1, 'La Monarquía'),
      (1, 'La República'),
      (2, 'Las guerras púnicas'),
      (3, 'Aníbal en los Alpes'),
    ]);
    repo.entries['cleopatra'] = indexChapters('cleopatra', [
      (1, 'La reina'),
    ], firstKey: 20);
    repo.entries['piramides'] = indexChapters(
      'piramides',
      [(1, 'Guiza'), (2, 'La Gran Pirámide')],
      firstKey: 30,
      pdf: true,
    );
    repo.entries['suelto'] = [indexWholeText('suelto', 40)];
  }

  Finder documentRow(String id) => find.byWidgetPredicate(
    (widget) => widget is IndexDocumentRow && widget.document.id == id,
    description: 'la fila del documento $id',
  );

  /// La lista del Índice, que se desplaza (no la del buscador).
  Finder list() => find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Si el foco está en [finder] o adentro.
  bool focusedIn(Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final targets = finder.evaluate().toSet();
    if (targets.contains(focused)) return true;
    var inside = false;
    focused.visitAncestorElements((ancestor) {
      inside = targets.contains(ancestor);
      return !inside;
    });
    return inside;
  }

  String readerFor(String documentId, {ExtractPlace? at}) =>
      RoutePaths.extractReading(StudyCreationKind.fullText, [
        documentId,
      ], at: at);

  /// Despliega [documentId]: lo busca bajando por la lista —la lista
  /// dibuja de a lo que entra— y lo toca.
  Future<void> unfold(WidgetTester tester, String documentId) async {
    final row = documentRow(documentId);
    for (var i = 0; i < 50 && row.evaluate().isEmpty; i++) {
      await tester.drag(list(), const Offset(0, -200));
      await tester.pump();
    }
    await tester.ensureVisible(row.first);
    await tester.pumpAndSettle();
    await tester.tap(row.first);
    await tester.pumpAndSettle();
  }

  group('sin nada, cargando', () {
    testWidgets('sin nada procesado, el Índice vacío dice cómo se arma y '
        'lleva a Procesado', (tester) async {
      await harness.pump(tester);

      expect(find.byKey(const Key('index-empty')), findsOneWidget);
      expect(find.text(es.f46P3EmptyTitle), findsOneWidget);
      expect(find.text(es.f46P3EmptyMessage), findsOneWidget);

      await tester.tap(find.text(es.f46P3EmptyAction));
      await tester.pumpAndSettle();
      expect(find.text('Procesado'), findsOneWidget);
    });

    testWidgets('mientras se leen los temas, la ruedita; y nada más', (
      tester,
    ) async {
      library();
      repo.hold('topics');
      await harness.pump(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('index-empty')), findsNothing);

      repo.release('topics');
      await tester.pumpAndSettle();
      expect(find.text('ROMA'), findsOneWidget);
    });
  });

  group('por tema', () {
    testWidgets('cada tema en versalitas con cuántos documentos tiene, de la '
        'A a la Z, y «Sin tema» al final', (tester) async {
      library();
      await harness.pump(tester);

      final egipto = tester.getTopLeft(find.text('EGIPTO')).dy;
      final roma = tester.getTopLeft(find.text('ROMA')).dy;
      final loose = tester.getTopLeft(find.text('SIN TEMA')).dy;
      expect(egipto, lessThan(roma));
      expect(roma, lessThan(loose));
      Finder count(int n) => find.byWidgetPredicate(
        (w) =>
            w is IndexCount &&
            w.count == n &&
            w.tooltip == es.f46P3TopicDocuments(n),
      );
      expect(count(2), findsNWidgets(2));
      expect(count(1), findsOneWidget);
    });

    testWidgets('un documento con dos temas está bajo cada uno y dice en qué '
        'otro está también (decisión D)', (tester) async {
      library();
      await harness.pump(tester);

      expect(find.text('Cleopatra'), findsNWidgets(2));
      // Cada fila nombra los otros temas, y nunca el suyo: bajo Egipto,
      // «también en Roma»; bajo Roma, «también en Egipto»; uno de un solo
      // tema, nada.
      List<String> also(String documentId) => [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: documentRow(documentId),
            matching: find.textContaining(es.f46P3AlsoIn('')),
          ),
        ))
          text.textSpan!.toPlainText(),
      ];
      expect(also('cleopatra'), [
        es.f46P3AlsoIn('Roma'),
        es.f46P3AlsoIn('Egipto'),
      ]);
      expect(also('historia'), isEmpty);
      expect(also('piramides'), isEmpty);
    });

    testWidgets('los capítulos se leen recién al desplegar el documento, y se '
        'ven con su nivel, los puntos y su página', (tester) async {
      library();
      await harness.pump(tester);
      expect(repo.calls, isNot(contains('entries:historia')));
      expect(indexEntry('La Monarquía'), findsNothing);

      await unfold(tester, 'historia');

      expect(repo.calls, contains('entries:historia'));
      expect(shownEntries(tester), [
        'La Monarquía',
        'La República',
        'Las guerras púnicas',
        'Aníbal en los Alpes',
      ]);
      final line = tester.renderObject<RenderBox>(indexEntry('La República'));
      final deeper = tester.renderObject<RenderBox>(
        indexEntry('Aníbal en los Alpes'),
      );
      // Más hondo, más corrido a la derecha.
      expect(
        deeper.localToGlobal(Offset.zero).dx,
        greaterThan(line.localToGlobal(Offset.zero).dx),
      );
      final page = tester.widget<IndexLeaderLine>(indexEntry('La República'));
      expect(page.page, es.f46P3TextPage(2));
    });

    testWidgets('un PDF lleva la página real (decisión C)', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'piramides');

      final guiza = tester.widget<IndexLeaderLine>(indexEntry('Guiza'));
      expect(guiza.page, es.f46P3PdfPage(10));
    });

    testWidgets('un texto sin títulos es una sola entrada, «Texto completo», '
        'sin puntos ni página', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'suelto');

      final whole = tester.widget<IndexLeaderLine>(
        indexEntry(es.f46P3WholeText),
      );
      expect(whole.page, isNull);

      // Abre el texto entero desde el comienzo, sin un lugar que resaltar
      // (F46, paso 4).
      await tester.tap(indexEntry(es.f46P3WholeText));
      await tester.pumpAndSettle();
      expect(find.text('lector ${readerFor('suelto')}'), findsOneWidget);
    });

    testWidgets('plegar un tema esconde sus documentos y deja de leerlos', (
      tester,
    ) async {
      library();
      await harness.pump(tester);
      expect(repo.watching['documentsOf:egipto'], 1);

      await tester.tap(find.text('EGIPTO'));
      await tester.pumpAndSettle();

      expect(find.text('Pirámides'), findsNothing);
      expect(repo.watching['documentsOf:egipto'], 0);

      await tester.tap(find.text('EGIPTO'));
      await tester.pumpAndSettle();
      expect(find.text('Pirámides'), findsOneWidget);
    });
  });

  group('los niveles y la numeración', () {
    testWidgets('«Niveles» decide hasta dónde se despliega, ⌄ abre uno solo y '
        '«Todo» muestra todos', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      await tester.tap(find.byKey(const ValueKey('index-depth-one')));
      await tester.pumpAndSettle();
      expect(shownEntries(tester), ['La Monarquía', 'La República']);

      // ⌄ de «La República»: se abre ella, y sus hijos quedan como dicen
      // los niveles —el de nivel 2 plegado—.
      await tester.tap(find.byKey(const ValueKey('index-fold-2')));
      await tester.pumpAndSettle();
      expect(shownEntries(tester), [
        'La Monarquía',
        'La República',
        'Las guerras púnicas',
      ]);

      await tester.tap(find.byKey(const ValueKey('index-depth-all')));
      await tester.pumpAndSettle();
      expect(shownEntries(tester), hasLength(4));
    });

    testWidgets('⋮ prende la numeración «1», «2.1», «2.1.1»', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      await tester.tap(find.byKey(const Key('index-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('index-numbering')));
      await tester.pumpAndSettle();

      for (final number in ['1', '2', '2.1', '2.1.1']) {
        expect(
          find.descendant(
            of: find.byType(IndexEntryRow),
            matching: find.text(number),
          ),
          findsOneWidget,
          reason: number,
        );
      }
    });

    testWidgets('lo elegido se recuerda para la próxima vez', (tester) async {
      library();
      await harness.pump(
        tester,
        prefs: {
          IndexViewController.prefsKey:
              '{"arrangement":"byDocument","order":"recent","depth":"one",'
              '"numbered":true}',
        },
      );

      final chip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('index-arrangement-byDocument')),
      );
      expect(chip.selected, isTrue);
      final depth = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('index-depth-one')),
      );
      expect(depth.selected, isTrue);
    });
  });

  group('por documento', () {
    testWidgets('todos, de la A a la Z y con sus temas; o los más recientes '
        'primero', (tester) async {
      library();
      repo.documents[0] = repo.documents[0].copyWith(
        createdAt: DateTime(2026, 6),
      );
      await harness.pump(tester);

      await tester.tap(
        find.byKey(const ValueKey('index-arrangement-byDocument')),
      );
      await tester.pumpAndSettle();

      double y(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(find.text('ROMA'), findsNothing);
      expect(y('Apuntes sueltos'), lessThan(y('Cleopatra')));
      expect(y('Cleopatra'), lessThan(y('Historia de Roma')));
      expect(find.text(es.f46P3InTopics('Roma, Egipto')), findsOneWidget);

      await tester.tap(find.byKey(const Key('index-sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<IndexDocumentOrder>,
          es.f46P3SortRecent,
        ),
      );
      await tester.pumpAndSettle();
      expect(y('Historia de Roma'), lessThan(y('Apuntes sueltos')));
    });
  });

  group('«Nuevo» y lo que todavía se indexa', () {
    testWidgets('«Nuevo» en lo que llegó hace menos de siete días, y no en lo '
        'de antes', (tester) async {
      repo.documents.addAll([
        indexDocument(
          'nuevo',
          'Recién llegado',
          createdAt: kIndexTestNow.subtract(const Duration(days: 3)),
        ),
        indexDocument(
          'viejo',
          'De hace tiempo',
          createdAt: kIndexTestNow.subtract(const Duration(days: 8)),
        ),
      ]);
      await harness.pump(tester);

      expect(
        find.descendant(
          of: documentRow('nuevo'),
          matching: find.textContaining(es.f46P3New),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: documentRow('viejo'),
          matching: find.textContaining(es.f46P3New),
        ),
        findsNothing,
      );
    });

    testWidgets('un documento que el relleno todavía no indexó lo dice, y '
        'desplegado también', (tester) async {
      repo.documents.add(
        indexDocument('pendiente', 'Pendiente', indexed: false),
      );
      await harness.pump(tester);

      expect(find.textContaining(es.f46P3Indexing), findsOneWidget);
      await unfold(tester, 'pendiente');
      expect(find.text(es.f46P3EntriesPending), findsOneWidget);
    });

    testWidgets('la línea de avance mientras se indexa lo que ya estaba, y se '
        'va al terminar', (tester) async {
      library();
      repo.progress = const IndexProgress(
        documents: 10,
        indexedDocuments: 3,
        untitledImages: 0,
      );
      await harness.pump(tester);

      expect(find.text(es.f46P3Progress(3, 10)), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('index-progress')),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, closeTo(0.3, 1e-9));

      repo
        ..progress = const IndexProgress(
          documents: 10,
          indexedDocuments: 10,
          untitledImages: 0,
        )
        ..changed();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('index-progress')), findsNothing);
    });
  });

  group('buscar', () {
    testWidgets('lo encontrado con su documento arriba y los capítulos que lo '
        'contienen, y lo buscado resaltado', (tester) async {
      library();
      await harness.pump(tester);

      await harness.search(tester, 'anib');

      expect(find.text('ROMA'), findsNothing);
      expect(find.text('Historia de Roma'), findsOneWidget);
      expect(shownEntries(tester), [
        'La República',
        'Las guerras púnicas',
        'Aníbal en los Alpes',
      ]);
      final hit = tester.widget<IndexLeaderLine>(
        indexEntry('Aníbal en los Alpes'),
      );
      final marked = <String>[];
      hit.title.visitChildren((span) {
        if (span is TextSpan && span.style?.backgroundColor != null) {
          marked.add(span.text!);
        }
        return true;
      });
      expect(marked, ['Aníb']);
    });

    testWidgets('los documentos cuyo título coincide van arriba, y tocarlos '
        'los abre desde el comienzo', (tester) async {
      library();
      await harness.pump(tester);

      await harness.search(tester, 'cleo');

      expect(find.text(es.f46P3SearchDocuments), findsOneWidget);
      await tester.tap(find.text('Cleopatra').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('docs=cleopatra'), findsOneWidget);
    });

    testWidgets('sin resultados lo dice; borrar la búsqueda vuelve al árbol '
        'como estaba', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      await harness.search(tester, 'zzz');
      expect(find.byKey(const Key('index-search-empty')), findsOneWidget);
      expect(find.text(es.f46P3SearchEmpty('zzz')), findsOneWidget);

      await tester.tap(find.byKey(const Key('index-search-clear')));
      await tester.pumpAndSettle();
      expect(indexEntry('La Monarquía'), findsOneWidget);
    });

    testWidgets('una búsqueda que llega al máximo lo dice', (tester) async {
      repo.documents.add(indexDocument('largo', 'Largo', chapters: 250));
      repo.entries['largo'] = indexChapters('largo', [
        for (var i = 0; i < 250; i++) (1, 'Sección $i'),
      ]);
      await harness.pump(tester);

      await harness.search(tester, 'seccion');
      await tester.scrollUntilVisible(
        find.text(es.f46P3SearchCapped(200)),
        800,
        maxScrolls: 100,
        scrollable: list(),
      );
      expect(find.text(es.f46P3SearchCapped(200)), findsOneWidget);
    });
  });

  group('en vivo', () {
    testWidgets('lo que llega aparece en su lugar y brilla; lo borrado se va; '
        'lo renombrado cambia; lo desplegado sigue desplegado', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      repo.documents.add(
        indexDocument('acueductos', 'Acueductos', spaces: ['roma']),
      );
      repo.changed();
      await tester.pump();
      await tester.pump();

      expect(find.text('Acueductos'), findsOneWidget);
      final glow = tester.widget<IndexGlow>(
        find
            .descendant(
              of: documentRow('acueductos'),
              matching: find.byType(IndexGlow),
            )
            .first,
      );
      expect(glow.arrivedAt, kIndexTestNow);
      final old = tester.widget<IndexGlow>(
        find
            .descendant(
              of: documentRow('historia').first,
              matching: find.byType(IndexGlow),
            )
            .first,
      );
      expect(old.arrivedAt, isNull);
      await tester.pumpAndSettle();

      repo.documents.removeWhere((d) => d.id == 'cleopatra');
      final at = repo.documents.indexWhere((d) => d.id == 'historia');
      repo.documents[at] = repo.documents[at].copyWith(title: 'Roma antigua');
      repo.changed();
      await tester.pumpAndSettle();

      expect(find.text('Cleopatra'), findsNothing);
      expect(find.text('Roma antigua'), findsOneWidget);
      expect(indexEntry('La Monarquía'), findsOneWidget);
    });

    testWidgets('un capítulo que cambia vuelve a dibujar su documento, y nada '
        'del otro desplegado', (tester) async {
      library();
      await harness.pump(tester);
      await unfold(tester, 'historia');
      await unfold(tester, 'piramides');
      final before = tester.widget(find.byKey(const ValueKey(30)));

      repo.entries['historia'] = [
        ...repo.entries['historia']!,
        ...indexChapters('historia', [(1, 'El Imperio')], firstKey: 9),
      ];
      repo.changed();
      await tester.pumpAndSettle();

      expect(indexEntry('El Imperio'), findsOneWidget);
      expect(tester.widget(find.byKey(const ValueKey(30))), same(before));
    });
  });

  group('lo fijo arriba', () {
    testWidgets('el tema y el documento quedan arriba mientras se recorren '
        'sus capítulos', (tester) async {
      repo.spaces['roma'] = 'Roma';
      repo.documents.add(
        indexDocument(
          'largo',
          'Un libro largo',
          spaces: ['roma'],
          chapters: 80,
        ),
      );
      repo.entries['largo'] = indexChapters('largo', [
        for (var i = 0; i < 80; i++) (1, 'Capítulo $i'),
      ]);
      await harness.pump(tester);
      await unfold(tester, 'largo');
      final listTop = tester.getBottomLeft(find.byType(IndexControls)).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await tester.pumpAndSettle();

      expect(indexEntry('Capítulo 0'), findsNothing);
      final topic = tester.getRect(find.text('ROMA'));
      final document = tester.getRect(find.text('Un libro largo'));
      expect(topic.top, lessThan(listTop));
      expect(document.top, greaterThan(topic.bottom));
      expect(document.top, lessThan(topic.bottom + 40));
    });
  });

  group('lo que abre una entrada', () {
    testWidgets('en un teléfono, el texto del documento en el lector único, '
        'justo en el título de la entrada (F46, paso 4); «atrás» vuelve al '
        'Índice como estaba, con la entrada marcada', (tester) async {
      library();
      final semantics = tester.ensureSemantics();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      await tester.tap(indexEntry('La República'));
      await tester.pumpAndSettle();
      // «La República» es el segundo capítulo: su título, de 100 a 112.
      const title = ExtractPlace(documentId: 'historia', start: 100, end: 112);
      expect(
        find.text('lector ${readerFor('historia', at: title)}'),
        findsOneWidget,
      );

      harness.router.pop();
      await tester.pumpAndSettle();
      expect(indexEntry('La República'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            RegExp('^${es.f46P3SemChapter(1, 'La República')}'),
          ),
        ),
        isSemantics(isSelected: true, hasSelectedState: true, isButton: true),
      );
      semantics.dispose();
    });

    testWidgets('una imagen se abre en su galería, en su lugar', (
      tester,
    ) async {
      repo.documents.add(
        indexDocument('fotos', 'Fotos', hasText: false, images: 3),
      );
      repo.entries['fotos'] = [
        indexImage('fotos', 1, position: 0, title: 'Coliseo'),
        indexImage('fotos', 2, position: 1),
        indexImage('fotos', 3, position: 2, title: 'Foro'),
      ];
      await harness.pump(
        tester,
        overrides: [
          processedImagesProvider.overrideWith(
            (ref, key) => const Stream.empty(),
          ),
        ],
      );
      await unfold(tester, 'fotos');
      expect(indexEntry(es.f46P3UntitledImage(2)), findsOneWidget);

      await tester.tap(indexEntry('Foro'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final viewer = tester.widget<ProcessedImageViewerScreen>(
        find.byType(ProcessedImageViewerScreen),
      );
      expect(viewer.documentId, 'fotos');
      expect(viewer.initialIndex, 2);
    });
  });

  group('en una pantalla ancha', () {
    const wide = Size(1280, 900);

    testWidgets('dos paneles: tocar un capítulo lo abre al lado, sin dejar el '
        'Índice, y ✕ lo cierra', (tester) async {
      library();
      await harness.pump(tester, size: wide);
      expect(find.byKey(const Key('index-pane-empty')), findsOneWidget);
      expect(find.text(es.f46P3PaneEmptyTitle), findsOneWidget);

      await unfold(tester, 'historia');
      await tester.tap(indexEntry('La República'));
      await tester.pumpAndSettle();

      expect(find.text('al lado historia 2'), findsOneWidget);
      expect(find.textContaining('lector'), findsNothing);
      expect(indexEntry('La República'), findsOneWidget);

      await tester.tap(find.text('cerrar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('index-pane-empty')), findsOneWidget);
    });

    testWidgets('con el teclado: Ctrl+F va al buscador, Tab recorre las filas, '
        '→ y ← despliegan y pliegan, Enter abre al lado', (tester) async {
      library();
      await harness.pump(tester, size: wide);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'index-search');

      Future<void> tabTo(Finder finder) async {
        for (var i = 0; i < 40 && !focusedIn(finder); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusedIn(finder), isTrue);
      }

      await tabTo(documentRow('historia'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(indexEntry('La Monarquía'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(indexEntry('La Monarquía'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tabTo(find.byKey(const ValueKey(2)));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('al lado historia 2'), findsOneWidget);
    });
  });

  group('para todos', () {
    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('a 360 dp con la letra al doble, tema $name: el árbol, un '
          'documento desplegado y la búsqueda entran sin desbordar', (
        tester,
      ) async {
        library();
        repo.documents.add(
          indexDocument(
            'titulo-largo',
            'Una historia muy larga de la República romana y de sus guerras '
                'contra Cartago',
            spaces: ['roma'],
            chapters: 1,
          ),
        );
        repo.entries['titulo-largo'] = indexChapters('titulo-largo', [
          (
            1,
            'Un capítulo con un título larguísimo que no entra en un renglón',
          ),
        ], firstKey: 70);
        await harness.pump(
          tester,
          size: const Size(360, 720),
          textScale: 2,
          theme: theme,
        );
        expect(tester.takeException(), isNull);

        await unfold(tester, 'titulo-largo');
        expect(tester.takeException(), isNull);

        await harness.search(tester, 'rep');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el lector de pantalla oye cada fila con su nivel y su página, '
        'y si está desplegada', (tester) async {
      library();
      final semantics = tester.ensureSemantics();
      await harness.pump(tester);
      await unfold(tester, 'historia');

      expect(
        tester.getSemantics(find.bySemanticsLabel(es.f46P3SemTopic('Roma', 2))),
        isSemantics(
          label: es.f46P3SemTopic('Roma', 2),
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      final chapter =
          '${es.f46P3SemChapter(2, 'Las guerras púnicas')}, '
          '${es.f46P3SemTextPage(3)}';
      expect(
        tester.getSemantics(find.bySemanticsLabel(chapter)),
        isSemantics(
          label: chapter,
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('de a lo que se ve', () {
    testWidgets('con muchos temas, solo se leen los documentos de los que '
        'están cerca de la pantalla; al bajar, los demás', (tester) async {
      for (var t = 0; t < 60; t++) {
        final id = 'tema$t';
        repo.spaces[id] = 'Tema ${t.toString().padLeft(2, '0')}';
        for (var d = 0; d < 10; d++) {
          repo.documents.add(
            indexDocument('$id-$d', 'Documento $t.$d', spaces: [id]),
          );
        }
      }
      await harness.pump(tester);

      final read = repo.calls
          .where((c) => c.startsWith('documentsOf:'))
          .toSet();
      expect(read.length, lessThan(6));
      expect(read, contains('documentsOf:tema0'));

      await tester.scrollUntilVisible(
        find.text('Documento 59.9'),
        2000,
        maxScrolls: 200,
        scrollable: list(),
      );
      expect(repo.calls, contains('documentsOf:tema59'));
    });
  });
}
