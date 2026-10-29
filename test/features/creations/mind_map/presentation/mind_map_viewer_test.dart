import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/chat/presentation/screens/chat_screen.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/mind_map/mind_map_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';
import 'package:sinapsis/features/processed/presentation/screens/processed_document_screen.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/processed_rows.dart';
import '../../presentation/repasar_harness.dart';

/// F43, paso 9: el visor del mapa mental —el árbol que se abre y se cierra,
/// el pellizco y los botones, la hoja de cada idea con «Preguntarle al
/// chat» y «Ver en el documento», y guardarlo como imagen—, en la app de
/// verdad con su router.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;

  const content = {
    'title': 'La salida de Egipto',
    'root': {
      'label': 'Éxodo',
      'children': [
        {
          'label': 'Las plagas',
          'note': 'Diez señales contra el Faraón.',
          'document_id': 'p-1',
          'source': 'Éxodo — Comentario',
          'quote': 'el Señor envió diez plagas sobre Egipto',
          'children': [
            {'label': 'El Nilo en sangre'},
            {'label': 'Las ranas'},
          ],
        },
        {
          'label': 'El mar se abre',
          'children': [
            {'label': 'El paso a pie seco'},
          ],
        },
        {'label': 'El Sinaí'},
      ],
    },
  };

  setUp(() async {
    harness = await RepasarHarness.create(specs: [mindMapKindSpec()]);
  });

  /// Un mapa listo sobre el documento p-1 (con [sourceItemId] como fuente).
  Future<StudyCreation> ready({
    Map<String, Object?> json = content,
    CreationScope scope = const CreationScope.document('p-1'),
    List<String> sources = const ['p-1'],
    String? sourceItemId,
  }) async {
    await insertProcessedRows(
      harness.library.database,
      id: 'p-1',
      title: 'Éxodo — Comentario',
      sourceItemId: sourceItemId,
      parts: const {
        ProcessedSection.text: ['Y el Señor envió diez plagas sobre Egipto.'],
      },
    );
    final queued = await harness.creation(
      StudyCreationKind.mindMap,
      scope: scope,
      sources: sources,
      status: CreationStatus.generating,
    );
    await harness.creations.complete(
      queued.id,
      title: 'La salida de Egipto',
      content: jsonEncode(json),
    );
    return queued;
  }

  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) => harness.openRepasar(
    tester,
    size: size,
    theme: theme,
    textScale: textScale,
    location: '/creations/${creation.id}',
  );

  Finder node(String id) => find.byKey(ValueKey('mind-map-node-$id'));
  Finder toggle(String id) => find.byKey(ValueKey('mind-map-toggle-$id'));

  double scale(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byKey(const Key('mind-map-viewport')))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  group('el árbol', () {
    testWidgets('abre con la idea central y sus ramas principales; lo de '
        'abajo, cerrado', (tester) async {
      final creation = await ready();
      await open(tester, creation);

      expect(find.text('Éxodo'), findsOneWidget);
      expect(find.text('Las plagas'), findsOneWidget);
      expect(find.text('El mar se abre'), findsOneWidget);
      expect(find.text('El Sinaí'), findsOneWidget);
      expect(find.text('El Nilo en sangre'), findsNothing);
      // La central abierta («‹»), las ramas con hijos cerradas («›»), las
      // hojas sin nada.
      expect(
        find.descendant(
          of: toggle('0'),
          matching: find.byIcon(Icons.chevron_left_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: toggle('0.0'),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
      expect(toggle('0.2'), findsNothing);
      // A la derecha de la central, en el orden de la IA.
      final root = tester.getRect(node('0'));
      final plagues = tester.getRect(node('0.0'));
      final sea = tester.getRect(node('0.1'));
      expect(plagues.left, greaterThan(root.right));
      expect(sea.top, greaterThan(plagues.bottom));
    });

    testWidgets('«›» abre una rama sin mover la idea de lugar, y otra vez la '
        'cierra', (tester) async {
      final creation = await ready();
      await open(tester, creation);

      final before = tester.getTopLeft(node('0.0'));
      await tester.tap(toggle('0.0'));
      await tester.pumpAndSettle();
      expect(find.text('El Nilo en sangre'), findsOneWidget);
      expect(find.text('Las ranas'), findsOneWidget);
      expect(tester.getTopLeft(node('0.0')), before);
      expect(
        tester.getRect(node('0.0.0')).left,
        greaterThan(tester.getRect(node('0.0')).right),
      );

      await tester.tap(toggle('0.0'));
      await tester.pumpAndSettle();
      expect(find.text('El Nilo en sangre'), findsNothing);
      expect(tester.getTopLeft(node('0.0')), before);
    });

    testWidgets('Ampliar todo abre todas las ramas; Contraer todo vuelve a las '
        'principales', (tester) async {
      final creation = await ready();
      await open(tester, creation);

      await tester.tap(find.byKey(const Key('mind-map-expand-all')));
      await tester.pumpAndSettle();
      for (final label in [
        'El Nilo en sangre',
        'Las ranas',
        'El paso a pie seco',
      ]) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('mind-map-collapse-all')));
      await tester.pumpAndSettle();
      expect(find.text('El Nilo en sangre'), findsNothing);
      expect(find.text('El paso a pie seco'), findsNothing);
      expect(find.text('Las plagas'), findsOneWidget);
    });

    testWidgets('acercar y alejar cambian la escala; ajustar la vuelve a '
        'encuadrar', (tester) async {
      final creation = await ready();
      await open(tester, creation);
      final fitted = scale(tester);

      await tester.tap(find.byKey(const Key('mind-map-zoom-in')));
      await tester.pump();
      expect(scale(tester), closeTo(fitted * 1.25, 1e-6));
      await tester.tap(find.byKey(const Key('mind-map-zoom-out')));
      await tester.tap(find.byKey(const Key('mind-map-zoom-out')));
      await tester.pump();
      expect(scale(tester), closeTo(fitted / 1.25, 1e-6));

      await tester.tap(find.byKey(const Key('mind-map-fit')));
      await tester.pump();
      // Encuadrado y centrado: el mapa entero entra en el visor.
      final viewport = tester.getRect(
        find.byKey(const Key('mind-map-viewport')),
      );
      for (final id in ['0', '0.0', '0.1', '0.2']) {
        final rect = tester.getRect(node(id));
        expect(viewport.contains(rect.topLeft), isTrue, reason: id);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: id);
      }
    });

    testWidgets('pellizcar acerca', (tester) async {
      final creation = await ready();
      await open(tester, creation);
      final fitted = scale(tester);
      final center = tester.getCenter(
        find.byKey(const Key('mind-map-viewport')),
      );
      final a = await tester.startGesture(center - const Offset(40, 0));
      final b = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      await a.moveBy(const Offset(-60, 0));
      await b.moveBy(const Offset(60, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(scale(tester), greaterThan(fitted * 1.5));
    });

    testWidgets('para el lector de pantalla: el nombre, el nivel y las ramas', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final creation = await ready();
      await open(tester, creation);

      expect(
        find.bySemanticsLabel(
          '${es.f43MindNodeLabel('Las plagas', 2)}. '
          '${es.f43MindNodeBranchesClosed(2)}',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(es.f43MindNodeLabel('El Sinaí', 2)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(es.f43MindOpenBranch), findsNWidgets(2));
      expect(find.bySemanticsLabel(es.f43MindCloseBranch), findsOneWidget);
      handle.dispose();
    });

    testWidgets('un mapa vacío lo dice', (tester) async {
      final creation = await ready(json: const {'nada': true});
      await open(tester, creation);
      expect(find.byKey(const Key('mind-map-empty')), findsOneWidget);
      expect(find.text(es.f43MindEmpty), findsOneWidget);
    });
  });

  group('tocar una idea', () {
    testWidgets('abre su hoja: el nombre, dónde está, la nota, el documento '
        'y el pasaje', (tester) async {
      final creation = await ready();
      await open(tester, creation);

      await tester.tap(find.text('Las plagas'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('mind-map-sheet-0.0'));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(es.f43MindInside('Éxodo')),
        ),
        findsOneWidget,
      );
      expect(find.text('Diez señales contra el Faraón.'), findsOneWidget);
      expect(find.text(es.f43MindFrom('Éxodo — Comentario')), findsOneWidget);
      expect(
        find.text('«el Señor envió diez plagas sobre Egipto»'),
        findsOneWidget,
      );
      expect(find.text(es.f43MindAskChat), findsOneWidget);
      expect(find.text(es.f43MindSeeInDocument), findsOneWidget);
    });

    testWidgets('«Preguntarle al chat sobre esto» abre el chat con la pregunta '
        'sobre la idea, con la de arriba y el documento', (tester) async {
      final creation = await ready();
      await open(tester, creation);
      await tester.tap(find.text('Las plagas'));
      await tester.pumpAndSettle();

      final question = es.f43MindAskDocIn(
        'Éxodo — Comentario',
        'Las plagas',
        'Éxodo',
      );
      // Antes de que el chat la tome, la pregunta espera con su recorte.
      await tester.tap(find.byKey(const Key('mind-map-ask-chat')));
      expect(
        harness.container.read(chatHandoffProvider),
        ChatHandoff(question: question),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      // El chat la tomó y la mandó.
      expect(harness.container.read(chatHandoffProvider), isNull);
      expect(find.text(question), findsWidgets);
    });

    testWidgets('sobre un cuaderno, la pregunta va acotada a él', (
      tester,
    ) async {
      final notebook = await harness.container
          .read(notebookRepositoryProvider)
          .create(name: 'Pentateuco', mode: NotebookMode.manual);
      final creation = await ready(scope: CreationScope.notebook(notebook.id));
      await open(tester, creation);
      await tester.tap(find.text('El Sinaí'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mind-map-ask-chat')));
      expect(
        harness.container.read(chatHandoffProvider),
        ChatHandoff(
          question: es.f43MindAskIn('El Sinaí', 'Éxodo'),
          notebookId: notebook.id,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('«Ver en el documento» abre la lectura de la fuente parada en '
        'el pasaje', (tester) async {
      final now = DateTime(2026, 10, 29);
      const text = 'Capítulo 7. Y el Señor envió diez plagas sobre Egipto.';
      await harness.container
          .read(libraryRepositoryProvider)
          .save(
            KnowledgeItem(
              id: 'src-1',
              title: 'Éxodo',
              source: Source(
                id: 'src-1',
                kind: SourceKind.webPage,
                capturedAt: now,
                url: 'https://e.org/exodo',
              ),
              processingState: ProcessingState.ready,
              createdAt: now,
              updatedAt: now,
              renditions: [
                Rendition.text(
                  id: 'rend-src-1',
                  itemId: 'src-1',
                  kind: RenditionKind.markdown,
                  content: text,
                  isPrimary: true,
                  createdAt: now,
                ),
              ],
            ),
          );
      final creation = await ready(sourceItemId: 'src-1');
      await open(tester, creation);
      await tester.tap(find.text('Las plagas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mind-map-see-document')));
      await tester.pumpAndSettle();

      const passage = 'el Señor envió diez plagas sobre Egipto';
      final start = text.indexOf(passage);
      final reading = tester.widget<ReadingScreen>(find.byType(ReadingScreen));
      expect(reading.itemId, 'src-1');
      expect(reading.jump, (start: start, end: start + passage.length));
    });

    testWidgets(
      'sin pasaje, «Ver en el documento» abre el documento procesado',
      (tester) async {
        final creation = await ready();
        await open(tester, creation);
        await tester.tap(find.text('El Sinaí'));
        await tester.pumpAndSettle();
        // Con una sola fuente, la idea es de ella aunque la IA no lo diga.
        expect(find.text(es.f43MindSeeInDocument), findsOneWidget);
        await tester.tap(find.byKey(const Key('mind-map-see-document')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ProcessedDocumentScreen>(
                find.byType(ProcessedDocumentScreen),
              )
              .documentId,
          'p-1',
        );
      },
    );

    testWidgets('con varias fuentes y una idea sin documento: «Ver las '
        'fuentes»', (tester) async {
      await harness.processed('p-2', 'Génesis');
      final creation = await ready(sources: const ['p-1', 'p-2']);
      await open(tester, creation);
      await tester.tap(find.text('El Sinaí'));
      await tester.pumpAndSettle();
      expect(find.text(es.f43MindSeeSources), findsOneWidget);
      expect(find.text(es.f43MindSeeInDocument), findsNothing);
    });
  });

  group('en cualquier pantalla', () {
    testWidgets('a 360 de ancho con la letra al doble, sin desbordes, y se '
        'abre igual', (tester) async {
      final creation = await ready();
      await open(tester, creation, size: const Size(360, 720), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('mind-map-expand-all')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('El paso a pie seco'), findsOneWidget);
      // La barra de abajo entra entera.
      final bar = tester.getRect(
        find.byKey(const Key('mind-map-collapse-all')),
      );
      expect(bar.right, lessThanOrEqualTo(360));
      expect(bar.left, greaterThanOrEqualTo(0));
    });

    for (final theme in AppThemeChoice.values) {
      testWidgets('en el tema ${theme.name}: se dibuja y la letra se lee sobre '
          'cada nivel', (tester) async {
        final creation = await ready();
        await open(tester, creation, theme: theme);
        await tester.tap(find.byKey(const Key('mind-map-expand-all')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['Éxodo', 'Las plagas', 'El Nilo en sangre']) {
          final text = tester.widget<Text>(find.text(label));
          final box = tester.widget<Material>(
            find
                .ancestor(of: find.text(label), matching: find.byType(Material))
                .first,
          );
          final ratio = _contrast(text.style!.color!, box.color!);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$label: $ratio');
        }
      });
    }
  });

  group('guardar como imagen', () {
    testWidgets('el botón de la barra guarda el PNG del árbol entero', (
      tester,
    ) async {
      final creation = await ready();
      await open(tester, creation);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('mind-map-save-image')));
        for (
          var i = 0;
          i < 50 && harness.library.fileSaver.savedBytes == null;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      final saver = harness.library.fileSaver;
      expect(saver.savedFileName, 'La salida de Egipto.png');
      final bytes = saver.savedBytes!;
      // La firma de un PNG.
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(
        find.text(es.f43StudioDownloaded('La salida de Egipto.png')),
        findsOneWidget,
      );
    });
  });
}

/// El contraste entre dos colores, como lo mide WCAG.
double _contrast(Color a, Color b) {
  final la = a.withValues(alpha: 1).computeLuminance();
  final lb = b.withValues(alpha: 1).computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
