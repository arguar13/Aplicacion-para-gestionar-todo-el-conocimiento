import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/health/domain/entities/health_thresholds.dart';
import 'package:sinapsis/features/health/presentation/widgets/health_panel.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/features/vocabulary/domain/entities/vocabulary_stats.dart';
import 'package:sinapsis/features/vocabulary/presentation/providers/vocabulary_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;
  late AppDatabase db;
  var counter = 0;

  setUp(() async {
    harness = await LibraryHarness.create();
    db = harness.database;
    counter = 0;
  });

  /// Guarda una fuente ya "procesada": lo que espera en la Bandeja.
  Future<void> seedPendingSource() async {
    final n = counter++;
    final now = DateTime(2026, 9, 11, 10);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: 'fuente-$n',
            title: 'Fuente $n',
            source: Source(
              id: 'src-$n',
              kind: SourceKind.webPage,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            // Con texto: es lo que la hace entrar a la Bandeja (F30,
            // decisión 68).
            renditions: [
              Rendition.text(
                id: 'texto-$n',
                itemId: 'fuente-$n',
                kind: RenditionKind.plainText,
                content: 'El texto de la fuente $n.',
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
  }

  Future<String> seedNote({
    NoteKind kind = NoteKind.living,
    NoteMaturity maturity = NoteMaturity.seed,
    String text = 'texto',
  }) async {
    final n = counter++;
    final id = 'nota-$n';
    final now = DateTime(2026, 9, 11, 10);
    await harness.container
        .read(libraryRepositoryProvider)
        .save(
          KnowledgeItem(
            id: id,
            title: 'Nota $n',
            source: Source(
              id: 'src-$id',
              kind: SourceKind.manualNote,
              capturedAt: now,
            ),
            processingState: ProcessingState.ready,
            createdAt: now,
            updatedAt: now,
            renditions: [
              Rendition.text(
                id: 'rend-$id',
                itemId: id,
                kind: RenditionKind.blocks,
                content: encodeContentBlocks([
                  ContentBlock.paragraph(text: text),
                ]),
                isPrimary: true,
                createdAt: now,
              ),
            ],
          ),
        );
    await (db.update(
      db.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(noteKind: Value(kind), maturity: Value(maturity)),
    );
    return id;
  }

  Future<void> contradict(String from, String to, {bool reviewed = false}) =>
      harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: from,
            toItemId: to,
            kind: RelationKind.contradicts,
          )
          .then((_) async {
            if (!reviewed) return;
            // Solo la que se acaba de crear: las demás siguen sin revisar.
            await (db.update(db.relations)..where(
                  (r) => r.fromItemId.equals(from) & r.toItemId.equals(to),
                ))
                .write(
                  RelationsCompanion(reviewedAt: Value(DateTime(2026, 9, 11))),
                );
          });

  MergeCandidateGroup vocabularyGroup(int n) => MergeCandidateGroup(
    values: [
      VocabularyValueStat(
        id: 'v$n',
        label: 'Valor $n',
        definitionId: 'def',
        definitionName: 'Región',
        isText: true,
        usage: 1,
        aliasCount: 0,
      ),
    ],
    pairs: const [],
  );

  /// El panel dentro de un router mínimo, con una pantalla de mentira en cada
  /// destino: lo que se prueba es adónde lleva cada indicador. El provider de
  /// candidatos de vocabulario se sobrescribe porque calcula en un isolate,
  /// que no corre bajo el reloj simulado.
  Future<void> pumpPanel(
    WidgetTester tester, {
    int vocabularyGroups = 0,
    bool expanded = true,
  }) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    GoRoute route(String path) => GoRoute(
      path: path,
      builder: (_, _) => Scaffold(body: Text('destino $path')),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: HealthPanel(initiallyExpanded: expanded),
            ),
          ),
        ),
        for (final path in [
          RoutePaths.inbox,
          RoutePaths.grownNotes,
          RoutePaths.vocabulary,
          RoutePaths.graphTension,
          RoutePaths.brokenLinks,
          RoutePaths.suggestionReview,
        ])
          route(path),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
          overrides: [
            mergeCandidateGroupsProvider.overrideWith(
              (ref) async => [
                for (var i = 0; i < vocabularyGroups; i++) vocabularyGroup(i),
              ],
            ),
          ],
          child: MaterialApp.router(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// La tarjeta de un indicador: lo que se toca.
  Finder tile(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  Finder inTile(String label, Finder what) =>
      find.descendant(of: tile(label), matching: what);

  testWidgets('muestra los cuatro indicadores con lo que hay en la bóveda', (
    tester,
  ) async {
    await seedPendingSource();
    await seedPendingSource();
    await seedPendingSource();
    final a = await seedNote(maturity: NoteMaturity.developing);
    final b = await seedNote(maturity: NoteMaturity.developing);
    await seedNote();
    await seedNote(kind: NoteKind.atomic, maturity: NoteMaturity.mature);
    await contradict(a, b);
    await contradict(b, a, reviewed: true);

    await pumpPanel(tester, vocabularyGroups: 5);

    expect(find.text(es.healthPanelTitle), findsOneWidget);
    // Bandeja: las tres fuentes.
    expect(inTile(es.healthInboxLabel, find.text('3')), findsOneWidget);
    // Notas: 1 semilla, 2 en desarrollo, 1 madura; 1 atómica y 3 vivas.
    expect(
      inTile(es.healthNotesLabel, find.text(es.healthNotesKinds(1, 3))),
      findsOneWidget,
    );
    expect(inTile(es.healthNotesLabel, find.text('2')), findsOneWidget);
    expect(
      inTile(es.healthNotesLabel, find.text(es.noteMaturityMature)),
      findsOneWidget,
    );
    // Vocabulario: los cinco grupos.
    expect(inTile(es.healthVocabularyLabel, find.text('5')), findsOneWidget);
    // Contradicciones: una sin revisar.
    expect(
      inTile(es.healthContradictionsLabel, find.text('1')),
      findsOneWidget,
    );
    expect(find.text(es.healthInboxWarning), findsNothing);
    expect(find.text(es.healthNotesWarning), findsNothing);
  });

  testWidgets('la Bandeja pasa el umbral: se pinta en alerta y lo dice', (
    tester,
  ) async {
    for (var i = 0; i < kInboxWarningThreshold + 1; i++) {
      await seedPendingSource();
    }

    await pumpPanel(tester);

    expect(find.text(es.healthInboxWarning), findsOneWidget);
    expect(
      inTile(es.healthInboxLabel, find.text('${kInboxWarningThreshold + 1}')),
      findsOneWidget,
    );
  });

  testWidgets('justo en el umbral de la Bandeja no avisa', (tester) async {
    for (var i = 0; i < kInboxWarningThreshold; i++) {
      await seedPendingSource();
    }

    await pumpPanel(tester);

    expect(find.text(es.healthInboxWarning), findsNothing);
  });

  testWidgets('muchas atómicas y pocas vivas: avisa que se acumulan '
      'fragmentos', (tester) async {
    for (var i = 0; i < kFragmentWarningMinAtomic; i++) {
      await seedNote(kind: NoteKind.atomic);
    }
    await seedNote();

    await pumpPanel(tester);

    expect(find.text(es.healthNotesWarning), findsOneWidget);
    expect(
      find.text(es.healthNotesKinds(kFragmentWarningMinAtomic, 1)),
      findsOneWidget,
    );
  });

  testWidgets('mientras algo se calcula muestra "…", sin animar nada', (
    tester,
  ) async {
    // El provider de vocabulario nunca responde: lo que se ve es el "…".
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: ProviderScope(
          overrides: [
            mergeCandidateGroupsProvider.overrideWith(
              (ref) => Future<List<MergeCandidateGroup>>.delayed(
                const Duration(days: 1),
                () => const [],
              ),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: HealthPanel(initiallyExpanded: true)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(inTile(es.healthVocabularyLabel, find.text('…')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Se deshace el temporizador pendiente para que la prueba pueda cerrar.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(days: 2));
  });

  group('cada indicador lleva a la pantalla donde se actúa', () {
    testWidgets('la Bandeja lleva a la Bandeja', (tester) async {
      await pumpPanel(tester);

      await tester.tap(tile(es.healthInboxLabel));
      await tester.pumpAndSettle();

      expect(find.text('destino ${RoutePaths.inbox}'), findsOneWidget);
    });

    testWidgets('las notas por madurez llevan a las notas que crecieron', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.tap(tile(es.healthNotesLabel));
      await tester.pumpAndSettle();

      expect(find.text('destino ${RoutePaths.grownNotes}'), findsOneWidget);
    });

    testWidgets('el vocabulario lleva a Vocabulario', (tester) async {
      await pumpPanel(tester);

      await tester.tap(tile(es.healthVocabularyLabel));
      await tester.pumpAndSettle();

      expect(find.text('destino ${RoutePaths.vocabulary}'), findsOneWidget);
    });

    testWidgets('las contradicciones llevan a Tensión', (tester) async {
      await pumpPanel(tester);

      await tester.tap(tile(es.healthContradictionsLabel));
      await tester.pumpAndSettle();

      expect(find.text('destino ${RoutePaths.graphTension}'), findsOneWidget);
    });
  });

  group('los accesos a lo demás', () {
    testWidgets('las notas que crecieron, con cuántas son', (tester) async {
      await pumpPanel(tester);
      expect(find.text(es.healthGrownNotes(0)), findsOneWidget);

      await tester.tap(find.text(es.healthGrownNotes(0)));
      await tester.pumpAndSettle();

      expect(find.text('destino ${RoutePaths.grownNotes}'), findsOneWidget);
    });

    testWidgets('los enlaces rotos, con cuántos hay', (tester) async {
      await seedNote(text: '[[Cartago]] y [[Atenas]]');
      await pumpPanel(tester);
      expect(find.text(es.healthBrokenLinks(2)), findsOneWidget);

      await tester.tap(find.text(es.healthBrokenLinks(2)));
      await tester.pumpAndSettle();

      expect(find.text('destino ${RoutePaths.brokenLinks}'), findsOneWidget);
    });

    testWidgets('las sugerencias pendientes, sumando todos los grupos', (
      tester,
    ) async {
      final definition =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreatePropertyDefinition('Región'))
              .getRight()
              .toNullable()!;
      final suggestions = harness.container.read(suggestionRepositoryProvider);
      for (final value in ['Roma', 'Roma', 'Cartago']) {
        final item = await seedNote();
        await suggestions.createPropertySuggestion(
          targetItemId: item,
          definitionId: definition.id,
          definitionName: 'Región',
          value: value,
          isNewValue: true,
        );
      }
      await pumpPanel(tester);
      expect(find.text(es.healthSuggestions(3)), findsOneWidget);

      await tester.tap(find.text(es.healthSuggestions(3)));
      await tester.pumpAndSettle();

      expect(
        find.text('destino ${RoutePaths.suggestionReview}'),
        findsOneWidget,
      );
    });
  });

  testWidgets('se pliega y se despliega', (tester) async {
    await pumpPanel(tester);
    expect(find.text(es.healthInboxLabel), findsOneWidget);
    expect(find.text(es.healthPanelTitle), findsOneWidget);

    await tester.tap(find.byTooltip(es.healthPanelHide));
    await tester.pumpAndSettle();
    expect(find.text(es.healthInboxLabel), findsNothing);

    await tester.tap(find.byTooltip(es.healthPanelShow));
    await tester.pumpAndSettle();
    expect(find.text(es.healthInboxLabel), findsOneWidget);
  });

  group('plegado, que es como arranca', () {
    /// La píldora de un indicador: lo que se ve y se toca con el panel plegado.
    Finder pill(String tooltip) => find.byTooltip(tooltip);

    testWidgets('muestra los cuatro números a la vista, sin desplegar nada', (
      tester,
    ) async {
      await seedPendingSource();
      await seedPendingSource();
      final a = await seedNote(maturity: NoteMaturity.developing);
      final b = await seedNote();
      await seedNote(kind: NoteKind.atomic);
      await contradict(a, b);

      await pumpPanel(tester, vocabularyGroups: 4, expanded: false);

      expect(
        find.descendant(
          of: pill(es.healthInboxLabel),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      // Notas: las tres que hay, de cualquier subtipo.
      expect(
        find.descendant(
          of: pill(es.healthNotesLabel),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pill(es.healthVocabularyLabel),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: pill(es.healthContradictionsLabel),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      // Y nada más: ni tarjetas ni accesos hasta que se despliegue.
      expect(find.text(es.healthInboxLabel), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.byTooltip(es.healthPanelShow), findsOneWidget);
    });

    testWidgets('cada píldora lleva a la misma pantalla que su tarjeta', (
      tester,
    ) async {
      final destinations = {
        es.healthInboxLabel: RoutePaths.inbox,
        es.healthNotesLabel: RoutePaths.grownNotes,
        es.healthVocabularyLabel: RoutePaths.vocabulary,
        es.healthContradictionsLabel: RoutePaths.graphTension,
      };

      for (final MapEntry(key: label, value: path) in destinations.entries) {
        await pumpPanel(tester, expanded: false);

        await tester.tap(pill(label));
        await tester.pumpAndSettle();

        expect(find.text('destino $path'), findsOneWidget, reason: label);
      }
    });

    testWidgets('la píldora de la Bandeja también se pinta en alerta', (
      tester,
    ) async {
      for (var i = 0; i < kInboxWarningThreshold + 1; i++) {
        await seedPendingSource();
      }

      await pumpPanel(tester, expanded: false);

      final material = tester.widget<Material>(
        find
            .descendant(
              of: pill(es.healthInboxLabel),
              matching: find.byType(Material),
            )
            .first,
      );
      final scheme = Theme.of(
        tester.element(pill(es.healthInboxLabel)),
      ).colorScheme;
      expect(material.color, scheme.errorContainer);
    });

    testWidgets('no desborda en una pantalla muy angosta', (tester) async {
      await pumpPanel(tester, expanded: false);
      tester.view.physicalSize = const Size(240, 800);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('desplegado nunca pasa de la mitad del alto: la lista de '
        'abajo sigue teniendo lugar', (tester) async {
      await pumpPanel(tester);
      final natural = tester.getSize(find.byType(HealthPanel)).height;

      // `pumpPanel` fija su propia ventana: la baja se aplica después.
      tester.view.physicalSize = const Size(400, 500);
      await tester.pumpAndSettle();
      final bounded = tester.getSize(find.byType(HealthPanel)).height;

      expect(natural, greaterThan(500 * 0.5));
      // La mitad del alto para el cuerpo, más la cabecera y los márgenes.
      expect(bounded, lessThanOrEqualTo(500 * 0.5 + 80));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('se actualiza solo cuando algo cambia en la bóveda', (
    tester,
  ) async {
    await pumpPanel(tester);
    expect(inTile(es.healthInboxLabel, find.text('0')), findsOneWidget);

    await seedPendingSource();
    await tester.pumpAndSettle();

    expect(inTile(es.healthInboxLabel, find.text('1')), findsOneWidget);
  });
}
