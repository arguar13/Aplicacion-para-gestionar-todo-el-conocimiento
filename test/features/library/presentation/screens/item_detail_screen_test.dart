import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/tema_category.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/graph/presentation/widgets/compact_graph_node.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/historical_date_form.dart';
import 'package:sinapsis/features/timeline/data/repositories/timeline_repository_impl.dart';
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
    // Con la cita bibliográfica sumada al detalle, el contenido ya no
    // entra en el tamaño de ventana por defecto de las pruebas de widget
    // (800x600): un texto que quedaba visible sin scrollear pasaría a
    // estar fuera del viewport, y `ListView` ni siquiera lo construiría
    // —es perezoso también con una lista de hijos fija—. Agrandar la
    // ventana de la prueba es más simple y menos frágil que agregar un
    // `scrollUntilVisible` en cada prueba que mira algo del pie de la
    // pantalla.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

    testWidgets('un elemento con texto ofrece leerlo para destilar', (
      tester,
    ) async {
      final id = await captureAndGetId(
        'Un título\n\nY el cuerpo con la idea completa.',
      );

      await pumpDetail(tester, id);

      expect(find.text(es.readingOpenAction), findsOneWidget);
    });

    testWidgets('sin texto todavía, no ofrece leer', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.readingOpenAction), findsNothing);
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

    testWidgets('el contenido completo se puede copiar con un solo botón', (
      tester,
    ) async {
      final id = await captureAndGetId(
        'Un título\n\nY el cuerpo con la idea completa.',
      );
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
      await tester.tap(find.text(es.detailCopyContent));
      await tester.pumpAndSettle();

      expect(copied, 'Un título\n\nY el cuerpo con la idea completa.');
      expect(find.text(es.detailContentCopied), findsOneWidget);
    });
  });

  group('madurez', () {
    testWidgets('una nota muestra su madurez', (tester) async {
      final id = await captureAndGetId('un texto cualquiera');

      await pumpDetail(tester, id);

      expect(find.text(es.noteMaturitySeed), findsOneWidget);
    });

    testWidgets('una fuente no muestra ninguna madurez', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.text(es.noteMaturitySeed), findsNothing);
      expect(find.text(es.noteMaturityDeveloping), findsNothing);
      expect(find.text(es.noteMaturityMature), findsNothing);
    });
  });

  group('nota mapa', () {
    testWidgets('una nota muestra el chip de nota mapa, sin marcar', (
      tester,
    ) async {
      final id = await captureAndGetId('un texto cualquiera');

      await pumpDetail(tester, id);

      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isFalse);
    });

    testWidgets('una fuente no muestra el chip de nota mapa', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);

      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('tocarlo la marca como mapa', (tester) async {
      final id = await captureAndGetId('un texto cualquiera');
      await pumpDetail(tester, id);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isTrue);
    });

    testWidgets('tocarlo de nuevo la vuelve a nota viva', (tester) async {
      final id = await captureAndGetId('un texto cualquiera');
      await harness.container
          .read(inboxRepositoryProvider)
          .setNoteKind(itemId: id, kind: NoteKind.map);
      await pumpDetail(tester, id);

      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();

      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isFalse);
    });
  });

  group('vínculos de nota mapa', () {
    testWidgets(
      'una nota mapa con vínculos de dos tipos muestra dos encabezados de '
      'grupo',
      (tester) async {
        // Ni "relacionado" ni "cita": la primera coincide, en español, con
        // el título fijo de toda la sección (`detailRelationsTitle`), y la
        // segunda con el título de `CitationSection` (`citationTitle`),
        // así que cualquiera de las dos confundiría al buscar el texto del
        // encabezado de grupo con el de otra parte fija de la pantalla.
        final other1 = await captureAndGetId('un elemento que continúa');
        final other2 = await captureAndGetId('un elemento que contradice');
        final id = await captureAndGetId('la nota mapa');
        await harness.container
            .read(inboxRepositoryProvider)
            .setNoteKind(itemId: id, kind: NoteKind.map);
        await harness.container
            .read(organizeRepositoryProvider)
            .createRelation(
              fromItemId: id,
              toItemId: other1,
              kind: RelationKind.continues,
            );
        await harness.container
            .read(organizeRepositoryProvider)
            .createRelation(
              fromItemId: id,
              toItemId: other2,
              kind: RelationKind.contradicts,
            );

        await pumpDetail(tester, id);

        expect(find.text(es.relationKindLabelContinues), findsOneWidget);
        expect(find.text(es.relationKindLabelContradicts), findsOneWidget);
        expect(find.byType(ListTile), findsNWidgets(2));
      },
    );

    testWidgets(
      'una nota sin marcar sigue mostrando la lista plana, sin encabezados',
      (tester) async {
        final other = await captureAndGetId('otro elemento');
        final id = await captureAndGetId('una nota sin marcar');
        await harness.container
            .read(organizeRepositoryProvider)
            .createRelation(
              fromItemId: id,
              toItemId: other,
              kind: RelationKind.continues,
            );

        await pumpDetail(tester, id);

        expect(find.text(es.relationKindLabelContinues), findsNothing);
        expect(find.byType(ListTile), findsOneWidget);
      },
    );
  });

  group('grafo local (panel embebido)', () {
    testWidgets('sin vínculos, el panel muestra su estado vacío', (
      tester,
    ) async {
      final id = await captureAndGetId('un elemento sin vínculos');

      await pumpDetail(tester, id);

      expect(find.text(es.graphEmpty), findsOneWidget);
      expect(find.byType(CompactGraphNode), findsNothing);
    });

    testWidgets('con un vínculo, el panel muestra dos nodos', (tester) async {
      final other = await captureAndGetId('el otro elemento');
      final id = await captureAndGetId('el elemento con vínculo');
      await harness.container
          .read(organizeRepositoryProvider)
          .createRelation(
            fromItemId: id,
            toItemId: other,
            kind: RelationKind.relatedTo,
          );

      await pumpDetail(tester, id);

      expect(find.text(es.graphEmpty), findsNothing);
      expect(find.byType(CompactGraphNode), findsNWidgets(2));
    });

    testWidgets('tocar el botón de ver grafo completo navega al grafo local', (
      tester,
    ) async {
      final other = await captureAndGetId('el otro elemento');
      final id = await captureAndGetId('el elemento con vínculo');
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

      final openFullButton = find.byTooltip(es.localGraphPanelOpenFull);
      await tester.scrollUntilVisible(
        openFullButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(openFullButton);
      await tester.pumpAndSettle();

      expect(
        find.text(es.localGraphTitle('el elemento con vínculo')),
        findsOneWidget,
      );
    });

    testWidgets(
      'un vecino marcado como nota mapa, tocado desde el panel, entra al '
      'grafo local centrado en él en vez de a su detalle',
      (tester) async {
        final other = await captureAndGetId('el vecino mapa');
        final id = await captureAndGetId('el elemento con vínculo');
        await harness.container
            .read(organizeRepositoryProvider)
            .createRelation(
              fromItemId: id,
              toItemId: other,
              kind: RelationKind.relatedTo,
            );
        await harness.container
            .read(inboxRepositoryProvider)
            .setNoteKind(itemId: other, kind: NoteKind.map);

        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();
        harness.goTo('${RoutePaths.library}/$id');
        await tester.pumpAndSettle();

        final mapNeighbor = find.text('el vecino mapa');
        await tester.scrollUntilVisible(
          mapNeighbor,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(mapNeighbor);
        await tester.pumpAndSettle();

        expect(find.text(es.localGraphTitle('el vecino mapa')), findsOneWidget);
        expect(find.text(es.detailRelationsTitle), findsNothing);
      },
    );
  });

  group('procedencia', () {
    testWidgets('muestra de dónde salió y cuándo se guardó', (tester) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);
      // La sección de procedencia queda más abajo que el "cache extent" por
      // defecto de un `ListView` en test —lo que ya obliga a scrollear para
      // las pruebas de más abajo—, así que hay que llegar hasta ella antes
      // de poder afirmar que está. `.first`: la propia `SelectableText` de
      // la cita bibliográfica —y la del contenido— envuelven su texto en
      // un `Scrollable` propio para su desplazamiento interno, así que ya
      // no alcanza con "el" `Scrollable` a secas; el primero en el árbol
      // sigue siendo el de la lista de toda la pantalla.
      await tester.scrollUntilVisible(
        find.text(es.detailProvenance),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text(es.detailProvenance), findsOneWidget);
      expect(find.text(es.sourceKindWebPage), findsOneWidget);
      // La cita bibliográfica, más arriba en la pantalla, también menciona
      // la URL —es parte legítima de una cita—, así que el enlace de la
      // procedencia en sí ya no es el único lugar que la muestra.
      expect(find.textContaining('https://ejemplo.org'), findsWidgets);
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
      final copyLinkButton = find.text(es.detailCopyLink);
      // `ensureVisible` no sirve acá: el botón queda más allá del "cache
      // extent" por defecto del `ListView`, así que ni siquiera está
      // construido todavía —`ensureVisible` necesita que el elemento ya
      // exista para poder scrollear hasta él—. `scrollUntilVisible` en
      // cambio scrollea de a poco hasta que aparece.
      await tester.scrollUntilVisible(
        copyLinkButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(copyLinkButton);
      await tester.pumpAndSettle();

      expect(copied, 'https://ejemplo.org/un-articulo');
      expect(find.text(es.detailLinkCopied), findsOneWidget);
    });

    testWidgets('un elemento sin fusiones no muestra nada nuevo', (
      tester,
    ) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');

      await pumpDetail(tester, id);
      await tester.scrollUntilVisible(
        find.text(es.detailProvenance),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text(es.detailMergedProvenanceTitle), findsNothing);
    });

    testWidgets('un elemento con una fusión muestra la procedencia absorbida', (
      tester,
    ) async {
      final id = await captureAndGetId('https://ejemplo.org/un-articulo');
      final discardedCapture = DateTime(2026, 5);
      await harness.database
          .into(harness.database.mergedProvenances)
          .insert(
            MergedProvenancesCompanion.insert(
              id: 'merged-1',
              itemId: id,
              sourceKind: SourceKind.socialPost,
              capturedAt: discardedCapture,
              mergedAt: DateTime(2026, 9, 11, 10),
            ),
          );

      await pumpDetail(tester, id);
      await tester.scrollUntilVisible(
        find.text(es.detailMergedProvenanceTitle),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text(es.detailMergedProvenanceTitle), findsOneWidget);
      expect(
        find.text(
          es.detailMergedProvenanceRow(
            es.sourceKindSocialPost,
            DateFormat.yMMMd('es').format(discardedCapture),
          ),
        ),
        findsOneWidget,
      );
      // Sigue mostrando la procedencia propia además de la absorbida —
      // fusionar no la reemplaza, la suma.
      expect(find.text(es.sourceKindWebPage), findsOneWidget);
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
    ///
    /// El contenido no tiene ninguna firma de formato reconocible a
    /// propósito —ni PDF, ni DOCX, ni ningún otro—: este grupo prueba la
    /// procedencia (nombre, borrar el original), no la vista previa
    /// embebida de un formato puntual, que ya tiene sus propias pruebas en
    /// `open_document_viewer_test.dart`. Un archivo que
    /// sí sniffeara como PDF de verdad disparía el visor de `pdfrx`, que
    /// necesita PDFium nativo puesto a mano (`tool/fetch_pdfium.sh`) para
    /// no colgarse bajo `flutter test` — algo que este grupo no tiene por
    /// qué pedir.
    Future<String> captureFile({String name = 'La tesis de Ana.pdf'}) async {
      final result = await harness.container.read(captureItemUseCaseProvider)(
        CaptureRequest.file(
          file: CapturedFile(
            name: name,
            bytes: Uint8List.fromList(utf8.encode('contenido de prueba')),
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
        //
        // Las etiquetas son los valores de la categoría Tema.
        final temaId = await temaDefinitionId(harness.database);
        final allTags = await (harness.database.select(
          harness.database.propertyValues,
        )..where((v) => v.definitionId.equals(temaId))).get();
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

  group('propiedades', () {
    testWidgets('un elemento recién guardado no tiene ninguna', (tester) async {
      final id = await captureAndGetId('una nota cualquiera');

      await pumpDetail(tester, id);

      expect(find.text(es.detailNoPropertiesYet), findsOneWidget);
    });

    testWidgets('agregar una categoría nueva con su valor la deja guardada', (
      tester,
    ) async {
      final id = await captureAndGetId('una nota sobre historia romana');

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddProperty));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyCategoryHint),
        'Región',
      );
      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyValueHint),
        'Roma',
      );
      await tester.tap(find.text(es.detailAddProperty).last);
      await tester.pumpAndSettle();

      expect(find.text('Región'), findsOneWidget);
      expect(find.text('Roma'), findsOneWidget);
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      expect(item.properties, hasLength(1));
      expect(item.properties.single.definitionName, 'Región');
      expect(item.properties.single.value, 'Roma');
    });

    testWidgets('cancelar el diálogo no agrega nada', (tester) async {
      final id = await captureAndGetId('una nota');

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddProperty));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyCategoryHint),
        'Región',
      );
      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyValueHint),
        'Roma',
      );
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text('Roma'), findsNothing);
    });

    testWidgets('con el valor en blanco, confirmar no cierra el diálogo', (
      tester,
    ) async {
      final id = await captureAndGetId('una nota');

      await pumpDetail(tester, id);
      await tester.tap(find.text(es.detailAddProperty));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyCategoryHint),
        'Región',
      );
      await tester.tap(find.text(es.detailAddProperty).last);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets(
      'escribir el nombre de una categoría que ya existe en otro elemento '
      'la reutiliza, en vez de crear otra',
      (tester) async {
        final existing = await captureAndGetId('el primer elemento');
        final existingItem =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .findById(existing))
                .getRight()
                .toNullable()!;
        final definition =
            (await harness.container
                    .read(organizeRepositoryProvider)
                    .getOrCreatePropertyDefinition('Región'))
                .getRight()
                .toNullable()!;
        await harness.container
            .read(organizeRepositoryProvider)
            .assignProperty(
              itemId: existingItem.id,
              definitionId: definition.id,
              value: 'Roma',
            );

        final id = await captureAndGetId('un segundo elemento');
        await pumpDetail(tester, id);
        await tester.tap(find.text(es.detailAddProperty));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyCategoryHint),
          'región',
        );
        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyValueHint),
          'Egipto',
        );
        await tester.tap(find.text(es.detailAddProperty).last);
        await tester.pumpAndSettle();

        // Una sola categoría "Región" en toda la base —además de "Tema" y
        // "Fecha del hecho", sembradas desde el arranque—, con los dos
        // valores que le pusieron los dos elementos.
        final allDefinitions = await harness.database
            .select(harness.database.propertyDefinitions)
            .get();
        expect(allDefinitions.where((d) => d.name == 'Región'), hasLength(1));
      },
    );

    testWidgets(
      'un elemento puede tener dos valores bajo la misma categoría a la vez',
      (tester) async {
        final id = await captureAndGetId('un video sobre dos regiones');
        await pumpDetail(tester, id);

        await tester.tap(find.text(es.detailAddProperty));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyCategoryHint),
          'Región',
        );
        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyValueHint),
          'Roma',
        );
        await tester.tap(find.text(es.detailAddProperty).last);
        await tester.pumpAndSettle();

        await tester.tap(find.text(es.detailAddProperty));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyCategoryHint),
          'Región',
        );
        await tester.enterText(
          find.widgetWithText(TextField, es.detailPropertyValueHint),
          'Egipto',
        );
        await tester.tap(find.text(es.detailAddProperty).last);
        await tester.pumpAndSettle();

        expect(find.text('Roma'), findsOneWidget);
        expect(find.text('Egipto'), findsOneWidget);
        final item =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .findById(id))
                .getRight()
                .toNullable()!;
        expect(item.properties.map((p) => p.value), {'Roma', 'Egipto'});
      },
    );

    testWidgets('quitar un valor lo saca de la lista, sin afectar a otro '
        'elemento que lo tenga puesto', (tester) async {
      final definition =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreatePropertyDefinition('Región'))
              .getRight()
              .toNullable()!;

      final idA = await captureAndGetId('un elemento');
      await harness.container
          .read(organizeRepositoryProvider)
          .assignProperty(
            itemId: idA,
            definitionId: definition.id,
            value: 'Roma',
          );
      final idB = await captureAndGetId('otro elemento');
      await harness.container
          .read(organizeRepositoryProvider)
          .assignProperty(
            itemId: idB,
            definitionId: definition.id,
            value: 'Roma',
          );

      await pumpDetail(tester, idA);
      expect(find.text('Roma'), findsOneWidget);

      await tester.tap(find.byTooltip(es.detailRemoveProperty('Roma')));
      await tester.pumpAndSettle();

      expect(find.text('Roma'), findsNothing);
      final reloadedA =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .findById(idA))
              .getRight()
              .toNullable()!;
      final reloadedB =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .findById(idB))
              .getRight()
              .toNullable()!;
      expect(reloadedA.properties, isEmpty);
      expect(reloadedB.properties, hasLength(1));
    });
  });

  group('fecha del hecho', () {
    Future<void> openDialogFor(WidgetTester tester, String category) async {
      await tester.tap(find.text(es.detailAddProperty));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, es.detailPropertyCategoryHint),
        category,
      );
      await tester.pumpAndSettle();
    }

    Future<void> enterYear(WidgetTester tester, String year) async {
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerYear),
        year,
      );
      await tester.pumpAndSettle();
    }

    Future<void> choosePrecision(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
    }

    Future<void> chooseMonth(WidgetTester tester, String name) async {
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, es.detailAddProperty));
      await tester.pumpAndSettle();
    }

    Future<PropertyValueRow> storedValue(String label) =>
        (harness.database.select(
          harness.database.propertyValues,
        )..where((v) => v.value.equals(label))).getSingle();

    testWidgets('escribir la categoría de fecha cambia el texto libre por el '
        'formulario de fecha', (tester) async {
      final id = await captureAndGetId('un hecho');
      await pumpDetail(tester, id);

      await openDialogFor(tester, kFechaDelHechoCategoryName);

      expect(find.byType(HistoricalDateForm), findsOneWidget);
      expect(
        find.widgetWithText(TextField, es.detailPropertyValueHint),
        findsNothing,
      );
    });

    testWidgets('el nombre de la categoría se reconoce sin distinguir '
        'mayúsculas', (tester) async {
      final id = await captureAndGetId('un hecho');
      await pumpDetail(tester, id);

      await openDialogFor(tester, 'fecha DEL hecho');

      expect(find.byType(HistoricalDateForm), findsOneWidget);
    });

    testWidgets('una categoría que no es de fecha sigue pidiendo un texto', (
      tester,
    ) async {
      final id = await captureAndGetId('un hecho');
      await pumpDetail(tester, id);

      await openDialogFor(tester, 'Región');

      expect(find.byType(HistoricalDateForm), findsNothing);
      expect(
        find.widgetWithText(TextField, es.detailPropertyValueHint),
        findsOneWidget,
      );
    });

    testWidgets('con la fecha a medio escribir no se puede confirmar', (
      tester,
    ) async {
      final id = await captureAndGetId('un hecho');
      await pumpDetail(tester, id);
      await openDialogFor(tester, kFechaDelHechoCategoryName);

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, es.detailAddProperty),
      );

      expect(button.onPressed, isNull);
    });

    testWidgets('al escribir un año válido el botón se habilita', (
      tester,
    ) async {
      final id = await captureAndGetId('un hecho');
      await pumpDetail(tester, id);
      await openDialogFor(tester, kFechaDelHechoCategoryName);

      await enterYear(tester, '476');

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, es.detailAddProperty),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      'un año queda guardado como fecha, con su precisión y su rango',
      (tester) async {
        final id = await captureAndGetId('la caída de Roma');
        await pumpDetail(tester, id);
        await openDialogFor(tester, kFechaDelHechoCategoryName);

        await enterYear(tester, '476');
        await confirm(tester);

        // El chip muestra la fecha, y el elemento la tiene puesta.
        expect(find.text('476'), findsOneWidget);
        final item =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .findById(id))
                .getRight()
                .toNullable()!;
        expect(
          item.properties.single.definitionName,
          kFechaDelHechoCategoryName,
        );
        expect(item.properties.single.value, '476');

        // Y no es solo texto: lleva la fecha completa.
        final row = await storedValue('476');
        expect(row.datePrecision, DatePrecision.year);
        expect(row.dateFromYear, 476);
        expect(row.dateToYear, 476);
        expect(row.dateIsCirca, isFalse);
      },
    );

    testWidgets('a.C., con día y aproximada, queda guardado completo', (
      tester,
    ) async {
      final id = await captureAndGetId('los idus de marzo');
      await pumpDetail(tester, id);
      await openDialogFor(tester, kFechaDelHechoCategoryName);

      await enterYear(tester, '44');
      await tester.tap(find.text(es.datePickerEraBce));
      await tester.pumpAndSettle();
      await choosePrecision(tester, es.datePickerPrecisionDay);
      await chooseMonth(tester, 'Marzo');
      await tester.enterText(
        find.widgetWithText(TextField, es.datePickerDay),
        '15',
      );
      await tester.tap(find.text(es.datePickerCirca));
      await tester.pumpAndSettle();
      await confirm(tester);

      final label = const HistoricalDate(
        year: 44,
        precision: DatePrecision.day,
        month: 3,
        day: 15,
        isBce: true,
        isCirca: true,
      ).label;
      expect(find.text(label), findsOneWidget);
      final row = await storedValue(label);
      // 44 a.C. es el año astronómico -43.
      expect(row.dateFromYear, -43);
      expect(row.dateFromMonth, 3);
      expect(row.dateFromDay, 15);
      expect(row.dateToYear, -43);
      expect(row.datePrecision, DatePrecision.day);
      expect(row.dateIsCirca, isTrue);
    });

    testWidgets('una década guarda el tramo que cubre', (tester) async {
      final id = await captureAndGetId('los años veinte');
      await pumpDetail(tester, id);
      await openDialogFor(tester, kFechaDelHechoCategoryName);

      await enterYear(tester, '1920');
      await choosePrecision(tester, es.datePickerPrecisionDecade);
      await confirm(tester);

      final row = await storedValue('1920 – 1929');
      expect(row.datePrecision, DatePrecision.decade);
      expect(row.dateFromYear, 1920);
      expect(row.dateToYear, 1929);
    });

    testWidgets('dos elementos con la misma fecha comparten el valor', (
      tester,
    ) async {
      final first = await captureAndGetId('primer hecho');
      await pumpDetail(tester, first);
      await openDialogFor(tester, kFechaDelHechoCategoryName);
      await enterYear(tester, '476');
      await confirm(tester);

      final second = await captureAndGetId('segundo hecho');
      await pumpDetail(tester, second);
      await openDialogFor(tester, kFechaDelHechoCategoryName);
      await enterYear(tester, '476');
      await confirm(tester);

      final rows = await (harness.database.select(
        harness.database.propertyValues,
      )..where((v) => v.value.equals('476'))).get();
      expect(rows, hasLength(1));
    });

    testWidgets('cancelar no guarda nada', (tester) async {
      final id = await captureAndGetId('un hecho');
      await pumpDetail(tester, id);
      await openDialogFor(tester, kFechaDelHechoCategoryName);
      await enterYear(tester, '476');

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(find.text('476'), findsNothing);
      final item =
          (await harness.container.read(libraryRepositoryProvider).findById(id))
              .getRight()
              .toNullable()!;
      expect(item.properties, isEmpty);
    });

    testWidgets('lo que se pone acá aparece en la línea de tiempo', (
      tester,
    ) async {
      final id = await captureAndGetId('la caída de Roma');
      await pumpDetail(tester, id);
      await openDialogFor(tester, kFechaDelHechoCategoryName);
      await enterYear(tester, '476');
      await confirm(tester);

      final timeline = TimelineRepositoryImpl(
        database: harness.database,
        library: harness.container.read(libraryRepositoryProvider),
        telemetry: harness.container.read(telemetryServiceProvider),
      );
      // Un stream de la base necesita el reloj real: dentro de `testWidgets`
      // el reloj es falso y su primera emisión no llegaría nunca.
      final events = (await tester.runAsync(
        () => timeline.watchEvents(const LibraryQuery()).first,
      ))!;

      expect(events, hasLength(1));
      expect(events.single.itemId, id);
      expect(
        events.single.date,
        const HistoricalDate(year: 476, precision: DatePrecision.year),
      );
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
      await tester.tap(find.text(es.pickRelationConfirm));
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
      await tester.tap(find.text(es.pickRelationConfirm));
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

      final relationTile = find.byType(ListTile);
      await tester.scrollUntilVisible(
        relationTile,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(relationTile);
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
      // `.first`: la sección de cita bibliográfica también tiene su propio
      // `SelectableText` más abajo en la pantalla, y este helper siempre
      // quiere el del contenido, que es el que aparece primero.
      final topLeft = tester.getTopLeft(find.byType(SelectableText).first);
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

  group('exportar', () {
    testWidgets('elegir un formato lo exporta y se lo pasa al selector', (
      tester,
    ) async {
      final id = await captureAndGetId('Un artículo interesante');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatMarkdown));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, endsWith('.md'));
      expect(harness.fileSaver.savedBytes, isNotNull);
    });

    testWidgets('cada formato del menú se exporta con su propia extensión', (
      tester,
    ) async {
      final id = await captureAndGetId('Un artículo interesante');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatPdf));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, endsWith('.pdf'));
    });

    testWidgets('si el selector de guardado falla, lo avisa', (tester) async {
      final id = await captureAndGetId('Un artículo interesante');
      harness.fileSaver.error = StateError('el diálogo se cayó');

      await pumpDetail(tester, id);
      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatMarkdown));
      await tester.pumpAndSettle();

      expect(find.text(es.globalErrorExportFailed), findsOneWidget);
    });
  });
}
