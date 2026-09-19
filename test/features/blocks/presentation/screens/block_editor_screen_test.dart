import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
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
    // texto correcto en el bloque. La creación del vínculo de verdad al
    // guardar —el resto de `_save`— encadena un `await` real de más contra
    // la base (guardar, después listar, después crear la relación) que
    // bajo el reloj simulado de `testWidgets` se cuelga sin motivo
    // aparente —confirmado aparte, contra el propio repositorio, sin
    // ningún widget de por medio: ver el grupo "crear el vínculo real, sin
    // widgets" más abajo—. Esa lógica se prueba ahí, y la de qué títulos
    // extrae un texto, en el grupo de `extractLinkedTitles`; lo que hace
    // falta cubrir acá es solo que el editor escribe el `[[ ]]` correcto.
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

  group('extractLinkedTitles', () {
    ContentBlock p(String text) => ContentBlock.paragraph(text: text);

    test('un solo enlace', () {
      expect(extractLinkedTitles([p('Ver [[Colonialismo Británico]] acá')]), {
        'colonialismo británico',
      });
    });

    test('varios enlaces, en varios bloques', () {
      expect(
        extractLinkedTitles([
          p('Ver [[Uno]] y [[Dos]]'),
          p('También [[Tres]]'),
        ]),
        {'uno', 'dos', 'tres'},
      );
    });

    test('sin distinguir mayúsculas: dos formas del mismo título quedan '
        'juntas', () {
      expect(extractLinkedTitles([p('[[Roma]] y [[roma]] de nuevo')]), {
        'roma',
      });
    });

    test('sin ningún enlace, devuelve vacío', () {
      expect(extractLinkedTitles([p('Texto sin nada especial')]), isEmpty);
    });

    test('un enlace vacío [[ ]] no cuenta', () {
      expect(extractLinkedTitles([p('Ver [[  ]] acá')]), isEmpty);
    });
  });

  group('crear el vínculo real, sin widgets', () {
    // La secuencia exacta que hace `_save` tras guardar —listar la
    // biblioteca y después crear la relación— probada contra el
    // repositorio directo: es la parte que un widget test no puede
    // ejercitar de forma confiable bajo el reloj simulado (ver el
    // comentario de más arriba), pero que sí se puede probar así, igual
    // que cualquier otro repositorio del proyecto.
    test('guardar dos elementos con contenido real, listarlos y vincularlos '
        'funciona de punta a punta', () async {
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

      final linkedTitles = extractLinkedTitles(
        decodeContentBlocks(
          items
              .firstWhere((i) => i.id == 'item-nuevo')
              .renditions
              .whereType<TextRendition>()
              .single
              .content,
        ),
      );
      expect(linkedTitles, {'colonialismo británico'});

      final relation = await container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: 'item-nuevo',
            toItemId: target.id,
            kind: RelationKind.relatedTo,
          );
      expect(relation.isRight(), isTrue);

      final relations = await container
          .read(organizeRepositoryProvider)
          .watchRelationsForItem('item-nuevo')
          .first;
      expect(relations, hasLength(1));
      expect(relations.single.otherItemId, target.id);
    });
  });
}
