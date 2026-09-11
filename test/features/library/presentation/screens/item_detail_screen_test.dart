import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/storage/file_opener.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  /// Guarda algo y devuelve su identificador.
  ///
  /// No usa "el primero de la lista": la lista se ordena por fecha de
  /// captura, y el reloj de las pruebas es fijo, así que dos capturas en la
  /// misma prueba comparten el mismo instante y el orden entre ellas no está
  /// garantizado. Se identifica en cambio comparando qué identificador
  /// apareció que antes no estaba — funciona sin importar cuántos elementos
  /// haya ni en qué orden los devuelva la consulta.
  Future<String> captureAndGetId(String input, {String? note}) async {
    Future<Set<String>> currentIds() async =>
        (await harness.container
                .read(libraryRepositoryProvider)
                .list(const LibraryQuery()))
            .getRight()
            .toNullable()!
            .map((i) => i.id)
            .toSet();

    final before = await currentIds();
    await harness.capture(input, note: note);
    final after = await currentIds();

    return after.difference(before).single;
  }

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    await tester.pumpWidget(harness.wrap(ItemDetailScreen(itemId: id)));
    await tester.pumpAndSettle();
  }

  /// Deja un elemento como si traerle el contenido hubiera fallado.
  ///
  /// Pasa por el repositorio en vez de escribir la fila a mano: así el estado
  /// del que parte la prueba es uno que la app produce de verdad.
  Future<void> markFailed(String id) async {
    final repository = harness.container.read(libraryRepositoryProvider);
    final item = (await repository.findById(id)).getRight().toNullable()!;

    await repository.save(
      item.copyWith(processingState: ProcessingState.failed),
    );
  }

  group('contenido', () {
    testWidgets('muestra el texto guardado', (tester) async {
      final id = await captureAndGetId(
        'Un título\n\nY el cuerpo con la idea completa.',
      );

      await pumpDetail(tester, id);

      expect(find.textContaining('la idea completa'), findsOneWidget);
    });

    testWidgets('la nota del usuario se ve aparte del contenido', (
      tester,
    ) async {
      final id = await captureAndGetId(
        'Un artículo',
        note: 'me lo recomendó Ana',
      );

      await pumpDetail(tester, id);

      expect(find.text('me lo recomendó Ana'), findsOneWidget);
    });

    testWidgets('un elemento sin contenido todavía aclara que el enlace SÍ '
        'está guardado', (tester) async {
      // Una pantalla vacía se lee como "no se guardó nada", y el usuario
      // vuelve a capturarlo o deja de confiar en la app.
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.detailNoContentYet), findsOneWidget);
    });
  });

  group('procedencia', () {
    testWidgets('muestra de dónde salió y cuándo se guardó', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.detailProvenance), findsOneWidget);
      expect(find.text(es.sourceKindWebPage), findsOneWidget);
      expect(find.textContaining('https://ejemplo.org'), findsOneWidget);
    });

    testWidgets('una nota escrita a mano no inventa un enlace de origen', (
      tester,
    ) async {
      // El origen es la persona; mostrar un campo vacío sería peor que no
      // mostrarlo.
      final id = await captureAndGetId('una idea propia');

      await pumpDetail(tester, id);

      expect(find.text(es.detailCopyLink), findsNothing);
      expect(find.text(es.sourceKindNote), findsOneWidget);
    });

    testWidgets('el enlace se puede copiar al portapapeles', (tester) async {
      // Se copia en vez de abrirse: abrirlo exigiría un complemento nativo
      // que hoy no se puede probar acá, y un botón que a veces no hace nada
      // es peor que uno que siempre funciona.
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
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

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailCopyLink));
      await tester.pumpAndSettle();

      expect(copied, 'https://ejemplo.org/un-articulo');
      expect(find.text(es.detailLinkCopied), findsOneWidget);
    });
  });

  group('eliminar', () {
    testWidgets('pide confirmación antes de borrar algo irreversible', (
      tester,
    ) async {
      final id = await captureAndGetId('algo que se va a borrar');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text(es.detailDeleteConfirm), findsOneWidget);
    });

    testWidgets('cancelar no borra nada', (tester) async {
      final id = await captureAndGetId('algo que NO se va a borrar');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      expect(items, hasLength(1));
    });

    testWidgets('confirmar borra y vuelve a la biblioteca', (tester) async {
      final id = await captureAndGetId('algo que se va a borrar');

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.pushTo(RoutePaths.itemDetail(id));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.detailDelete).last);
      await tester.pumpAndSettle();

      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(find.text(es.emptyLibraryTitle), findsOneWidget);
    });
  });

  group('archivos originales', () {
    /// Guarda un elemento que vino de un archivo, como lo dejaría el
    /// adaptador de archivos.
    Future<String> captureFile({String name = 'La tesis de Ana.pdf'}) async {
      final result = await harness.container.read(captureItemUseCaseProvider)(
        CaptureRequest.file(
          file: CapturedFile(
            name: name,
            bytes: Uint8List.fromList(utf8.encode('%PDF-1.7 contenido')),
          ),
        ),
      );

      return result.getRight().toNullable()!.id;
    }

    testWidgets('el detalle dice que el archivo original está a salvo', (
      tester,
    ) async {
      // Para un PDF no hay ningún enlace al que volver: el archivo ES la
      // fuente. Sin esta fila, nada en la pantalla lo diría y el usuario
      // tendría que confiar en que sí.
      final id = await captureFile();

      await pumpDetail(tester, id);

      expect(find.textContaining('La tesis de Ana.pdf'), findsOneWidget);
    });

    testWidgets('el nombre se muestra limpio, sin el identificador', (
      tester,
    ) async {
      // En el disco cada archivo vive en una carpeta con el identificador de
      // su fuente. Eso es necesario ahí y es ruido en la pantalla.
      final id = await captureFile(name: 'apunte.pdf');

      await pumpDetail(tester, id);

      expect(find.textContaining('originales/'), findsNothing);
      expect(find.textContaining('apunte.pdf'), findsOneWidget);
    });

    testWidgets('el aviso de contenido pendiente habla del archivo, no de '
        'un enlace', (tester) async {
      // Decirle "el enlace sigue guardado" a alguien que nunca guardó un
      // enlace suena a mensaje equivocado, y hace dudar de si su documento
      // sigue ahí.
      final id = await captureFile();

      await pumpDetail(tester, id);

      expect(find.text(es.detailNoContentYetFile), findsOneWidget);
      expect(find.text(es.detailNoContentYet), findsNothing);
    });

    testWidgets('y el de extracción fallida, también', (tester) async {
      final id = await captureFile();
      await markFailed(id);

      await pumpDetail(tester, id);

      expect(find.text(es.detailExtractionFailedFile), findsOneWidget);
      expect(find.text(es.detailExtractionFailed), findsNothing);
    });

    testWidgets('un enlace sigue hablando del enlace', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.detailNoContentYet), findsOneWidget);
    });

    testWidgets('un elemento sin archivo no ofrece abrir nada', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.detailOpenFile), findsNothing);
    });

    testWidgets('el botón de abrir le pasa al sistema la ruta absoluta, no la '
        'relativa que guarda la base', (tester) async {
      final id = await captureFile();
      // La ruta relativa la decide el adaptador de archivos, con un
      // identificador propio de la fuente — no hay por qué coincidir con el
      // del elemento. Se pide la de verdad en vez de reconstruirla a mano.
      final repository = harness.container.read(libraryRepositoryProvider);
      final item = (await repository.findById(id)).getRight().toNullable()!;
      final relativePath = item.source.originalFilePath!;

      await pumpDetail(tester, id);
      await tester.tap(find.widgetWithText(TextButton, es.detailOpenFile));
      await tester.pumpAndSettle();

      expect(harness.fileOpener.requested, [
        await harness.files.resolve(relativePath),
      ]);
    });

    testWidgets('si se pudo abrir, no hace falta avisar nada más', (
      tester,
    ) async {
      final id = await captureFile();
      harness.fileOpener.result = FileOpenResult.done;

      await pumpDetail(tester, id);
      await tester.tap(find.widgetWithText(TextButton, es.detailOpenFile));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('si el archivo ya no está, lo dice', (tester) async {
      final id = await captureFile();
      harness.fileOpener.result = FileOpenResult.fileNotFound;

      await pumpDetail(tester, id);
      await tester.tap(find.widgetWithText(TextButton, es.detailOpenFile));
      await tester.pumpAndSettle();

      expect(find.text(es.detailOpenFileNotFound), findsOneWidget);
    });

    testWidgets('si no hay ninguna aplicación para ese tipo, lo dice', (
      tester,
    ) async {
      final id = await captureFile();
      harness.fileOpener.result = FileOpenResult.noAppAvailable;

      await pumpDetail(tester, id);
      await tester.tap(find.widgetWithText(TextButton, es.detailOpenFile));
      await tester.pumpAndSettle();

      expect(find.text(es.detailOpenFileNoApp), findsOneWidget);
    });

    testWidgets('cualquier otro fallo tiene un aviso genérico', (tester) async {
      final id = await captureFile();
      harness.fileOpener.result = FileOpenResult.failed;

      await pumpDetail(tester, id);
      await tester.tap(find.widgetWithText(TextButton, es.detailOpenFile));
      await tester.pumpAndSettle();

      expect(find.text(es.detailOpenFileFailed), findsOneWidget);
    });
  });

  group('reintentar', () {
    testWidgets('algo que falló ofrece volver a intentarlo', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/se-cayó');
      await markFailed(id);

      await pumpDetail(tester, id);

      expect(find.text(es.detailExtractionFailed), findsOneWidget);
      expect(find.text(es.detailRetry), findsOneWidget);
    });

    testWidgets('el botón lo devuelve a la cola', (tester) async {
      // Reintentar es a pedido y no automático en cada arranque. Ese trato
      // solo se sostiene si el botón funciona: sin él, lo que falló una vez
      // quedaría muerto para siempre.
      final id = await captureAndGetId('https://ejemplo.org/se-cayó');
      await markFailed(id);

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailRetry));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, [id]);
    });

    testWidgets('algo que todavía está en camino NO ofrece reintento', (
      tester,
    ) async {
      // Un botón de reintentar sobre algo que está andando invita a
      // apretarlo, y lo único que haría es encolar de nuevo lo mismo.
      final id = await captureAndGetId('https://ejemplo.org/en-camino');

      await pumpDetail(tester, id);

      expect(find.text(es.detailRetry), findsNothing);
    });
  });

  group('etiquetas', () {
    testWidgets('un elemento recién guardado no tiene ninguna', (tester) async {
      final id = await captureAndGetId('una nota cualquiera');

      await pumpDetail(tester, id);

      expect(find.text(es.detailAddTag), findsOneWidget);
    });

    testWidgets('agregar una nueva la deja guardada', (tester) async {
      final id = await captureAndGetId('una nota sobre epistemología');

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddTag));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Filosofía');
      // El botón "Agregar etiqueta" del diálogo: hay dos widgets con ese
      // texto en pantalla —el chip de atrás y el botón del diálogo—, y el
      // del diálogo es el último en el árbol.
      await tester.tap(find.text(es.detailAddTag).last);
      await tester.pumpAndSettle();

      expect(find.text('Filosofía'), findsOneWidget);
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      expect(item.tags.map((t) => t.name), ['Filosofía']);
    });

    testWidgets('cancelar el diálogo no agrega nada', (tester) async {
      final id = await captureAndGetId('una nota');

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddTag));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Algo');
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text('Algo'), findsNothing);
    });

    testWidgets('un nombre en blanco no hace nada', (tester) async {
      final id = await captureAndGetId('una nota');

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddTag));
      await tester.pumpAndSettle();

      // Sin escribir nada, confirmar no debe cerrar con una etiqueta vacía.
      await tester.tap(find.text(es.detailAddTag).last);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets(
      'escribir el nombre de una ya existente en otro elemento reutiliza esa',
      (tester) async {
        // Quien escribe "filosofía" en minúscula sobre una etiqueta que ya
        // existe como "Filosofía" tiene que terminar en la misma, no en dos
        // que compiten por agrupar lo mismo.
        final existing = await captureAndGetId('el primer artículo');
        final existingItem =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .findById(existing))
                .getRight()
                .toNullable()!;
        final firstTag =
            (await harness.container
                    .read(organizeRepositoryProvider)
                    .getOrCreateTag('Filosofía'))
                .getRight()
                .toNullable()!;
        await harness.container
            .read(libraryRepositoryProvider)
            .save(existingItem.copyWith(tags: [firstTag]));

        final id = await captureAndGetId('un segundo artículo');
        await pumpDetail(tester, id);
        await tester.tap(find.text(es.detailAddTag));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'filosofía');
        await tester.tap(find.text(es.detailAddTag).last);
        await tester.pumpAndSettle();

        // Se lee directo de la base y no con `watchAllTags`: abrir una
        // segunda suscripción justo cuando la del diálogo se está
        // descartando (autoDispose) compite sobre el mismo stream de drift.
        // En la app real eso no pasa —Riverpod comparte una sola
        // suscripción entre quien la mire— así que alcanza con una lectura
        // puntual para esta comprobación.
        final allTags = await harness.database
            .select(harness.database.tags)
            .get();
        expect(allTags, hasLength(1));
      },
    );

    testWidgets('tocar una sugerencia la agrega sin escribir nada más', (
      tester,
    ) async {
      final withTag = await captureAndGetId('un artículo cualquiera');
      final item =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .findById(withTag))
              .getRight()
              .toNullable()!;
      final tag =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreateTag('Historia'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .save(item.copyWith(tags: [tag]));

      final id = await captureAndGetId('otro elemento sin etiquetas');
      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddTag));
      await tester.pumpAndSettle();

      // "Historia" aparece como sugerencia porque ya existe en el
      // vocabulario, aunque este elemento nunca la tuvo. Se apunta al chip
      // y no al texto crudo: el área que responde al toque es la del
      // `ActionChip`, más grande que el glifo de su etiqueta.
      await tester.tap(find.widgetWithText(ActionChip, 'Historia'));
      await tester.pumpAndSettle();

      final reloaded =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      expect(reloaded.tags.map((t) => t.name), ['Historia']);
    });

    testWidgets('una que ya tiene el elemento no se sugiere de nuevo', (
      tester,
    ) async {
      final id = await captureAndGetId('un elemento etiquetado');
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      final tag =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreateTag('Arte'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .save(item.copyWith(tags: [tag]));

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddTag));
      await tester.pumpAndSettle();

      // "Arte" solo debe verse una vez: como chip ya puesto, no también como
      // sugerencia para agregarla de nuevo.
      expect(find.text('Arte'), findsOneWidget);
    });

    testWidgets('quitar una la saca de la lista', (tester) async {
      final id = await captureAndGetId('un elemento con una etiqueta');
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      final tag =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreateTag('Efímera'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .save(item.copyWith(tags: [tag]));

      await pumpDetail(tester, id);
      expect(find.text('Efímera'), findsOneWidget);

      await tester.tap(find.byTooltip(es.detailRemoveTag('Efímera')));
      await tester.pumpAndSettle();

      expect(find.text('Efímera'), findsNothing);
      final reloaded =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      expect(reloaded.tags, isEmpty);
    });
  });

  group('relaciones', () {
    testWidgets('sin nada vinculado, no muestra ninguna fila', (tester) async {
      final id = await captureAndGetId('un elemento cualquiera');

      await pumpDetail(tester, id);

      expect(find.text(es.detailRelationsTitle), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets(
      'con un solo elemento en la biblioteca, el selector avisa que no hay '
      'con qué vincular',
      (tester) async {
        final id = await captureAndGetId('el único elemento');

        await pumpDetail(tester, id);
        await tester.tap(find.byTooltip(es.detailAddRelation));
        await tester.pumpAndSettle();

        expect(find.text(es.pickItemNoOthers), findsOneWidget);
      },
    );

    testWidgets('vincular con otro elemento lo deja guardado y visible', (
      tester,
    ) async {
      await captureAndGetId('un artículo sobre el tema');
      final id = await captureAndGetId('la respuesta al artículo');

      await pumpDetail(tester, id);
      await tester.tap(find.byTooltip(es.detailAddRelation));
      await tester.pumpAndSettle();

      await tester.tap(find.text('un artículo sobre el tema'));
      await tester.pumpAndSettle();

      // El tipo por defecto es "relacionado", así que alcanza con
      // confirmar.
      await tester.tap(find.text(es.detailAddRelation));
      await tester.pumpAndSettle();

      expect(
        find.text(es.relationKindRelatedTo('un artículo sobre el tema')),
        findsOneWidget,
      );
    });

    testWidgets('se puede elegir otro tipo de vínculo, con una nota', (
      tester,
    ) async {
      await captureAndGetId('la fuente original');
      final id = await captureAndGetId('lo que la cita');

      await pumpDetail(tester, id);
      await tester.tap(find.byTooltip(es.detailAddRelation));
      await tester.pumpAndSettle();
      await tester.tap(find.text('la fuente original'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cita'));
      await tester.enterText(
        find.byType(TextField),
        'para el trabajo del jueves',
      );
      await tester.tap(find.text(es.detailAddRelation));
      await tester.pumpAndSettle();

      expect(
        find.text(es.relationKindCitesOutgoing('la fuente original')),
        findsOneWidget,
      );
      expect(find.text('para el trabajo del jueves'), findsOneWidget);
    });

    testWidgets('cancelar el selector de elemento no crea nada', (
      tester,
    ) async {
      await captureAndGetId('otro elemento cualquiera');
      final id = await captureAndGetId('el elemento que se mira');

      await pumpDetail(tester, id);
      await tester.tap(find.byTooltip(es.detailAddRelation));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('cancelar el selector de tipo tampoco crea nada', (
      tester,
    ) async {
      await captureAndGetId('otro elemento cualquiera');
      final id = await captureAndGetId('el elemento que se mira');

      await pumpDetail(tester, id);
      await tester.tap(find.byTooltip(es.detailAddRelation));
      await tester.pumpAndSettle();
      await tester.tap(find.text('otro elemento cualquiera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      // Se lee directo de la base, no con `watchRelationsForItem`: la
      // sección de vínculos de la pantalla ya tiene su propia suscripción
      // activa mientras el detalle está montado, y abrir una segunda acá
      // compite sobre el mismo stream de drift.
      final relations = await harness.database
          .select(harness.database.relations)
          .get();
      expect(relations, isEmpty);
    });

    testWidgets('quitar un vínculo lo saca de la lista', (tester) async {
      final other = await captureAndGetId('el otro elemento');
      final id = await captureAndGetId('el elemento con el vínculo');
      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: id,
            toItemId: other,
            kind: RelationKind.relatedTo,
          );

      await pumpDetail(tester, id);
      expect(find.byType(ListTile), findsOneWidget);

      await tester.tap(find.byTooltip(es.detailRemoveRelation));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets(
      'se ve desde el otro elemento también, con el sentido correcto',
      (tester) async {
        final origin = await captureAndGetId('el capítulo uno');
        final continuation = await captureAndGetId('el capítulo dos');
        await harness.container
            .read(organizeRepositoryProvider)
            .createRelation(
              fromItemId: origin,
              toItemId: continuation,
              kind: RelationKind.continues,
            );

        // Parado en el capítulo dos (el destino), la frase tiene que decir
        // que ES la continuación del uno, no que continúa en él.
        await pumpDetail(tester, continuation);

        expect(
          find.text(es.relationKindContinuesIncoming('el capítulo uno')),
          findsOneWidget,
        );
      },
    );

    testWidgets('tocar una fila de vínculo navega al otro elemento', (
      tester,
    ) async {
      final other = await captureAndGetId('el destino del vínculo');
      final id = await captureAndGetId('el origen del vínculo');
      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: id,
            toItemId: other,
            kind: RelationKind.relatedTo,
          );

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();
      harness.goTo('${RoutePaths.library}/$id');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();

      // No alcanza con buscar el texto: el origen sigue en la pila de
      // navegación (para poder volver), y su fila de vínculo también dice
      // "el destino del vínculo". Lo que distingue a la pantalla de encima
      // es su AppBar.
      expect(
        find.widgetWithText(AppBar, 'el destino del vínculo'),
        findsOneWidget,
      );
    });
  });

  group('resaltados', () {
    /// Selecciona la primera palabra del contenido con un toque largo, tal
    /// como lo haría alguien leyendo en la pantalla. No se manipula la
    /// selección por código: es la única forma de probar esto que también
    /// ejercita el callback `onSelectionChanged` de verdad.
    Future<void> selectFirstWord(WidgetTester tester) async {
      final topLeft = tester.getTopLeft(find.byType(SelectableText));
      await tester.longPressAt(topLeft + const Offset(8, 8));
      await tester.pumpAndSettle();
    }

    testWidgets('seleccionar una palabra ofrece resaltarla', (tester) async {
      final id = await captureAndGetId(
        'Un texto con varias palabras para '
        'seleccionar.',
      );

      await pumpDetail(tester, id);
      await selectFirstWord(tester);

      expect(find.text(es.detailHighlightSelection), findsOneWidget);
    });

    testWidgets('sin nada seleccionado, no se ofrece', (tester) async {
      final id = await captureAndGetId('Un texto cualquiera.');

      await pumpDetail(tester, id);

      expect(find.text(es.detailHighlightSelection), findsNothing);
    });

    testWidgets('resaltar deja el fragmento marcado y en la lista', (
      tester,
    ) async {
      final id = await captureAndGetId('Palabra clave del artículo entero.');

      await pumpDetail(tester, id);
      await selectFirstWord(tester);
      await tester.tap(find.text(es.detailHighlightSelection));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'me interesa esto');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.text(es.detailHighlightsTitle), findsOneWidget);
      expect(find.text('me interesa esto'), findsOneWidget);
      // El botón desaparece: la selección se limpia al confirmar, para no
      // dejar picando un botón que apunta a un resaltado que ya se hizo.
      expect(find.text(es.detailHighlightSelection), findsNothing);
    });

    testWidgets('resaltar sin escribir nada también funciona', (tester) async {
      // Resaltar sin explicar por qué es perfectamente legítimo: no toda
      // selección necesita una justificación.
      final id = await captureAndGetId('Palabra clave del artículo entero.');

      await pumpDetail(tester, id);
      await selectFirstWord(tester);
      await tester.tap(find.text(es.detailHighlightSelection));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.text(es.detailHighlightsTitle), findsOneWidget);
    });

    testWidgets('cancelar el diálogo de nota no crea el resaltado', (
      tester,
    ) async {
      final id = await captureAndGetId('Palabra clave del artículo entero.');

      await pumpDetail(tester, id);
      await selectFirstWord(tester);
      await tester.tap(find.text(es.detailHighlightSelection));
      await tester.pumpAndSettle();

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text(es.detailHighlightsTitle), findsNothing);
    });

    testWidgets('editar la nota de un resaltado ya hecho', (tester) async {
      final id = await captureAndGetId('Palabra clave del artículo entero.');
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      final renditionId = item.renditions.single.renditionId;
      await harness.container
          .read(organizeRepositoryProvider)
          .createHighlight(
            renditionId: renditionId,
            startOffset: 0,
            endOffset: 7,
            excerpt: 'Palabra',
            note: 'nota original',
          );

      await pumpDetail(tester, id);
      // Lo que abre el editor es la fila de la lista, no el propio texto
      // resaltado.
      await tester.tap(find.text('nota original'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nota corregida');
      await tester.tap(find.text(es.detailSave));
      await tester.pumpAndSettle();

      expect(find.text('nota corregida'), findsOneWidget);
      expect(find.text('nota original'), findsNothing);
    });

    testWidgets('borrar un resaltado lo saca de la lista', (tester) async {
      final id = await captureAndGetId('Palabra clave del artículo entero.');
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      final renditionId = item.renditions.single.renditionId;
      await harness.container
          .read(organizeRepositoryProvider)
          .createHighlight(
            renditionId: renditionId,
            startOffset: 0,
            endOffset: 7,
            excerpt: 'Palabra',
          );

      await pumpDetail(tester, id);
      expect(find.text(es.detailHighlightsTitle), findsOneWidget);

      await tester.tap(find.byTooltip(es.detailRemoveHighlight));
      await tester.pumpAndSettle();

      expect(find.text(es.detailHighlightsTitle), findsNothing);
    });

    testWidgets(
      'un resaltado cuyo rango ya no entra en el texto actual no rompe la '
      'pantalla',
      (tester) async {
        // Pasa cuando la rendition se regenera con un texto más corto: los
        // índices de un resaltado viejo pueden quedar apuntando más allá de
        // donde ahora termina el texto.
        final id = await captureAndGetId('Corto.');
        final item =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .findById(id))
                .getRight()
                .toNullable()!;
        final renditionId = item.renditions.single.renditionId;
        await harness.container
            .read(organizeRepositoryProvider)
            .createHighlight(
              renditionId: renditionId,
              startOffset: 0,
              endOffset: 500,
              excerpt: 'un fragmento que ya no existe tal cual',
            );

        // No revienta al construir la pantalla: `pumpDetail` ya hace
        // `pumpAndSettle`, así que si el recorte de los índices fallara acá
        // se vería como una excepción durante el build.
        await pumpDetail(tester, id);

        // Y el resaltado se sigue viendo en la lista con el texto que se
        // guardó en su momento: el excerpt es independiente del contenido
        // actual.
        expect(
          find.text('un fragmento que ya no existe tal cual'),
          findsOneWidget,
        );
      },
    );
  });
}
