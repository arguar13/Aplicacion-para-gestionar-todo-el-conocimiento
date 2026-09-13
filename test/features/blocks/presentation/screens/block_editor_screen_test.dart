import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/features/blocks/presentation/screens/block_editor_screen.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
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
}
