import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/database/reference_reader.dart';
import 'package:sinapsis/core/domain/entities/contributor_role.dart';
import 'package:sinapsis/core/domain/entities/extracted_metadata.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reference/presentation/widgets/reference_section.dart';
import 'package:sinapsis/features/suggestions/presentation/providers/suggestion_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La tarjeta «Referencia» del detalle de una fuente (F15): sin datos invita a
/// completarlos; con datos muestra lo mínimo y pliega el resto; el formulario
/// pide lo que el tipo de obra usa y guarda de verdad, contra SQLite.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<KnowledgeItem> source(
    String id, {
    SourceKind kind = SourceKind.document,
    String title = 'Un libro',
    DateTime? publishedAt,
    String? url,
  }) async {
    await KnowledgeEntryWriter(harness.database).upsert(
      KnowledgeItem(
        id: id,
        title: title,
        source: Source(
          id: 'src-$id',
          kind: kind,
          capturedAt: DateTime(2026, 9, 11, 10),
          publishedAt: publishedAt,
          url: url,
        ),
        processingState: ProcessingState.ready,
        createdAt: DateTime(2026, 9, 11, 10),
        updatedAt: DateTime(2026, 9, 11, 10),
      ),
    );
    return (await harness.container
            .read(libraryRepositoryProvider)
            .findById(id))
        .getRight()
        .toNullable()!;
  }

  Future<void> pumpSection(WidgetTester tester, KnowledgeItem item) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, _) {
                final live = ref
                    .watch(libraryItemProvider(item.id))
                    .valueOrNull;
                return live == null
                    ? const SizedBox.shrink()
                    : ReferenceSection(item: live);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<ReferenceData> stored(String id) =>
      ReferenceReader(harness.database).read(id);

  Future<DateTime?> publishedAt(String id) async =>
      (await (harness.database.select(
        harness.database.knowledgeSources,
      )..where((s) => s.itemId.equals(id))).getSingle()).publishedAt;

  Future<void> enter(WidgetTester tester, Key key, String text) async {
    await tester.enterText(find.byKey(key), text);
    await tester.pump();
  }

  Future<void> chooseType(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('reference-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('reference-save')));
    await tester.tap(find.byKey(const Key('reference-save')));
    await tester.pumpAndSettle();
  }

  group('sin datos', () {
    testWidgets('dice qué se gana y ofrece completarla', (tester) async {
      await pumpSection(tester, await source('a'));

      expect(find.text(es.referenceSectionTitle), findsOneWidget);
      expect(find.text(es.referenceEmptyHint), findsOneWidget);
      expect(find.byKey(const Key('reference-complete')), findsOneWidget);
      expect(find.byKey(const Key('reference-edit')), findsNothing);
    });

    testWidgets('completarla abre el formulario, y cancelar lo cierra', (
      tester,
    ) async {
      await pumpSection(tester, await source('a'));

      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reference-type')), findsOneWidget);
      expect(find.byKey(const Key('reference-save')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reference-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reference-type')), findsNothing);
      expect(find.text(es.referenceEmptyHint), findsOneWidget);
    });

    testWidgets('cancelar no guarda nada', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await enter(tester, const Key('reference-year'), '1967');

      await tester.tap(find.byKey(const Key('reference-cancel')));
      await tester.pumpAndSettle();

      expect((await stored('a')).isEmpty, isTrue);
      expect(await publishedAt('a'), isNull);
    });
  });

  group('completar una obra', () {
    testWidgets('un libro: tipo, autor, fecha y editorial', (tester) async {
      await pumpSection(tester, await source('libro'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();

      await chooseType(tester, es.referenceTypeBook);
      await tester.tap(find.byKey(const Key('reference-add-author')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '').first,
        'García Márquez, Gabriel',
      );
      await enter(tester, const Key('reference-year'), '1967');
      await enter(
        tester,
        const Key('reference-field-publisher'),
        'Sudamericana',
      );
      await save(tester);

      final reference = await stored('libro');
      expect(reference.type, ReferenceType.book);
      expect(reference.publisher, 'Sudamericana');
      expect(reference.contributors.single.name.family, 'García Márquez');
      expect(reference.contributors.single.name.given, 'Gabriel');
      expect(reference.publicationPrecision, PublicationPrecision.year);
      expect(await publishedAt('libro'), DateTime(1967));
    });

    testWidgets('al guardar, vuelve a la vista con lo cargado', (tester) async {
      await pumpSection(tester, await source('libro'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await chooseType(tester, es.referenceTypeBook);
      await enter(
        tester,
        const Key('reference-field-publisher'),
        'Sudamericana',
      );

      await save(tester);

      expect(find.byKey(const Key('reference-type')), findsNothing);
      expect(find.text(es.referenceTypeBook), findsOneWidget);
      expect(find.text('Sudamericana'), findsOneWidget);
      expect(find.byKey(const Key('reference-edit')), findsOneWidget);
    });

    testWidgets('una fecha completa y una obra «sin fecha»', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await enter(tester, const Key('reference-year'), '2020');
      await enter(tester, const Key('reference-month'), '3');
      await enter(tester, const Key('reference-day'), '15');
      await save(tester);

      expect(await publishedAt('a'), DateTime(2020, 3, 15));
      expect(
        (await stored('a')).publicationPrecision,
        PublicationPrecision.day,
      );
      expect(find.text('2020-03-15'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reference-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reference-undated')));
      await tester.pumpAndSettle();
      await save(tester);

      expect(await publishedAt('a'), isNull);
      expect(
        (await stored('a')).publicationPrecision,
        PublicationPrecision.undated,
      );
      expect(find.text(es.referencePrecisionUndated), findsOneWidget);
    });

    testWidgets(
      'una institución no se parte, y las personas cambian de lugar',
      (tester) async {
        await pumpSection(tester, await source('a'));
        await tester.tap(find.byKey(const Key('reference-complete')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('reference-add-author')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reference-add-author')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('reference-person-field-0')),
          'Borges, Jorge Luis',
        );
        await tester.enterText(
          find.byKey(const Key('reference-person-field-1')),
          'Real Academia Española',
        );
        await tester.pump();
        // La segunda es una institución y sube al primer lugar.
        await tester.tap(find.byTooltip(es.referencePersonInstitution).last);
        await tester.pump();
        await tester.tap(find.byTooltip(es.referencePersonMoveUp).last);
        await tester.pump();
        await save(tester);

        final people = (await stored('a')).contributors;
        expect(people.map((c) => c.name.family), [
          'Real Academia Española',
          'Borges',
        ]);
        expect(people.first.name.isInstitution, isTrue);
        expect(people.last.name.isInstitution, isFalse);
      },
    );

    testWidgets('quitar una persona la saca de la lista', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reference-add-author')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '').first,
        'Borges, Jorge Luis',
      );
      await tester.pump();

      await tester.tap(find.byTooltip(es.referencePersonRemove));
      await tester.pumpAndSettle();
      await save(tester);

      expect((await stored('a')).contributors, isEmpty);
    });
  });

  group('lo que se pide de cada tipo', () {
    testWidgets('un artículo pide la revista y el volumen a la vista', (
      tester,
    ) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();

      await chooseType(tester, es.referenceTypeArticle);

      expect(find.text(es.referenceContainerJournal), findsOneWidget);
      expect(
        find.byKey(const Key('reference-field-container')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reference-field-volume')), findsOneWidget);
      // Lo demás, plegado.
      expect(find.byKey(const Key('reference-field-pages')), findsNothing);
      expect(find.byKey(const Key('reference-more-form')), findsOneWidget);
    });

    testWidgets('«Más datos» se despliega con lo del tipo', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await chooseType(tester, es.referenceTypeArticle);

      await tester.ensureVisible(find.byKey(const Key('reference-more-form')));
      await tester.tap(find.text(es.referenceMoreData));
      await tester.pumpAndSettle();

      for (final field in ['pages', 'issue', 'doi', 'issn', 'citationKey']) {
        expect(
          find.byKey(Key('reference-field-$field')),
          findsOneWidget,
          reason: field,
        );
      }
      expect(find.byKey(const Key('reference-field-isbn')), findsNothing);
    });

    testWidgets('un capítulo pide también a quien editó el libro', (
      tester,
    ) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();

      await chooseType(tester, es.referenceTypeChapter);

      expect(find.byKey(const Key('reference-add-author')), findsOneWidget);
      expect(find.byKey(const Key('reference-add-editor')), findsOneWidget);
      expect(find.byKey(const Key('reference-add-translator')), findsOneWidget);
      expect(find.byKey(const Key('reference-add-director')), findsNothing);
      expect(find.text(es.referenceContainerBook), findsOneWidget);
    });

    testWidgets('una tesis pide la universidad', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();

      await chooseType(tester, es.referenceTypeThesis);

      expect(find.text(es.referencePublisherUniversity), findsOneWidget);
    });

    testWidgets('una página web sin tipo se pide como un sitio web', (
      tester,
    ) async {
      final page = await source(
        'web',
        kind: SourceKind.webPage,
        url: 'https://sitio.org/a',
      );
      await pumpSection(tester, page);
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();

      expect(find.text(es.referenceContainerSite), findsOneWidget);
    });

    testWidgets(
      'lo que la obra ya tiene no se esconde aunque su tipo no lo use',
      (tester) async {
        final book = await source('libro');
        await KnowledgeEntryWriter(harness.database).setReference(
          'libro',
          const ReferenceData(
            type: ReferenceType.book,
            publisher: 'Editorial',
            issn: '1234-5679',
          ),
        );
        await pumpSection(tester, book);
        await tester.tap(find.byKey(const Key('reference-edit')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('reference-field-issn')), findsOneWidget);
        expect(find.text('1234-5679'), findsOneWidget);
      },
    );
  });

  group('con datos', () {
    testWidgets('lo mínimo a la vista y el resto plegado', (tester) async {
      final article = await source('art');
      await KnowledgeEntryWriter(harness.database).setReference(
        'art',
        const ReferenceData(
          type: ReferenceType.article,
          containerTitle: 'Revista de Datos',
          volume: '8',
          pages: '207-217',
          doi: '10.1000/xyz',
          contributors: [
            Contributor(
              name: PersonName(family: 'Ruiz', given: 'Ana'),
            ),
            Contributor(
              name: PersonName(family: 'Paz', given: 'Luis'),
              role: ContributorRole.translator,
            ),
          ],
        ),
      );
      await pumpSection(tester, article);

      expect(find.text(es.referenceTypeArticle), findsOneWidget);
      expect(find.text('Ruiz, Ana'), findsOneWidget);
      expect(find.text('Paz, Luis'), findsOneWidget);
      expect(find.text('Revista de Datos'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      // Plegado.
      expect(find.text('207-217'), findsNothing);
      expect(find.text('10.1000/xyz'), findsNothing);

      await tester.tap(find.byKey(const Key('reference-more')));
      await tester.pumpAndSettle();

      expect(find.text('207-217'), findsOneWidget);
      expect(find.text('10.1000/xyz'), findsOneWidget);
    });

    testWidgets('sin tipo dice que no lo tiene', (tester) async {
      final item = await source('a');
      await KnowledgeEntryWriter(
        harness.database,
      ).setReference('a', const ReferenceData(publisher: 'Editorial'));
      await pumpSection(tester, item);

      expect(find.text(es.referenceNoType), findsOneWidget);
    });

    testWidgets('la fecha de captura de una página se ve como fecha', (
      tester,
    ) async {
      final page = await source(
        'web',
        kind: SourceKind.webPage,
        publishedAt: DateTime(2020, 6),
        url: 'https://sitio.org/a',
      );
      await pumpSection(tester, page);

      // Sin exactitud guardada, una fecha capturada es de día completo.
      expect(find.text('2020-06-01'), findsOneWidget);
    });

    testWidgets('editar parte de lo guardado y cambia lo que se cambia', (
      tester,
    ) async {
      final book = await source('libro', publishedAt: DateTime(1967));
      await KnowledgeEntryWriter(harness.database).setReference(
        'libro',
        const ReferenceData(
          type: ReferenceType.book,
          publisher: 'Sudamericana',
          publicationPrecision: PublicationPrecision.year,
          contributors: [
            Contributor(
              name: PersonName(family: 'García Márquez', given: 'Gabriel'),
            ),
          ],
        ),
      );
      await pumpSection(tester, book);

      await tester.tap(find.byKey(const Key('reference-edit')));
      await tester.pumpAndSettle();

      expect(find.text('García Márquez, Gabriel'), findsOneWidget);
      expect(find.text('Sudamericana'), findsOneWidget);
      expect(find.text('1967'), findsOneWidget);

      await enter(
        tester,
        const Key('reference-field-publisher'),
        'Oveja Negra',
      );
      await save(tester);

      final reference = await stored('libro');
      expect(reference.publisher, 'Oveja Negra');
      expect(reference.contributors.single.name.family, 'García Márquez');
      // La fecha no se tocó: sigue como estaba.
      expect(await publishedAt('libro'), DateTime(1967));
    });
  });

  group('lo que no se puede guardar', () {
    testWidgets('un DOI que no vale se marca y no se guarda', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await chooseType(tester, es.referenceTypeBook);
      await tester.ensureVisible(find.byKey(const Key('reference-more-form')));
      await tester.tap(find.text(es.referenceMoreData));
      await tester.pumpAndSettle();
      await enter(tester, const Key('reference-field-doi'), 'no es un doi');

      await save(tester);

      expect(find.text(es.referenceErrorDoi), findsOneWidget);
      expect(find.byKey(const Key('reference-save')), findsOneWidget);
      expect((await stored('a')).isEmpty, isTrue);
    });

    testWidgets('una fecha que no existe se marca y no se guarda', (
      tester,
    ) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await enter(tester, const Key('reference-year'), '2023');
      await enter(tester, const Key('reference-month'), '2');
      await enter(tester, const Key('reference-day'), '30');

      await save(tester);

      expect(find.byKey(const Key('reference-error-date')), findsOneWidget);
      expect(find.text(es.referenceErrorDate), findsOneWidget);
      expect(await publishedAt('a'), isNull);
    });

    testWidgets('corregido el error, se guarda', (tester) async {
      await pumpSection(tester, await source('a'));
      await tester.tap(find.byKey(const Key('reference-complete')));
      await tester.pumpAndSettle();
      await enter(tester, const Key('reference-year'), 'mil');
      await save(tester);
      expect(find.byKey(const Key('reference-error-date')), findsOneWidget);

      await enter(tester, const Key('reference-year'), '1967');
      await save(tester);

      expect(find.byKey(const Key('reference-type')), findsNothing);
      expect(await publishedAt('a'), DateTime(1967));
    });
  });

  group('sugerencia de referencia (F15)', () {
    Future<void> seedSuggestion(String itemId, {String doi = '10.1000/xyz'}) =>
        harness.container
            .read(suggestionRepositoryProvider)
            .createMetadataSuggestion(
              targetItemId: itemId,
              extracted: ExtractedMetadata(
                reference: ReferenceData(
                  contributors: const [
                    Contributor(
                      name: PersonName(family: 'García', given: 'Ana'),
                    ),
                  ],
                  doi: doi,
                ),
              ),
            );

    testWidgets('con una pendiente, se ve el aviso con lo que trae', (
      tester,
    ) async {
      final item = await source('a');
      await seedSuggestion(item.id);

      await pumpSection(tester, item);

      expect(find.text(es.referenceSuggestionBanner), findsOneWidget);
      expect(find.byKey(const Key('metadata-suggestion-use')), findsOneWidget);
      expect(
        find.byKey(const Key('metadata-suggestion-discard')),
        findsOneWidget,
      );
    });

    testWidgets('usarla completa lo que la referencia no tenía', (
      tester,
    ) async {
      final item = await source('a');
      await seedSuggestion(item.id);
      await pumpSection(tester, item);

      await tester.tap(find.byKey(const Key('metadata-suggestion-use')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('metadata-suggestion-use')), findsNothing);
      final reference = await stored('a');
      expect(reference.doi, '10.1000/xyz');
      expect(reference.contributors.single.name.family, 'García');
    });

    testWidgets('descartarla no escribe nada y la saca de la vista', (
      tester,
    ) async {
      final item = await source('a');
      await seedSuggestion(item.id);
      await pumpSection(tester, item);

      await tester.tap(find.byKey(const Key('metadata-suggestion-discard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('metadata-suggestion-discard')),
        findsNothing,
      );
      expect((await stored('a')).isEmpty, isTrue);
    });

    testWidgets('sin ninguna pendiente, no se ve nada', (tester) async {
      await pumpSection(tester, await source('a'));

      expect(find.text(es.referenceSuggestionBanner), findsNothing);
    });
  });
}
