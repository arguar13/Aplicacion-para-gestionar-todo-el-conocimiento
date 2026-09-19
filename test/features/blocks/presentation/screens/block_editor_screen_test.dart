import 'package:drift/drift.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/dedup_fingerprint.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/links/presentation/widgets/broken_link_offer.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const BlockEditorScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('crear una nota nueva la guarda con su título y su bloque', (
    tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(
      find.widgetWithText(TextField, es.blocksTitleHint),
      'Mi primera nota',
    );
    await tester.enterText(
      find.widgetWithText(TextField, es.blocksParagraphHint),
      'contenido del primer bloque',
    );
    await tester.tap(find.byTooltip(es.detailSave));
    await tester.pumpAndSettle();

    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;

    expect(items, hasLength(1));
    expect(items.single.title, 'Mi primera nota');

    final rendition = items.single.renditions.whereType<TextRendition>().single;
    expect(rendition.kind, RenditionKind.blocks);
    expect(decodeContentBlocks(rendition.content), [
      const ContentBlock.paragraph(text: 'contenido del primer bloque'),
    ]);
  });

  testWidgets('guardar sin título ni contenido avisa en vez de guardar algo '
      'vacío', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip(es.detailSave));
    await tester.pumpAndSettle();

    expect(find.text(es.blocksEmptyError), findsOneWidget);

    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;
    expect(items, isEmpty);
  });

  testWidgets('el botón de agregar suma un bloque nuevo', (tester) async {
    await pumpEditor(tester);

    final blocksBefore = find.widgetWithText(TextField, es.blocksParagraphHint);
    expect(blocksBefore, findsOneWidget);

    await tester.tap(find.byTooltip(es.blocksAddBlock).first);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, es.blocksParagraphHint),
      findsNWidgets(2),
    );
  });

  testWidgets('elegir un tipo distinto cambia el ícono y el placeholder del '
      'bloque', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.byTooltip(es.blocksChangeType));
    await tester.pumpAndSettle();
    await tester.tap(find.text(es.blocksTypeHeading));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, es.blocksHeadingHint),
      findsOneWidget,
    );
  });

  testWidgets('editar una nota existente reemplaza sus bloques, no crea otra', (
    tester,
  ) async {
    // Se arma la nota original por el mismo camino que usaría la app: el
    // propio editor, guardando una vez.
    await pumpEditor(tester);
    await tester.enterText(
      find.widgetWithText(TextField, es.blocksParagraphHint),
      'texto original',
    );
    await tester.tap(find.byTooltip(es.detailSave));
    await tester.pumpAndSettle();

    final saved =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .single;

    // `key` distinto a propósito: sin él, Flutter reutiliza el `State` del
    // widget anterior en vez de montar uno nuevo —mismo tipo, misma
    // posición en el árbol— y los campos `late final` inicializados una
    // sola vez seguirían mostrando la nota vieja. En la app real esto no
    // pasa porque cada pantalla llega por su propia ruta, con su propio
    // `Element` desde cero.
    await tester.pumpWidget(
      harness.wrap(BlockEditorScreen(key: UniqueKey(), existingItem: saved)),
    );
    await tester.pumpAndSettle();

    expect(find.text('texto original'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, es.blocksParagraphHint),
      'texto editado',
    );
    await tester.tap(find.byTooltip(es.detailSave));
    await tester.pumpAndSettle();

    final items =
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;

    expect(items, hasLength(1));
    final rendition = items.single.renditions.whereType<TextRendition>().single;
    expect(decodeContentBlocks(rendition.content), [
      const ContentBlock.paragraph(text: 'texto editado'),
    ]);
  });

  group('deduplicación', () {
    const existingText = 'Un texto que ya está guardado desde antes';

    Future<List<KnowledgeItem>> savedItems() async =>
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;

    /// Guarda una nota con [text] y le pone a mano el `dedupHash`/`simhash`
    /// que le correspondería —igual que calculará de verdad el generador
    /// de sugerencias (F7, C8/C9), que todavía no existe en esta ronda—,
    /// para que haya algo con qué comparar antes de guardar.
    Future<String> seedExistingNote(String text) async {
      await harness.capture(text);
      final id = (await savedItems()).single.id;

      final normalized = normalizeForDedup(text);
      await (harness.database.update(
        harness.database.knowledgeNotes,
      )..where((n) => n.itemId.equals(id))).write(
        KnowledgeNotesCompanion(
          dedupHash: Value(contentHashOf(normalized)),
          simhash: Value(simhashOf(normalized)),
        ),
      );

      return id;
    }

    testWidgets('una nota nueva sin ninguna coincidencia guarda normal, '
        'sin ningún diálogo', (tester) async {
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextField, es.blocksParagraphHint),
        'Un texto que nadie más tiene',
      );
      await tester.tap(find.byTooltip(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.text(es.duplicateWarningTitleExact), findsNothing);
      expect(await savedItems(), hasLength(1));
    });

    testWidgets(
      'con una coincidencia exacta, elegir "Fusionar" deja un solo ítem '
      'con las dos renditions de texto',
      (tester) async {
        final existingId = await seedExistingNote(existingText);
        await pumpEditor(tester);

        await tester.enterText(
          find.widgetWithText(TextField, es.blocksParagraphHint),
          existingText,
        );
        await tester.tap(find.byTooltip(es.detailSave));
        await tester.pumpAndSettle();

        expect(find.text(es.duplicateWarningTitleExact), findsOneWidget);
        await tester.tap(find.text(es.duplicateWarningMerge));
        await tester.pumpAndSettle();

        final items = await savedItems();
        expect(items, hasLength(1));
        expect(items.single.id, existingId);
        expect(
          items.single.renditions.whereType<TextRendition>(),
          hasLength(2),
        );
      },
    );

    testWidgets(
      'con una coincidencia, elegir "Guardar aparte" dos ítems separados, '
      'ninguno tocado',
      (tester) async {
        final existingId = await seedExistingNote(existingText);
        await pumpEditor(tester);

        await tester.enterText(
          find.widgetWithText(TextField, es.blocksParagraphHint),
          existingText,
        );
        await tester.tap(find.byTooltip(es.detailSave));
        await tester.pumpAndSettle();

        await tester.tap(find.text(es.duplicateWarningKeepSeparate));
        await tester.pumpAndSettle();

        final items = await savedItems();
        expect(items, hasLength(2));
        expect(items.map((i) => i.id), contains(existingId));
      },
    );

    testWidgets('editar una nota existente no muestra el diálogo, aunque '
        'termine igual a otra', (tester) async {
      final existingId = await seedExistingNote(existingText);
      await harness.capture('una nota aparte para editar');
      final toEdit = (await savedItems()).firstWhere((i) => i.id != existingId);

      await tester.pumpWidget(
        harness.wrap(BlockEditorScreen(existingItem: toEdit)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, es.blocksParagraphHint),
        existingText,
      );
      await tester.tap(find.byTooltip(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.text(es.duplicateWarningTitleExact), findsNothing);
      expect(await savedItems(), hasLength(2));
    });
  });

  group('enlaces [[ ]]', () {
    // Solo la parte de interfaz: que escribir o insertar un enlace deje el
    // texto correcto en el bloque. Que guardar la nota registre el enlace y
    // cree la relación de verdad lo hace `save` del repositorio, dentro de su
    // transacción, y se prueba abajo y en `library_repository_impl_test`
    // contra el repositorio directo, sin ningún widget de por medio: los
    // `await` reales encadenados contra la base se cuelgan bajo el reloj
    // simulado de `testWidgets`. Qué títulos extrae un texto se prueba en
    // `inline_link_parser_test`.
    testWidgets('escribir [[Título]] a mano se ve tal cual en el bloque', (
      tester,
    ) async {
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextField, es.blocksParagraphHint),
        'Esto fue impulsado por el [[Colonialismo Británico]].',
      );
      await tester.pump();

      expect(
        find.text('Esto fue impulsado por el [[Colonialismo Británico]].'),
        findsOneWidget,
      );
    });

    testWidgets('el botón de enlazar inserta [[Título]] en el bloque', (
      tester,
    ) async {
      await harness.capture('Colonialismo Británico');
      await pumpEditor(tester);

      await tester.enterText(
        find.widgetWithText(TextField, es.blocksParagraphHint),
        'Esto fue impulsado por el ',
      );
      await tester.tap(find.byTooltip(es.blocksInsertLink));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colonialismo Británico'));
      await tester.pumpAndSettle();

      expect(
        find.text('Esto fue impulsado por el [[Colonialismo Británico]]'),
        findsOneWidget,
      );
    });
  });

  group('enlace sin nota', () {
    /// El campo del primer bloque: el título es el primer `TextField` y este,
    /// el segundo. No se busca por su placeholder porque desaparece en cuanto
    /// se escribe algo.
    Finder blockField() => find.byType(TextField).at(1);

    /// Escribe [text] en el primer bloque y deja pasar la espera de la
    /// revisión, que es un debounce: una consulta por letra sería trabajo
    /// tirado.
    Future<void> typeAndWait(WidgetTester tester, String text) async {
      await tester.enterText(blockField(), text);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }

    Finder offer() => find.byType(BrokenLinkOffer);

    Future<List<KnowledgeItem>> savedItems() async =>
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!;

    testWidgets('escribir un [[Título]] que no existe ofrece crear la nota, '
        'sin salir del editor', (tester) async {
      await pumpEditor(tester);

      await typeAndWait(tester, 'Fue a [[Cartago]] en barco.');

      expect(find.text(es.blocksBrokenLinkTitle), findsOneWidget);
      expect(
        find.descendant(of: offer(), matching: find.text('[[Cartago]]')),
        findsOneWidget,
      );
      expect(find.byType(BlockEditorScreen), findsOneWidget);
    });

    testWidgets('un enlace a algo que existe no ofrece nada', (tester) async {
      await harness.capture('Colonialismo Británico');
      await pumpEditor(tester);

      await typeAndWait(tester, 'Ver [[colonialismo británico]].');

      expect(offer(), findsNothing);
    });

    testWidgets('sin ningún [[ ]] no aparece el aviso', (tester) async {
      await pumpEditor(tester);

      await typeAndWait(tester, 'Un texto sin enlaces.');

      expect(offer(), findsNothing);
    });

    testWidgets('un enlace igual al propio título de la nota no se ofrece', (
      tester,
    ) async {
      await pumpEditor(tester);
      await tester.enterText(find.byType(TextField).first, 'Cartago');

      await typeAndWait(tester, 'Hablo de [[cartago]].');

      expect(offer(), findsNothing);
    });

    testWidgets('crear la nota la deja en la biblioteca como viva y apaga el '
        'aviso, sin salir del editor', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, 'Fue a [[Cartago]] en barco.');

      await tester.tap(find.text(es.blocksBrokenLinkCreate));
      await tester.pumpAndSettle();

      final created = (await savedItems()).singleWhere(
        (i) => i.title == 'Cartago',
      );
      final mirror = await (harness.database.select(
        harness.database.knowledgeNotes,
      )..where((n) => n.itemId.equals(created.id))).getSingle();
      expect(mirror.noteKind, NoteKind.living);
      expect(offer(), findsNothing);
      // Sigue en el editor y con lo escrito intacto.
      expect(find.byType(BlockEditorScreen), findsOneWidget);
      expect(find.text('Fue a [[Cartago]] en barco.'), findsOneWidget);
    });

    testWidgets('crear con el subtipo elegido lo escribe', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, '[[Índice de Roma]]');

      await tester.tap(find.widgetWithText(ChoiceChip, es.noteKindMap));
      await tester.pump();
      await tester.tap(find.text(es.blocksBrokenLinkCreate));
      await tester.pumpAndSettle();

      final created = (await savedItems()).singleWhere(
        (i) => i.title == 'Índice de Roma',
      );
      final mirror = await (harness.database.select(
        harness.database.knowledgeNotes,
      )..where((n) => n.itemId.equals(created.id))).getSingle();
      expect(mirror.noteKind, NoteKind.map);
    });

    testWidgets('el campo de texto no pierde el foco al crear la nota, ni con '
        'el mouse', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, 'Fue a [[Cartago]].');
      final editable = tester.widget<EditableText>(
        find.descendant(of: blockField(), matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasPrimaryFocus, isTrue);

      await tester.tap(
        find.text(es.blocksBrokenLinkCreate),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect((await savedItems()).map((i) => i.title), contains('Cartago'));
      expect(editable.focusNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('"Ahora no" oculta el aviso y no vuelve mientras se sigue '
        'escribiendo', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, 'Fue a [[Cartago]].');

      await tester.tap(find.text(es.blocksBrokenLinkDismiss));
      await tester.pumpAndSettle();
      expect(offer(), findsNothing);

      await typeAndWait(tester, 'Fue a [[Cartago]] y volvió.');

      expect(offer(), findsNothing);
      expect(await savedItems(), isEmpty);
    });

    testWidgets('con varios enlaces sin nota ofrece el primero, avisa cuántos '
        'más hay y pasa al siguiente al crearlo', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, 'Fue a [[Cartago]] y a [[Atenas]].');

      expect(
        find.descendant(of: offer(), matching: find.text('[[Cartago]]')),
        findsOneWidget,
      );
      expect(find.text(es.blocksBrokenLinkMore(1)), findsOneWidget);

      await tester.tap(find.text(es.blocksBrokenLinkCreate));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: offer(), matching: find.text('[[Atenas]]')),
        findsOneWidget,
      );
      expect(find.textContaining('sin nota'), findsNothing);
    });

    testWidgets('quitar el enlace del texto apaga el aviso', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, 'Fue a [[Cartago]].');
      expect(offer(), findsOneWidget);

      await typeAndWait(tester, 'Ya no enlazo nada.');

      expect(offer(), findsNothing);
    });

    testWidgets('el aviso no impide guardar: la nota se guarda con su enlace '
        'aún roto', (tester) async {
      await pumpEditor(tester);
      await typeAndWait(tester, 'Fue a [[Cartago]].');

      await tester.tap(find.byTooltip(es.detailSave));
      await tester.pumpAndSettle();

      final links = await harness.database
          .select(harness.database.inlineLinks)
          .get();
      expect(links.map((l) => (l.normalizedTitle, l.toItemId)), [
        ('cartago', null),
      ]);
    });
  });

  group('guardar una nota con [[ ]], sin widgets', () {
    // `save` registra los enlaces y crea la relación de los que tienen
    // destino en la misma transacción que guarda la nota: el editor ya no
    // lista la biblioteca ni crea relaciones por su cuenta. Probado contra el
    // repositorio directo, que es lo que un widget test no puede ejercitar
    // de forma confiable bajo el reloj simulado (ver el comentario de más
    // arriba).
    test('vincula la nota con el elemento que enlaza, sin más pasos', () async {
      await harness.capture('Colonialismo Británico');
      final container = harness.container;

      final saved = await container
          .read(libraryRepositoryProvider)
          .save(
            KnowledgeItem(
              id: 'item-nuevo',
              title: 'Revolución Industrial',
              source: Source(
                id: 'src-nuevo',
                kind: SourceKind.manualNote,
                capturedAt: DateTime(2026),
              ),
              processingState: ProcessingState.ready,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              renditions: [
                Rendition.text(
                  id: 'rend-nuevo',
                  itemId: 'item-nuevo',
                  kind: RenditionKind.blocks,
                  content: encodeContentBlocks([
                    const ContentBlock.paragraph(
                      text:
                          'Esto fue impulsado por el '
                          '[[Colonialismo Británico]].',
                    ),
                  ]),
                  isPrimary: true,
                  createdAt: DateTime(2026),
                ),
              ],
            ),
          );
      expect(saved.isRight(), isTrue);

      final items =
          (await container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final target = items.firstWhere(
        (i) => i.title == 'Colonialismo Británico',
      );

      final relations = await container
          .read(organizeRepositoryProvider)
          .watchRelationsForItem('item-nuevo')
          .first;
      expect(relations, hasLength(1));
      expect(relations.single.otherItemId, target.id);
      expect(relations.single.kind, RelationKind.relatedTo);

      final links = await harness.database
          .select(harness.database.inlineLinks)
          .get();
      expect(links.map((l) => (l.fromItemId, l.normalizedTitle, l.toItemId)), [
        ('item-nuevo', 'colonialismo británico', target.id),
      ]);
    });
  });
}
