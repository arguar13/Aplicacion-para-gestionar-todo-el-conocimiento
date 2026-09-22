import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/person_name.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/publication_date.dart';
import 'package:sinapsis/core/domain/entities/reference_data.dart';
import 'package:sinapsis/core/domain/entities/reference_type.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/citations/presentation/providers/citation_preferences.dart';
import 'package:sinapsis/features/citations/presentation/widgets/citation_section.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La sección de cita del detalle (F15): la cita de la fuente en el estilo, el
/// idioma y la forma que se elijan, con lo que falta a la vista y copiable como
/// texto o con sus cursivas. Contra SQLite real.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Una fuente con [reference] guardada y devuelta como la ve el detalle.
  Future<KnowledgeItem> source(
    String id, {
    ReferenceData reference = const ReferenceData(),
    String title = 'Cien años de soledad',
    DateTime? publishedAt,
    SourceKind kind = SourceKind.document,
    String? url,
  }) async {
    final writer = KnowledgeEntryWriter(harness.database);
    await writer.upsert(
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
    if (!reference.isEmpty) await writer.setReference(id, reference);
    return (await harness.container
            .read(libraryRepositoryProvider)
            .findById(id))
        .getRight()
        .toNullable()!;
  }

  const book = ReferenceData(
    type: ReferenceType.book,
    publisher: 'Sudamericana',
    publicationPrecision: PublicationPrecision.year,
    contributors: [
      Contributor(
        name: PersonName(family: 'García Márquez', given: 'Gabriel'),
      ),
    ],
  );

  Future<List<String>> pumpSection(
    WidgetTester tester,
    KnowledgeItem item,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.view.physicalSize = const Size(800, 2400);
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
                    : CitationSection(item: live);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return copied;
  }

  /// Lo que dice la cita que se está mostrando.
  String shown(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const Key('citation-text')))
      .textSpan!
      .toPlainText();

  Future<void> chooseStyle(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const Key('citation-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  group('la cita', () {
    testWidgets('APA por defecto, con lo que la fuente tiene', (tester) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);

      expect(find.text(es.citationTitle), findsOneWidget);
      expect(
        shown(tester),
        'García Márquez, G. (1967). Cien años de soledad. Sudamericana.',
      );
      expect(find.byKey(const Key('citation-gaps')), findsNothing);
    });

    testWidgets('las cursivas del estilo se muestran en cursiva', (
      tester,
    ) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);

      final span = tester
          .widget<SelectableText>(find.byKey(const Key('citation-text')))
          .textSpan!;
      final italics = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan && child.style?.fontStyle == FontStyle.italic) {
          italics.add(child.text!);
        }
        return true;
      });

      expect(italics, ['Cien años de soledad']);
    });

    testWidgets('lo que falta se ve resaltado, con su nombre', (tester) async {
      final item = await source('libro');
      await pumpSection(tester, item);

      expect(shown(tester), contains('[falta: autor]'));
      expect(shown(tester), contains('[falta: año]'));
      expect(shown(tester), contains('[falta: tipo de obra]'));
      expect(
        find.text(es.citationMissingData('Autor, Año, Tipo de obra')),
        findsOneWidget,
      );

      final span = tester
          .widget<SelectableText>(find.byKey(const Key('citation-text')))
          .textSpan!;
      final highlighted = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan && child.style?.backgroundColor != null) {
          highlighted.add(child.text!);
        }
        return true;
      });
      expect(highlighted, contains('[falta: autor]'));
    });

    testWidgets('una página web con su enlace se cita sin datos cargados', (
      tester,
    ) async {
      final item = await source(
        'web',
        kind: SourceKind.webPage,
        title: 'Una página',
        url: 'https://sitio.org/a',
        publishedAt: DateTime(2020, 3, 15),
      );
      await pumpSection(tester, item);

      expect(shown(tester), contains('(2020, 15 de marzo)'));
      expect(shown(tester), endsWith('https://sitio.org/a'));
    });
  });

  group('el estilo', () {
    testWidgets('elegir otro cambia la cita', (tester) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);

      await chooseStyle(tester, 'MLA 9');

      expect(
        shown(tester),
        'García Márquez, Gabriel. Cien años de soledad. Sudamericana, 1967.',
      );

      await chooseStyle(tester, 'IEEE');

      expect(
        shown(tester),
        'G. García Márquez, Cien años de soledad. Sudamericana, 1967.',
      );
    });

    testWidgets('los dos sistemas de Chicago llevan su explicación', (
      tester,
    ) async {
      final item = await source('libro', reference: book);
      await pumpSection(tester, item);

      await tester.tap(find.byKey(const Key('citation-style')));
      await tester.pumpAndSettle();

      expect(find.text(es.citationStyleChicagoNotes), findsWidgets);
      expect(find.text(es.citationStyleChicagoAuthorDate), findsWidgets);
    });

    testWidgets('lo predeterminado sale de lo que Ajustes recuerda', (
      tester,
    ) async {
      await harness.container
          .read(citationPreferencesProvider.notifier)
          .setStyle('mla9');
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);

      expect(shown(tester), startsWith('García Márquez, Gabriel. '));
    });

    testWidgets('elegir otro estilo acá no cambia lo predeterminado', (
      tester,
    ) async {
      final item = await source('libro', reference: book);
      await pumpSection(tester, item);

      await chooseStyle(tester, 'MLA 9');

      expect(
        harness.container.read(citationPreferencesProvider).styleId,
        isNull,
      );
    });
  });

  group('el idioma', () {
    testWidgets('elegir inglés cambia los términos', (tester) async {
      final item = await source(
        'cap',
        reference: const ReferenceData(
          type: ReferenceType.chapter,
          containerTitle: 'Historia',
          publisher: 'Editorial',
          pages: '12-20',
          contributors: [
            Contributor(
              name: PersonName(family: 'Ruiz', given: 'Ana'),
            ),
          ],
        ),
        publishedAt: DateTime(2020),
      );
      await pumpSection(tester, item);

      expect(shown(tester), contains(' En Historia (pp. 12–20)'));

      await tester.tap(find.text(es.citationLanguageEn));
      await tester.pumpAndSettle();

      expect(shown(tester), contains(' In Historia (pp. 12–20)'));
    });
  });

  group('las formas', () {
    testWidgets('APA solo tiene la entrada y la cita en el texto', (
      tester,
    ) async {
      final item = await source('libro', reference: book);
      await pumpSection(tester, item);

      expect(find.byKey(const Key('citation-form-reference')), findsOneWidget);
      expect(find.byKey(const Key('citation-form-inText')), findsOneWidget);
      expect(find.byKey(const Key('citation-form-note')), findsNothing);
      expect(find.byKey(const Key('citation-form-shortNote')), findsNothing);
    });

    testWidgets('Chicago notas y bibliografía tiene las dos notas', (
      tester,
    ) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);
      await chooseStyle(tester, es.citationStyleChicagoNotes);

      expect(find.byKey(const Key('citation-form-note')), findsOneWidget);
      expect(find.byKey(const Key('citation-form-shortNote')), findsOneWidget);
      expect(find.byKey(const Key('citation-form-inText')), findsNothing);

      await tester.tap(find.byKey(const Key('citation-form-note')));
      await tester.pumpAndSettle();
      expect(
        shown(tester),
        'Gabriel García Márquez, Cien años de soledad (Sudamericana, 1967).',
      );

      await tester.tap(find.byKey(const Key('citation-form-shortNote')));
      await tester.pumpAndSettle();
      expect(shown(tester), 'García Márquez, Cien años de soledad.');
    });

    testWidgets('cambiar a un estilo sin esa forma vuelve a la entrada', (
      tester,
    ) async {
      final item = await source('libro', reference: book);
      await pumpSection(tester, item);
      await chooseStyle(tester, es.citationStyleChicagoNotes);
      await tester.tap(find.byKey(const Key('citation-form-note')));
      await tester.pumpAndSettle();

      await chooseStyle(tester, 'APA 7');

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const Key('citation-form-reference')),
            )
            .selected,
        isTrue,
      );
      expect(shown(tester), startsWith('García Márquez, G. '));
    });

    testWidgets('la entrada de la lista no pide página', (tester) async {
      final item = await source('libro', reference: book);
      await pumpSection(tester, item);

      expect(find.byKey(const Key('citation-locator')), findsNothing);

      await tester.tap(find.byKey(const Key('citation-form-inText')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('citation-locator')), findsOneWidget);
    });
  });

  group('la página o el minuto', () {
    testWidgets('se agregan a la cita en el texto', (tester) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);
      await tester.tap(find.byKey(const Key('citation-form-inText')));
      await tester.pumpAndSettle();
      expect(shown(tester), '(García Márquez, 1967)');

      await tester.enterText(
        find.byKey(const Key('citation-locator')),
        '12-14',
      );
      await tester.pump();
      expect(shown(tester), '(García Márquez, 1967, pp. 12–14)');

      await tester.enterText(find.byKey(const Key('citation-locator')), '12');
      await tester.pump();
      expect(shown(tester), '(García Márquez, 1967, p. 12)');

      await tester.enterText(
        find.byKey(const Key('citation-locator')),
        '0:14:35',
      );
      await tester.pump();
      expect(shown(tester), '(García Márquez, 1967, 0:14:35)');
    });

    testWidgets('y a la nota, donde la página va al final', (tester) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      await pumpSection(tester, item);
      await chooseStyle(tester, es.citationStyleChicagoNotes);
      await tester.tap(find.byKey(const Key('citation-form-note')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('citation-locator')),
        '315-16',
      );
      await tester.pump();

      expect(
        shown(tester),
        'Gabriel García Márquez, Cien años de soledad (Sudamericana, 1967), '
        '315–16.',
      );
    });
  });

  group('copiar', () {
    testWidgets('como texto plano, sin cursivas', (tester) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      final copied = await pumpSection(tester, item);

      await tester.tap(find.byKey(const Key('citation-copy')));
      await tester.pumpAndSettle();

      expect(copied, [
        'García Márquez, G. (1967). Cien años de soledad. Sudamericana.',
      ]);
      expect(find.text(es.citationCopied), findsOneWidget);
    });

    testWidgets('con formato, en Markdown, con las cursivas', (tester) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      final copied = await pumpSection(tester, item);

      await tester.tap(find.byKey(const Key('citation-copy-markdown')));
      await tester.pumpAndSettle();

      expect(copied, [
        'García Márquez, G. (1967). *Cien años de soledad*. Sudamericana.',
      ]);
    });

    testWidgets('lo que se copia es lo que se ve: estilo, forma y página', (
      tester,
    ) async {
      final item = await source(
        'libro',
        reference: book,
        publishedAt: DateTime(1967),
      );
      final copied = await pumpSection(tester, item);
      await chooseStyle(tester, es.citationStyleChicagoAuthorDate);
      await tester.tap(find.byKey(const Key('citation-form-inText')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('citation-locator')), '12');
      await tester.pump();

      await tester.tap(find.byKey(const Key('citation-copy')));
      await tester.pumpAndSettle();

      expect(copied, ['(García Márquez 1967, 12)']);
    });
  });

  testWidgets('cuando la referencia cambia, la cita se actualiza sola', (
    tester,
  ) async {
    final item = await source('libro', publishedAt: DateTime(1967));
    await pumpSection(tester, item);
    expect(shown(tester), contains('[falta: autor]'));

    await tester.runAsync(
      () => KnowledgeEntryWriter(harness.database).setReference('libro', book),
    );
    await tester.pumpAndSettle();

    expect(shown(tester), startsWith('García Márquez, G. (1967).'));
  });
}
