import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/library_view_mode.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/rendition.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/space.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/capture/domain/entities/capture_request.dart';
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/capture/presentation/providers/capture_providers.dart';
import 'package:sinapsis/features/capture/presentation/screens/capture_screen.dart';
import 'package:sinapsis/features/health/presentation/widgets/health_panel.dart';
import 'package:sinapsis/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:sinapsis/features/library/domain/entities/library_query.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/library/presentation/providers/library_query_notifier.dart';
import 'package:sinapsis/features/library/presentation/screens/item_detail_screen.dart';
import 'package:sinapsis/features/library/presentation/screens/library_screen.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_calendar_view.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_item_card.dart';
import 'package:sinapsis/features/library/presentation/widgets/library_table_view.dart';
import 'package:sinapsis/features/library/presentation/widgets/space_filter_section.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/reading/presentation/screens/reading_screen.dart';
import 'package:sinapsis/features/settings/presentation/screens/settings_screen.dart';
import 'package:sinapsis/features/transform/presentation/providers/processing_queue_state.dart';
import 'package:sinapsis/features/transform/presentation/screens/transcription_model_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(harness.wrap(const LibraryScreen()));
    await tester.pumpAndSettle();
  }

  /// Un PNG real de un solo píxel, no bytes inventados: la portada de la
  /// fila pasa los bytes guardados por `Image.memory`, que revienta si no
  /// son una imagen de verdad.
  Uint8List fakePngBytes() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

  /// Abre el panel de filtros de tipo y etiquetas: viven detrás de ese botón
  /// y no sueltos en la barra —ver `_FiltersSheet` en `library_screen.dart`—,
  /// así que cualquier prueba que necesite tocar uno de esos chips pasa por
  /// acá primero.
  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byTooltip(es.libraryFiltersTooltip));
    await tester.pumpAndSettle();
  }

  /// El chip del tema [name] adentro del panel de filtros —y no el que
  /// muestra el tema elegido debajo de la búsqueda, que puede llamarse
  /// igual—.
  Finder spaceChip(String name) => find.descendant(
    of: find.byKey(SpaceFilterSection.chipsKey),
    matching: find.text(name),
  );

  /// Cierra ese mismo panel.
  ///
  /// Hace falta antes de mirar lo que queda debajo en algunos casos: cuando
  /// el filtro recién elegido deja la lista vacía, el panel —todavía
  /// abierto— y el estado vacío de atrás ofrecen los dos un botón "Limpiar
  /// filtros" con el mismo texto, y sin cerrar el panel ese texto deja de
  /// ser único en la pantalla.
  Future<void> closeFilters(WidgetTester tester) async {
    // No se toca la posición del velo de atrás: con `isScrollControlled` el
    // panel puede ocupar buena parte del alto de la pantalla, y ahí el
    // centro geométrico del velo cae justo debajo del panel en vez de en la
    // franja que sí sigue destapada. Cerrarlo por el `Navigator` en vez de
    // por un toque evita depender de esa geometría.
    Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();
  }

  group('estados vacíos', () {
    testWidgets('una biblioteca recién estrenada explica para qué sirve la '
        'app', (tester) async {
      await pumpLibrary(tester);

      expect(find.text(es.emptyLibraryTitle), findsOneWidget);
      expect(find.text(es.emptyLibraryMessage), findsOneWidget);
    });

    testWidgets('una búsqueda sin coincidencias dice QUÉ se buscó, no un '
        '"no hay nada" genérico', (tester) async {
      await harness.capture('una nota sobre filosofía');
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'zoología');
      await tester.pumpAndSettle();

      expect(find.text(es.librarySearchEmpty('zoología')), findsOneWidget);
      // Y no se confunde con la biblioteca vacía: sí hay cosas guardadas.
      expect(find.text(es.emptyLibraryTitle), findsNothing);
    });

    testWidgets('unos filtros demasiado estrechos ofrecen la salida', (
      tester,
    ) async {
      // El usuario puede no darse cuenta de que dejó un filtro puesto; sin el
      // botón, la biblioteca parece vacía sin motivo.
      await harness.capture('una nota');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(find.text(es.sourceKindYoutube));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(find.text(es.libraryFilterEmpty), findsOneWidget);
      expect(find.text(es.libraryClearFilters), findsOneWidget);
    });

    testWidgets('limpiar los filtros devuelve la lista', (tester) async {
      await harness.capture('una nota');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(find.text(es.sourceKindYoutube));
      await tester.pumpAndSettle();
      await closeFilters(tester);
      await tester.tap(find.text(es.libraryClearFilters));
      await tester.pumpAndSettle();

      expect(find.text('una nota'), findsOneWidget);
    });
  });

  group('el panel de salud (F9)', () {
    testWidgets('con elementos, va al tope de la pantalla de inicio', (
      tester,
    ) async {
      await harness.capture('Una nota cualquiera');
      await pumpLibrary(tester);

      expect(find.byType(HealthPanel), findsOneWidget);
      // Plegado, pero con los cuatro indicadores a la vista: una fila.
      for (final indicator in [
        es.healthInboxLabel,
        es.healthNotesLabel,
        es.healthVocabularyLabel,
        es.healthContradictionsLabel,
      ]) {
        expect(find.byTooltip(indicator), findsOneWidget, reason: indicator);
      }
      // Por encima de la lista, no debajo.
      final panelY = tester.getTopLeft(find.byType(HealthPanel)).dy;
      final listY = tester.getTopLeft(find.text('Una nota cualquiera')).dy;
      expect(panelY, lessThan(listY));
    });

    testWidgets(
      'en una biblioteca vacía no hay nada que mantener: no aparece',
      (tester) async {
        await pumpLibrary(tester);

        expect(find.byType(HealthPanel), findsNothing);
      },
    );

    testWidgets('con una búsqueda sin resultados tampoco: sería ruido', (
      tester,
    ) async {
      await harness.capture('una nota sobre filosofía');
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'zoología');
      await tester.pumpAndSettle();

      expect(find.byType(HealthPanel), findsNothing);
    });
  });

  group('la oferta de compactar (F12)', () {
    final offer = find.byKey(const ValueKey('compaction-offer'));

    /// Lo que un borrado grande deja: unos 90 MB de páginas libres dentro de la
    /// base, bastante más que el mínimo para ofrecer devolverlos.
    Future<void> leaveLotsOfFreePages() async {
      final db = harness.database;
      await db.customStatement(
        'CREATE TABLE relleno (id INTEGER PRIMARY KEY, v BLOB NOT NULL)',
      );
      await db.customStatement('''
        WITH RECURSIVE n(x) AS (
          SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 30000
        )
        INSERT INTO relleno (v) SELECT randomblob(3000) FROM n''');
      await db.customStatement('DELETE FROM relleno');
    }

    testWidgets('con mucho para devolver, va al tope, sobre el panel de '
        'salud', (tester) async {
      await harness.capture('Una nota cualquiera');
      await leaveLotsOfFreePages();
      await pumpLibrary(tester);

      expect(offer, findsOneWidget);
      final offerY = tester.getTopLeft(offer).dy;
      final panelY = tester.getTopLeft(find.byType(HealthPanel)).dy;
      final listY = tester.getTopLeft(find.text('Una nota cualquiera')).dy;
      expect(offerY, lessThan(panelY));
      expect(panelY, lessThan(listY));
    });

    testWidgets('«Ahora no» la quita y el resto de la pantalla sigue', (
      tester,
    ) async {
      await harness.capture('Una nota cualquiera');
      await leaveLotsOfFreePages();
      await pumpLibrary(tester);

      await tester.tap(find.text(es.vaultCompactionOfferNotNow));
      await tester.pumpAndSettle();

      expect(offer, findsNothing);
      expect(find.byType(HealthPanel), findsOneWidget);
      expect(find.text('Una nota cualquiera'), findsOneWidget);
    });

    testWidgets('en una bóveda al día no aparece', (tester) async {
      await harness.capture('Una nota cualquiera');
      await pumpLibrary(tester);

      expect(offer, findsNothing);
    });
  });

  group('la lista', () {
    testWidgets('muestra lo guardado con su título', (tester) async {
      await harness.capture('La estructura de las revoluciones');
      await pumpLibrary(tester);

      expect(find.text('La estructura de las revoluciones'), findsOneWidget);
    });

    testWidgets('se actualiza sola cuando entra algo nuevo, sin recargar', (
      tester,
    ) async {
      // Es lo que hace que volver de la captura muestre el elemento ya
      // puesto, y lo que va a hacer aparecer una transcripción cuando
      // termine en segundo plano.
      await pumpLibrary(tester);
      expect(find.text('Recién llegado'), findsNothing);

      await harness.capture('Recién llegado');
      await tester.pumpAndSettle();

      expect(find.text('Recién llegado'), findsOneWidget);
    });

    testWidgets('marca lo que todavía está pendiente', (tester) async {
      await harness.capture('https://ejemplo.org/un-articulo-guardado');
      await pumpLibrary(tester);

      expect(find.text(es.processingPending), findsOneWidget);
    });

    testWidgets('lo que está en curso muestra cuánto va, con su barra', (
      tester,
    ) async {
      // Un libro de cientos de páginas o un video de horas se ve avanzar
      // desde la lista, sin abrirlo (F21).
      final result = await harness.container.read(captureItemUseCaseProvider)(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/un-libro'),
      );
      final id = result.getRight().toNullable()!.id;
      harness.queue.showProgress({
        id: const ProcessingProgress(
          lane: ProcessingLane.long,
          done: 1,
          total: 4,
        ),
      });

      await pumpLibrary(tester);

      expect(find.text(es.processingProgressLabel(25)), findsOneWidget);
      expect(find.text(es.processingPending), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('lo que espera turno detrás de otro trabajo largo lo dice', (
      tester,
    ) async {
      final result = await harness.container.read(captureItemUseCaseProvider)(
        const CaptureRequest.text(rawInput: 'https://ejemplo.org/otro-video'),
      );
      final id = result.getRight().toNullable()!.id;
      harness.queue.showProgress({
        id: const ProcessingProgress(lane: ProcessingLane.waitingForLong),
      });

      await pumpLibrary(tester);

      expect(find.text(es.processingWaitingForLong), findsOneWidget);
    });

    testWidgets('no marca lo que ya está completo: una insignia de "listo" '
        'en cada fila sería ruido', (tester) async {
      await harness.capture('una nota que ya está completa');
      await pumpLibrary(tester);

      expect(find.text(es.processingPending), findsNothing);
      expect(find.text(es.processingFailed), findsNothing);
    });

    testWidgets('una imagen guardada muestra su propia foto como portada', (
      tester,
    ) async {
      final result = await harness.container.read(captureItemUseCaseProvider)(
        CaptureRequest.file(
          file: CapturedFile(name: 'foto.png', bytes: fakePngBytes()),
        ),
      );
      expect(result.isRight(), isTrue);

      await pumpLibrary(tester);

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('una nota de texto se queda con el ícono, sin portada', (
      tester,
    ) async {
      await harness.capture('una nota sin ningún archivo');
      await pumpLibrary(tester);

      expect(find.byType(Image), findsNothing);
    });
  });

  group('insignia de nota mapa', () {
    testWidgets('una nota marcada como mapa aparece con la insignia', (
      tester,
    ) async {
      await harness.capture('una nota mapa');
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final id = items.firstWhere((i) => i.title == 'una nota mapa').id;
      await harness.container
          .read(inboxRepositoryProvider)
          .setNoteKind(itemId: id, kind: NoteKind.map);

      await pumpLibrary(tester);

      expect(find.byTooltip(es.noteKindMap), findsOneWidget);
    });

    testWidgets('una nota sin marcar no muestra la insignia', (tester) async {
      await harness.capture('una nota sin marcar');
      await pumpLibrary(tester);

      expect(find.byTooltip(es.noteKindMap), findsNothing);
    });

    testWidgets('una fuente no muestra la insignia', (tester) async {
      await harness.capture('https://ejemplo.org/un-articulo');
      await pumpLibrary(tester);

      expect(find.byTooltip(es.noteKindMap), findsNothing);
    });
  });

  group('buscar y filtrar', () {
    testWidgets('la búsqueda encuentra por contenido, no solo por título', (
      tester,
    ) async {
      await harness.capture('Un título cualquiera\n\nadentro habla de enzimas');
      await harness.capture('Otra nota sin relación');
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'enzimas');
      await tester.pumpAndSettle();

      expect(find.text('Un título cualquiera'), findsOneWidget);
      expect(find.text('Otra nota sin relación'), findsNothing);
    });

    testWidgets('el filtro por tipo deja solo lo que corresponde', (
      tester,
    ) async {
      await harness.capture('una nota escrita');
      await harness.capture('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(find.text(es.sourceKindYoutube));
      await tester.pumpAndSettle();

      expect(find.text('una nota escrita'), findsNothing);
      expect(find.textContaining('dQw4w9WgXcQ'), findsOneWidget);
    });

    testWidgets(
      'sin ninguna etiqueta puesta, el panel de filtros no ofrece una '
      'sección de etiquetas',
      (tester) async {
        // Mostrarla vacía sería ocupar lugar para decir "no hay nada por lo
        // que filtrar", que no es información que alguien necesite ver
        // siempre — y menos en una biblioteca recién estrenada.
        await harness.capture('una nota sin etiquetas');
        await pumpLibrary(tester);

        // La barra ya no crece ni se achica según haya o no etiquetas: tema,
        // tipo y etiquetas viven detrás del mismo botón — ver
        // `_FiltersSheet`.
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.bottom!.preferredSize.height, 64);

        await openFilters(tester);

        // Los encabezados de sección se muestran en mayúsculas — ver
        // `_FilterSectionLabel`.
        expect(
          find.text(es.libraryFilterTypeLabel.toUpperCase()),
          findsOneWidget,
        );
        expect(
          find.text(es.libraryFilterTagsLabel.toUpperCase()),
          findsNothing,
        );
      },
    );

    testWidgets('con al menos una etiqueta, el panel sí la ofrece', (
      tester,
    ) async {
      await harness.capture('algo etiquetado');
      await harness.container
          .read(organizeRepositoryProvider)
          .getOrCreateTag('Cualquiera');
      await pumpLibrary(tester);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom!.preferredSize.height, 64);

      await openFilters(tester);

      expect(
        find.text(es.libraryFilterTagsLabel.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text('Cualquiera'), findsOneWidget);
    });

    testWidgets('el filtro por etiqueta deja solo lo que corresponde', (
      tester,
    ) async {
      await harness.capture('un artículo de filosofía');
      await harness.capture('una nota sobre cocina');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final filosofico = items.firstWhere((i) => i.title.contains('filosofía'));
      final tag =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .getOrCreateTag('Filosofía'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .save(filosofico.copyWith(tags: [tag]));

      await pumpLibrary(tester);
      await openFilters(tester);
      // Las etiquetas van al final del panel: en una pantalla chica, más abajo
      // del borde, como para quien las busca con el dedo.
      await tester.ensureVisible(find.text('Filosofía'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();

      expect(find.textContaining('filosofía'), findsOneWidget);
      expect(find.textContaining('cocina'), findsNothing);
    });

    testWidgets(
      'un filtro de etiqueta que no coincide con nada ofrece limpiarlo',
      (tester) async {
        await harness.capture('algo sin esa etiqueta');
        // La etiqueta existe pero nadie la tiene puesta: puede pasar
        // perfectamente —se creó para otra cosa, o se está probando el
        // filtro— y el chip para filtrar por ella igual aparece, porque sale
        // de todo el vocabulario y no de lo que hay visible en ese momento.
        await harness.container
            .read(organizeRepositoryProvider)
            .getOrCreateTag('Sin uso');

        await pumpLibrary(tester);
        await openFilters(tester);
        // Las etiquetas van al final del panel: en una pantalla chica,
        // más abajo del borde, como para quien las busca con el dedo.
        await tester.ensureVisible(find.text('Sin uso'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sin uso'));
        await tester.pumpAndSettle();
        await closeFilters(tester);

        expect(find.text(es.libraryFilterEmpty), findsOneWidget);

        await tester.tap(find.text(es.libraryClearFilters));
        await tester.pumpAndSettle();

        expect(find.text('algo sin esa etiqueta'), findsOneWidget);
      },
    );

    testWidgets('crear un espacio y elegirlo deja solo lo que contiene', (
      tester,
    ) async {
      await harness.capture('un artículo de filosofía');
      await harness.capture('una nota sobre cocina');

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final filosofico = items.firstWhere((i) => i.title.contains('filosofía'));
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Filosofía'))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: filosofico.id, spaceId: space.id);

      await pumpLibrary(tester);
      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(find.textContaining('filosofía'), findsOneWidget);
      expect(find.textContaining('cocina'), findsNothing);

      // Tocarlo de nuevo vuelve a "todos" — un espacio es una carpeta en la
      // que se entra y se sale, no un filtro que se combina con otros.
      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(find.textContaining('cocina'), findsOneWidget);
    });

    testWidgets('con algún tema creado, la biblioteca no ofrece crear otro '
        'suelto: se crea donde se elige uno', (tester) async {
      await harness.capture('una nota sin espacio');
      await harness.container
          .read(organizeRepositoryProvider)
          .createSpace('Filosofía');
      await pumpLibrary(tester);

      expect(find.text(es.spacesNewAction), findsNothing);

      // El botón de crear solo está mientras no hay ninguno —ver el grupo
      // de abajo—.
      await openFilters(tester);
      expect(find.text(es.spacesNewAction), findsNothing);
    });
  });

  group('el tema en el panel de filtros', () {
    Future<Space> createSpace(String name) async =>
        (await harness.container
                .read(organizeRepositoryProvider)
                .createSpace(name))
            .getRight()
            .toNullable()!;

    Future<void> assign(String title, Space space) async {
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(
            itemId: items.firstWhere((i) => i.title == title).id,
            spaceId: space.id,
          );
    }

    Finder filtersBadge() => find.ancestor(
      of: find.byTooltip(es.libraryFiltersTooltip),
      matching: find.byType(Badge),
    );

    testWidgets('va arriba de «Tipo»', (tester) async {
      await harness.capture('algo');
      await createSpace('Filosofía');
      await pumpLibrary(tester);

      await openFilters(tester);

      final spaceY = tester
          .getTopLeft(find.text(es.libraryFilterSpaceLabel.toUpperCase()))
          .dy;
      final typeY = tester
          .getTopLeft(find.text(es.libraryFilterTypeLabel.toUpperCase()))
          .dy;
      expect(spaceY, lessThan(typeY));
      expect(spaceChip('Filosofía'), findsOneWidget);
    });

    testWidgets('sin ningún tema creado, la sección está igual: dice para '
        'qué sirven y crea el primero sin elegirlo', (tester) async {
      await harness.capture('algo');
      await pumpLibrary(tester);

      await openFilters(tester);

      // Escondida, quien recién empieza no se entera de que puede filtrar
      // por tema.
      expect(
        find.text(es.libraryFilterSpaceLabel.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text(es.spacesFilterEmptyMessage), findsOneWidget);

      await tester.tap(find.text(es.spacesNewAction));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Filosofía',
      );
      await tester.tap(find.text(es.commonCreate));
      await tester.pumpAndSettle();

      expect(spaceChip('Filosofía'), findsOneWidget);
      expect(find.text(es.spacesFilterEmptyMessage), findsNothing);
      // Recién creado está vacío: elegirlo dejaría la lista vacía de golpe.
      expect(
        harness.container.read(libraryQueryNotifierProvider).spaceId,
        isNull,
      );
      expect(tester.widget<Badge>(filtersBadge()).isLabelVisible, isFalse);
    });

    testWidgets('borrar desde el Explorador el tema en el que está parada la '
        'biblioteca también la saca de él', (tester) async {
      await harness.capture('Afuera');
      final space = await createSpace('Cocina');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Cocina'));
      await tester.pumpAndSettle();
      await closeFilters(tester);
      expect(find.widgetWithText(InputChip, 'Cocina'), findsOneWidget);

      // Desde otra pantalla: este panel no se enteró de nada.
      await harness.container
          .read(organizeRepositoryProvider)
          .deleteSpace(space.id);
      await tester.pumpAndSettle();

      expect(
        harness.container.read(libraryQueryNotifierProvider).spaceId,
        isNull,
      );
      expect(find.widgetWithText(InputChip, 'Cocina'), findsNothing);
      expect(tester.widget<Badge>(filtersBadge()).isLabelVisible, isFalse);
      expect(find.text('Afuera'), findsOneWidget);
    });

    testWidgets('elegir un tema cuenta en la insignia y lo muestra debajo de '
        'la búsqueda; tocarlo de nuevo lo suelta', (tester) async {
      await harness.capture('En el tema');
      await harness.capture('Afuera');
      await assign('En el tema', await createSpace('Filosofía'));
      await pumpLibrary(tester);

      expect(tester.widget<Badge>(filtersBadge()).isLabelVisible, isFalse);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      final badge = tester.widget<Badge>(filtersBadge());
      expect(badge.isLabelVisible, isTrue);
      expect((badge.label! as Text).data, '1');
      // Sin la fila de temas, el chip de abajo de la búsqueda es lo que dice
      // en qué tema se está parado.
      expect(find.widgetWithText(InputChip, 'Filosofía'), findsOneWidget);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.bottom!.preferredSize.height, 104);
      expect(find.text('Afuera'), findsNothing);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(tester.widget<Badge>(filtersBadge()).isLabelVisible, isFalse);
      expect(find.widgetWithText(InputChip, 'Filosofía'), findsNothing);
      expect(find.text('Afuera'), findsOneWidget);
    });

    testWidgets('se elige de a uno: elegir otro reemplaza al anterior', (
      tester,
    ) async {
      await harness.capture('algo');
      await createSpace('Filosofía');
      await createSpace('Cocina');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await tester.tap(spaceChip('Cocina'));
      await tester.pumpAndSettle();

      final selected = [
        for (final chip in tester.widgetList<FilterChip>(
          find.descendant(
            of: find.byKey(SpaceFilterSection.chipsKey),
            matching: find.byType(FilterChip),
          ),
        ))
          if (chip.selected) (chip.label as Text).data,
      ];
      expect(selected, ['Cocina']);
    });

    testWidgets('la cruz del chip de abajo de la búsqueda sale del tema', (
      tester,
    ) async {
      await harness.capture('Afuera');
      await createSpace('Filosofía');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await closeFilters(tester);
      await tester.tap(find.byTooltip(es.libraryLeaveSpaceTooltip));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(libraryQueryNotifierProvider).spaceId,
        isNull,
      );
      expect(find.text('Afuera'), findsOneWidget);
    });

    testWidgets('«Limpiar filtros» también suelta el tema', (tester) async {
      await harness.capture('Afuera');
      await createSpace('Filosofía');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Filosofía'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryClearFilters).last);
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(
        harness.container.read(libraryQueryNotifierProvider).spaceId,
        isNull,
      );
      expect(tester.widget<Badge>(filtersBadge()).isLabelVisible, isFalse);
      expect(find.text('Afuera'), findsOneWidget);
    });

    testWidgets('un tema vacío ofrece salir con «Limpiar filtros», como '
        'cualquier filtro que deja la lista vacía', (tester) async {
      await harness.capture('Afuera');
      await createSpace('Vacío');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Vacío'));
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(find.text(es.libraryFilterEmpty), findsOneWidget);

      await tester.tap(find.text(es.libraryClearFilters));
      await tester.pumpAndSettle();

      expect(find.text('Afuera'), findsOneWidget);
    });

    testWidgets('con pocos temas no hay barra de desplazamiento', (
      tester,
    ) async {
      await harness.capture('algo');
      await createSpace('Filosofía');
      await createSpace('Cocina');
      await pumpLibrary(tester);

      await openFilters(tester);

      final scrollbar = tester.widget<RawScrollbar>(
        find.descendant(
          of: find.byKey(SpaceFilterSection.chipsKey),
          matching: find.byType(RawScrollbar),
        ),
      );
      expect(scrollbar.thumbVisibility, isFalse);
    });

    testWidgets('con muchos temas, el área tiene un tope, se desplaza con '
        'la barra siempre a la vista y llega hasta el último', (tester) async {
      await harness.capture('algo');
      // Nombres de largo parejo y con el número adelante: así se ordenan
      // igual de alfabético que de numérico, y el último es el último.
      for (var i = 10; i < 50; i++) {
        await createSpace('$i Tema bastante largo');
      }
      await pumpLibrary(tester);

      await openFilters(tester);

      final area = find.byKey(SpaceFilterSection.chipsKey);
      // Unas tres filas y media de chips, no los cuarenta temas apilados.
      expect(tester.getSize(area).height, lessThanOrEqualTo(200));
      expect(
        tester
            .getTopLeft(find.text(es.libraryFilterTypeLabel.toUpperCase()))
            .dy,
        greaterThan(tester.getBottomLeft(area).dy),
      );

      final scrollbar = tester.widget<RawScrollbar>(
        find.descendant(of: area, matching: find.byType(RawScrollbar)),
      );
      expect(scrollbar.thumbVisibility, isTrue);

      final last = spaceChip('49 Tema bastante largo');
      await tester.dragUntilVisible(
        last,
        find.descendant(of: area, matching: find.byType(Scrollable)),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();

      expect(
        harness.container.read(libraryQueryNotifierProvider).spaceId,
        isNotNull,
      );
    });

    testWidgets(
      'el tema elegido ofrece renombrarlo o borrarlo desde su ícono',
      (tester) async {
        await harness.capture('algo');
        await createSpace('Cocina');
        await pumpLibrary(tester);

        await openFilters(tester);
        // Sin elegir, el ícono no está: mantener apretado sigue sirviendo.
        expect(find.byTooltip(es.librarySpaceManageTooltip), findsNothing);

        await tester.tap(spaceChip('Cocina'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(es.librarySpaceManageTooltip));
        await tester.pumpAndSettle();

        expect(find.text(es.spacesRenameAction), findsOneWidget);
        expect(find.text(es.spacesDeleteAction), findsOneWidget);
      },
    );

    testWidgets('borrar el tema elegido sale de él', (tester) async {
      await harness.capture('Afuera');
      await createSpace('Cocina');
      await pumpLibrary(tester);

      await openFilters(tester);
      await tester.tap(spaceChip('Cocina'));
      await tester.pumpAndSettle();
      await tester.longPress(spaceChip('Cocina'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesDeleteAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesDeleteAction).last);
      await tester.pumpAndSettle();

      expect(
        harness.container.read(libraryQueryNotifierProvider).spaceId,
        isNull,
      );
      expect(spaceChip('Cocina'), findsNothing);
      await closeFilters(tester);
      expect(find.text('Afuera'), findsOneWidget);
    });
  });

  group('el nombre de un tema contra las etiquetas (F11)', () {
    Future<List<String>> spaceNames() async => [
      for (final row
          in await harness.database.select(harness.database.spaces).get())
        row.name,
    ];

    Future<void> createTag(String name) =>
        harness.container.read(organizeRepositoryProvider).getOrCreateTag(name);

    /// Crea el tema desde "Mover a tema" de una fila: la biblioteca ya no
    /// tiene un botón suelto para crear uno —se crea donde se elige—.
    Future<void> startCreating(WidgetTester tester, String name) async {
      await pumpLibrary(tester);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryItemMoveToSpace));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesNewAction));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.text(es.commonCreate));
      await tester.pumpAndSettle();
    }

    testWidgets('un nombre que ninguna etiqueta tiene se crea sin avisar', (
      tester,
    ) async {
      await harness.capture('algo');

      await startCreating(tester, 'Cocina');

      expect(find.text(es.spacesNameIsTagTitle), findsNothing);
      expect(await spaceNames(), ['Cocina']);
    });

    testWidgets('el nombre de una etiqueta avisa, y cancelar no crea nada', (
      tester,
    ) async {
      await harness.capture('algo');
      await createTag('Filosofía');

      await startCreating(tester, 'filosofia');

      expect(find.text(es.spacesNameIsTagTitle), findsOneWidget);
      expect(find.text(es.spacesNameIsTagBody('filosofia')), findsOneWidget);

      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await spaceNames(), isEmpty);
    });

    testWidgets('«Crear igual» lo crea a pesar del aviso', (tester) async {
      await harness.capture('algo');
      await createTag('Filosofía');

      await startCreating(tester, 'Filosofía');
      await tester.tap(find.text(es.spacesNameIsTagCreate));
      await tester.pumpAndSettle();

      expect(await spaceNames(), ['Filosofía']);
    });

    Future<void> startRenaming(
      WidgetTester tester,
      String from,
      String to,
    ) async {
      await harness.container
          .read(organizeRepositoryProvider)
          .createSpace(from);
      await pumpLibrary(tester);
      await openFilters(tester);
      await tester.longPress(spaceChip(from));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.spacesRenameAction).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, to);
      await tester.tap(find.text(es.detailSave).last);
      await tester.pumpAndSettle();
    }

    testWidgets('renombrar a una etiqueta existente avisa, y «Renombrar '
        'igual» lo renombra', (tester) async {
      await harness.capture('algo');
      await createTag('Filosofía');

      await startRenaming(tester, 'Cocina', 'Filosofía');

      expect(find.text(es.spacesNameIsTagTitle), findsOneWidget);
      await tester.tap(find.text(es.spacesNameIsTagRename));
      await tester.pumpAndSettle();

      expect(await spaceNames(), ['Filosofía']);
    });

    testWidgets('renombrar y cancelar el aviso deja el nombre como estaba', (
      tester,
    ) async {
      await harness.capture('algo');
      await createTag('Filosofía');

      await startRenaming(tester, 'Cocina', 'Filosofía');
      await tester.tap(find.text(es.commonCancel));
      await tester.pumpAndSettle();

      expect(await spaceNames(), ['Cocina']);
    });

    testWidgets('quedarse con su propio nombre no avisa: no es un nombre '
        'nuevo', (tester) async {
      await harness.capture('algo');
      await createTag('Filosofía');

      // El tema se llama igual que una etiqueta desde antes: solo se le
      // cambian las mayúsculas.
      await startRenaming(tester, 'Filosofía', 'filosofía');

      expect(find.text(es.spacesNameIsTagTitle), findsNothing);
      expect(await spaceNames(), ['filosofía']);
    });
  });

  group('la búsqueda dice DÓNDE está lo encontrado (F10)', () {
    final now = DateTime(2026, 9, 19, 10);

    /// Guarda una fuente con su texto por el repositorio, como lo hace la app:
    /// `save()` la fragmenta, y de esos chunks sale la cita.
    Future<KnowledgeItem> saveSource(
      String title,
      String text, {
      SourceKind kind = SourceKind.youtube,
    }) async {
      final item = KnowledgeItem(
        id: 'fuente-${title.hashCode}',
        title: title,
        source: Source(
          id: 'src-${title.hashCode}',
          kind: kind,
          capturedAt: now,
          url: 'https://ejemplo.org/${title.hashCode}',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
        renditions: [
          Rendition.text(
            id: 'rend-${title.hashCode}',
            itemId: 'fuente-${title.hashCode}',
            kind: RenditionKind.markdown,
            content: text,
            isPrimary: true,
            createdAt: now,
          ),
        ],
      );
      final result = await harness.container
          .read(libraryRepositoryProvider)
          .save(item);
      return result.getRight().toNullable()!;
    }

    const transcript =
        '[00:00] Introducción al tema de hoy.\n'
        '[00:30] Seguimos con la introducción.\n'
        '[01:20] Aquí hablamos del paradigma científico.\n'
        '[02:10] Y cerramos con las conclusiones.';

    testWidgets('una transcripción muestra el minuto y el fragmento con lo '
        'buscado', (tester) async {
      await saveSource('Charla grabada', transcript);
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'paradigma');
      await tester.pumpAndSettle();

      expect(find.text('Charla grabada'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'^\d+:\d{2}$').hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );
      // Dentro de la tarjeta: el texto de la búsqueda, arriba, también lo dice.
      expect(
        find.descendant(
          of: find.byType(LibraryItemCard),
          matching: find.textContaining('paradigma', findRichText: true),
        ),
        findsOneWidget,
      );
    });

    testWidgets('lo que solo coincide por el título no muestra fragmento', (
      tester,
    ) async {
      await saveSource('Sobre el paradigma', 'Sin nada relacionado.');
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'paradigma');
      await tester.pumpAndSettle();

      expect(find.text('Sobre el paradigma'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.byTooltip(es.searchCitationOpen), findsNothing);
    });

    testWidgets('sin texto buscado no hay fragmentos', (tester) async {
      await saveSource('Charla grabada', transcript);
      await pumpLibrary(tester);

      expect(find.text('Charla grabada'), findsOneWidget);
      expect(find.byTooltip(es.searchCitationOpen), findsNothing);
    });

    testWidgets('una fuente con página la cita con su número', (tester) async {
      final item = await saveSource(
        'Un documento',
        'El paradigma, en la página.',
        kind: SourceKind.document,
      );
      final db = harness.container.read(appDatabaseProvider);
      await (db.update(db.chunks)..where((c) => c.itemId.equals(item.id)))
          .write(const ChunksCompanion(pageNumber: Value(34)));
      await pumpLibrary(tester);

      await tester.enterText(find.byType(TextField).first, 'paradigma');
      await tester.pumpAndSettle();

      expect(find.text(es.searchCitationPage(34)), findsOneWidget);
    });

    testWidgets('tocar el fragmento abre la vista de lectura en ese '
        'fragmento', (tester) async {
      await saveSource('Charla grabada', transcript);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'paradigma');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(es.searchCitationOpen));
      await tester.pumpAndSettle();

      expect(find.byType(ReadingScreen), findsOneWidget);
    });

    testWidgets('tocar la fila, fuera del fragmento, sigue abriendo el '
        'detalle', (tester) async {
      await saveSource('Charla grabada', transcript);
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'paradigma');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Charla grabada'));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });
  });

  group('navegación', () {
    testWidgets('tocar una fila abre su detalle', (tester) async {
      await harness.capture('Algo para abrir');

      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Algo para abrir'));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });

    testWidgets('el botón de guardar lleva a la captura', (tester) async {
      await tester.pumpWidget(harness.wrapWithAppRouter());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureScreen), findsOneWidget);
    });

    testWidgets(
      'el botón de transcripción, desde ajustes, lleva a esa pantalla',
      (tester) async {
        // El acceso a la pantalla de transcripción se mudó de un ícono en
        // el AppBar de la biblioteca a la pantalla de Ajustes — ver la
        // decisión 22 en docs/arquitectura.md.
        await tester.pumpWidget(harness.wrapWithAppRouter());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        // Ajustes crece con cada sección —la IA de F27 empujó los modelos
        // hacia abajo—: como haría una persona, se desplaza hasta la fila
        // antes de tocarla, en vez de depender de que entre en la ventana.
        // `hitTestable`: que esté construida no alcanza, la lista arma de
        // más fuera de la vista; tiene que poder tocarse.
        final transcription = find
            .text(es.libraryTranscriptionModelTooltip)
            .hitTestable();
        await tester.scrollUntilVisible(
          transcription,
          200,
          scrollable: find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(transcription);
        await tester.pumpAndSettle();

        expect(find.byType(TranscriptionModelScreen), findsOneWidget);
      },
    );
  });

  group('selección múltiple', () {
    testWidgets('el ícono de seleccionar activa el modo, sin elegir nada '
        'todavía', (tester) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      expect(find.text(es.librarySelectedCount(0)), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('mantener presionada una fila entra al modo y la elige', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();

      expect(find.text(es.librarySelectedCount(1)), findsOneWidget);
    });

    testWidgets(
      'en modo selección, tocar una fila alterna la casilla en vez de '
      'navegar',
      (tester) async {
        await harness.capture('Uno');
        await pumpLibrary(tester);

        await tester.tap(find.byIcon(Icons.checklist));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Uno'));
        await tester.pumpAndSettle();

        expect(find.text(es.librarySelectedCount(1)), findsOneWidget);
        expect(find.byType(LibraryScreen), findsOneWidget);

        await tester.tap(find.text('Uno'));
        await tester.pumpAndSettle();

        expect(find.text(es.librarySelectedCount(0)), findsOneWidget);
      },
    );

    testWidgets('cancelar la selección vuelve a la barra normal', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text(es.libraryTitle), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsOneWidget);
    });

    testWidgets('sin nada elegido, exportar está deshabilitado', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.upload_file_outlined),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('exporta lo elegido para NotebookLM y confirma', (
      tester,
    ) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      harness.notebookLmDirectoryChooser.path = '/mi/carpeta';
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.upload_file_outlined));
      await tester.pumpAndSettle();

      // Los dos elegidos, más el índice.
      expect(harness.notebookLmDirectoryWriter.written, hasLength(3));
      expect(
        find.text(es.libraryExportPackageSaved(3, '/mi/carpeta')),
        findsOneWidget,
      );
      // Terminado el paquete, no queda nada seleccionado.
      expect(find.byIcon(Icons.checklist), findsOneWidget);
    });

    // La lista no trae el texto de los elementos: la exportación lo pide
    // completo antes de armar el paquete. Sin esto el paquete salía con los
    // títulos y sin una sola línea de texto, sin ningún aviso.
    testWidgets('el paquete lleva el texto de lo elegido, no solo los '
        'títulos', (tester) async {
      await harness.capture(
        'Frase única del primer libro para NotebookLM.',
        title: 'Uno',
      );
      harness.notebookLmDirectoryChooser.path = '/mi/carpeta';
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.upload_file_outlined));
      await tester.pumpAndSettle();

      final written = harness.notebookLmDirectoryWriter.written;
      final contents = [for (final bytes in written.values) utf8.decode(bytes)];
      expect(
        contents.any(
          (c) => c.contains('Frase única del primer libro para NotebookLM.'),
        ),
        isTrue,
        reason: 'ningún archivo del paquete trae el texto: $written',
      );
    });

    testWidgets(
      'cancelar el selector de carpeta no saca del modo de selección',
      (tester) async {
        await harness.capture('Uno');
        harness.notebookLmDirectoryChooser.path = null;
        await pumpLibrary(tester);

        await tester.longPress(find.text('Uno'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.upload_file_outlined));
        await tester.pumpAndSettle();

        expect(harness.notebookLmDirectoryWriter.written, isEmpty);
        expect(find.text(es.librarySelectedCount(1)), findsOneWidget);
      },
    );

    testWidgets('sin nada elegido, mover y eliminar están deshabilitados', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      final move = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.drive_file_move_outline),
      );
      final delete = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(move.onPressed, isNull);
      expect(delete.onPressed, isNull);
    });

    testWidgets('sin nada elegido, la bibliografía está deshabilitada (F15)', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.format_quote_outlined),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('exporta la bibliografía de lo elegido (F15, D13)', (
      tester,
    ) async {
      // Un texto suelto se captura como nota, que no cita nada de sí misma:
      // hace falta una fuente de verdad para que la bibliografía no salga
      // vacía.
      await harness.capture('https://ejemplo.org/uno', title: 'Uno');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.format_quote_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatMarkdown));
      await tester.pumpAndSettle();

      expect(
        harness.fileSaver.savedFileName,
        '${es.bibliographyExportSelectionName}.md',
      );
    });

    testWidgets('mueve lo elegido a un tema y confirma, de una vez', (
      tester,
    ) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await harness.capture('Tres');
      await harness.container
          .read(organizeRepositoryProvider)
          .createSpace('Filosofía');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.drive_file_move_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filosofía'));
      await tester.pumpAndSettle();

      expect(find.text(es.libraryBulkMoved(2, 'Filosofía')), findsOneWidget);
      // Terminado el movimiento, no queda nada seleccionado.
      expect(find.byIcon(Icons.checklist), findsOneWidget);

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final movedTitles = items
          .where((i) => i.spaceId != null)
          .map((i) => i.title)
          .toSet();
      expect(movedTitles, {'Uno', 'Dos'});
    });

    testWidgets('manda lo elegido a la papelera de una vez, sin preguntar, y '
        'avisa', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await harness.capture('Tres');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Uno'), findsNothing);
      expect(find.text('Dos'), findsNothing);
      expect(find.text('Tres'), findsOneWidget);
      expect(find.text(es.trashMoved(2)), findsOneWidget);
    });

    testWidgets('«Deshacer» devuelve a la biblioteca lo que se acaba de '
        'mandar a la papelera', (tester) async {
      await harness.capture('Uno');
      await harness.capture('Dos');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.trashUndo));
      await tester.pumpAndSettle();

      expect(find.text('Uno'), findsOneWidget);
      expect(find.text('Dos'), findsOneWidget);
    });
  });

  group('el menú de tres puntos de cada fila', () {
    testWidgets('eliminar lo manda a la papelera, lo saca de la lista y '
        'avisa', (tester) async {
      await harness.capture('Algo para borrar');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.detailDelete).last);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Algo para borrar'), findsNothing);
      expect(find.text(es.trashMoved(1)), findsOneWidget);
    });

    testWidgets('mover a un espacio lo deja asignado y avisa', (tester) async {
      await harness.capture('Por mover');
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Destino'))
              .getRight()
              .toNullable()!;
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryItemMoveToSpace));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destino'));
      await tester.pumpAndSettle();

      expect(find.text(es.libraryItemMoved('Destino')), findsOneWidget);

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      expect(items.firstWhere((i) => i.title == 'Por mover').spaceId, space.id);
    });

    testWidgets('el menú ofrece exportar solo como PDF o Word', (tester) async {
      await harness.capture('Para exportar');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(
        find.text(es.libraryItemExportAs(es.exportFormatPdf)),
        findsOneWidget,
      );
      expect(
        find.text(es.libraryItemExportAs(es.exportFormatDocx)),
        findsOneWidget,
      );
      for (final removed in [
        es.exportFormatMarkdown,
        es.exportFormatPlainText,
        es.exportFormatBibtex,
      ]) {
        expect(find.text(es.libraryItemExportAs(removed)), findsNothing);
      }
    });

    // La tarjeta viene de una lista, que no trae el texto: exportar pide el
    // elemento completo. Sin eso el Word salía con el título y nada más.
    testWidgets('el Word exportado desde la tarjeta lleva el texto', (
      tester,
    ) async {
      await harness.capture(
        'Frase única que tiene que estar en el Word exportado.',
        title: 'Para exportar',
      );
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryItemExportAs(es.exportFormatDocx)));
      await tester.pumpAndSettle();

      final docx = ZipDecoder().decodeBytes(harness.fileSaver.savedBytes!);
      final body = utf8.decode(
        docx.findFile('word/document.xml')!.content as List<int>,
      );
      expect(
        body,
        contains('Frase única que tiene que estar en el Word exportado.'),
      );
    });

    testWidgets('exportar pasa por el mismo selector de guardado', (
      tester,
    ) async {
      await harness.capture('Para exportar');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryItemExportAs(es.exportFormatDocx)));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, isNotNull);
      expect(find.text(es.libraryItemExported), findsOneWidget);
    });
  });

  group('vistas de la biblioteca', () {
    Future<void> switchView(WidgetTester tester, String label) async {
      await tester.tap(find.byType(PopupMenuButton<LibraryViewMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('la vista de tabla muestra una columna por propiedad', (
      tester,
    ) async {
      await harness.capture('Un artículo cualquiera');
      await pumpLibrary(tester);

      await switchView(tester, es.libraryViewTable);

      expect(find.text(es.libraryColumnTitle), findsOneWidget);
      expect(find.text(es.libraryColumnCaptured), findsOneWidget);
      expect(find.text('Un artículo cualquiera'), findsOneWidget);
    });

    testWidgets('tocar el encabezado de Título cambia el orden', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await switchView(tester, es.libraryViewTable);
      await tester.tap(find.text(es.libraryColumnTitle));
      await tester.pumpAndSettle();

      final query = harness.container.read(libraryQueryNotifierProvider);
      expect(query.sortBy, LibrarySort.title);
    });

    testWidgets('la vista de tablero agrupa por espacio', (tester) async {
      await harness.capture('Sin clasificar todavía');
      await harness.capture('Ya tiene espacio');
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Filosofía'))
              .getRight()
              .toNullable()!;

      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      final item = items.firstWhere((i) => i.title.contains('Ya tiene'));
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: item.id, spaceId: space.id);

      await pumpLibrary(tester);
      await switchView(tester, es.libraryViewKanban);

      // La columna del tablero: los temas ya no se repiten como chips
      // arriba de la lista —viven en el panel de filtros—.
      expect(find.text('Filosofía'), findsOneWidget);
      expect(find.text(es.detailSpaceNone), findsOneWidget);
      expect(find.textContaining('Sin clasificar todavía'), findsOneWidget);
      expect(find.textContaining('Ya tiene espacio'), findsOneWidget);
    });

    testWidgets('la columna de un espacio exporta su bibliografía (F15, D13)', (
      tester,
    ) async {
      await harness.capture('https://ejemplo.org/un-articulo');
      final space =
          (await harness.container
                  .read(organizeRepositoryProvider)
                  .createSpace('Filosofía'))
              .getRight()
              .toNullable()!;
      final items =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!;
      await harness.container
          .read(libraryRepositoryProvider)
          .assignSpace(itemId: items.single.id, spaceId: space.id);

      await pumpLibrary(tester);
      await switchView(tester, es.libraryViewKanban);
      await tester.tap(find.byIcon(Icons.format_quote_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatMarkdown));
      await tester.pumpAndSettle();

      expect(harness.fileSaver.savedFileName, 'Filosofía.md');
    });

    testWidgets(
      'la columna "sin clasificar" no ofrece bibliografía: no es un espacio',
      (tester) async {
        await harness.capture('Uno');
        await pumpLibrary(tester);

        await switchView(tester, es.libraryViewKanban);

        expect(find.byIcon(Icons.format_quote_outlined), findsNothing);
      },
    );
  });

  group('paginación', () {
    // El tamaño de tanda de `LibraryQueryNotifier` es 100: sin al menos esa
    // cantidad no hay manera de ejercitar "cargar más" de verdad.
    Future<void> captureMany(int count) async {
      for (var i = 0; i < count; i++) {
        await harness.capture('Elemento número $i');
      }
    }

    testWidgets('con menos elementos que una tanda, no ofrece cargar más', (
      tester,
    ) async {
      await captureMany(5);
      await pumpLibrary(tester);

      expect(find.text(es.libraryLoadMore), findsNothing);
    });

    testWidgets('con una tanda completa, ofrece cargar más', (tester) async {
      await captureMany(100);
      await pumpLibrary(tester);

      expect(find.text(es.libraryLoadMore), findsOneWidget);
    });

    testWidgets('tocar "cargar más" trae el resto sin perder lo que ya '
        'estaba', (tester) async {
      await captureMany(105);
      await pumpLibrary(tester);

      expect(find.text(es.libraryLoadMore), findsOneWidget);
      // Lo que ya se había traído sigue a la vista mientras se pide el
      // resto: no hay un spinner que lo tape por un instante.
      expect(find.textContaining('Elemento número'), findsWidgets);

      await tester.tap(find.text(es.libraryLoadMore));
      await tester.pumpAndSettle();

      // Con las 105 traídas, ya no queda nada más por cargar.
      expect(find.text(es.libraryLoadMore), findsNothing);
    });
  });

  group('retomar lo que quedó a medias', () {
    testWidgets('abrir la biblioteca pide traer lo que quedó pendiente', (
      tester,
    ) async {
      // Alguien pudo capturar cinco enlaces sin conexión y cerrar la app. Al
      // volver, eso tiene que completarse solo: si la pantalla no se lo
      // pidiera a la cola, quedaría esperando para siempre y el usuario no
      // tendría forma de saber que hay que pedirlo.
      await harness.capture('https://ejemplo.org/quedó-pendiente');

      await pumpLibrary(tester);

      expect(harness.queue.pendingSweeps, 1);
    });
  });

  group('importar referencias (F15, D9/D13/D14)', () {
    CapturedFile bibFile(String content) => CapturedFile(
      name: 'bib.bib',
      bytes: Uint8List.fromList(content.codeUnits),
    );

    testWidgets('cancelar el selector no hace nada', (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.byTooltip(es.libraryImportReferencesAction));
      await tester.pumpAndSettle();

      expect(harness.fileChooser.timesOpened, 1);
      expect(find.text(es.importReferencesReportTitle), findsNothing);
    });

    testWidgets('importa un .bib válido y muestra el informe', (tester) async {
      harness = await LibraryHarness.create(
        chosenFiles: [
          bibFile('@book{x, title = {Un libro}, author = {García, Ana}}'),
        ],
      );
      await pumpLibrary(tester);

      await tester.tap(find.byTooltip(es.libraryImportReferencesAction));
      await tester.pumpAndSettle();

      expect(find.text(es.importReferencesReportTitle), findsOneWidget);
      expect(find.text(es.importReferencesCreatedCount(1)), findsOneWidget);
    });

    testWidgets('un adjunto que coincide se encola para procesar', (
      tester,
    ) async {
      final pdf = CapturedFile(
        name: 'articulo.pdf',
        bytes: Uint8List.fromList('%PDF-1.7 contenido'.codeUnits),
      );
      harness = await LibraryHarness.create(
        chosenFiles: [
          bibFile('@book{x, title = {Un libro}, file = {articulo.pdf}}'),
          pdf,
        ],
      );
      await pumpLibrary(tester);

      await tester.tap(find.byTooltip(es.libraryImportReferencesAction));
      await tester.pumpAndSettle();

      expect(harness.queue.enqueued, hasLength(1));
    });
  });

  group('exportar referencias (F15, D15)', () {
    testWidgets('sin nada elegido, exportar referencias está deshabilitado', (
      tester,
    ) async {
      await harness.capture('Uno');
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.file_upload_outlined),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('exporta lo elegido como .bib', (tester) async {
      await harness.capture('https://ejemplo.org/uno', title: 'Uno');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.file_upload_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatBibtex));
      await tester.pumpAndSettle();

      expect(
        harness.fileSaver.savedFileName,
        '${es.exportReferencesFileName}.bib',
      );
      expect(
        String.fromCharCodes(harness.fileSaver.savedBytes!),
        contains('Uno'),
      );
    });

    testWidgets('exporta lo elegido como .ris', (tester) async {
      await harness.capture('https://ejemplo.org/uno', title: 'Uno');
      await pumpLibrary(tester);

      await tester.longPress(find.text('Uno'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.file_upload_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.referenceFileFormatRis));
      await tester.pumpAndSettle();

      expect(
        harness.fileSaver.savedFileName,
        '${es.exportReferencesFileName}.ris',
      );
    });

    testWidgets('una selección sin fuentes avisa que no hay nada que '
        'exportar', (tester) async {
      await harness.capture('una nota suelta');
      await pumpLibrary(tester);

      await tester.longPress(find.text('una nota suelta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.file_upload_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.exportFormatBibtex));
      await tester.pumpAndSettle();

      expect(find.text(es.exportReferencesEmpty), findsOneWidget);
      expect(harness.fileSaver.savedFileName, isNull);
    });
  });

  group('vistas guardadas (F16, D4)', () {
    testWidgets('sin ninguna guardada, la hoja lo avisa', (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.byTooltip(es.libraryViewsAction));
      await tester.pumpAndSettle();

      expect(find.text(es.libraryViewsEmpty), findsOneWidget);
    });

    testWidgets('guardar la vista actual la deja en la lista', (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.byTooltip(es.libraryViewsAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryViewsSaveCurrent));
      // Sin `pumpAndSettle`: el cursor del campo autoenfocado parpadea con
      // un temporizador propio, y unos cuadros bastan para que el diálogo
      // termine de entrar.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('saved-view-name-field')),
        'Mi vista',
      );
      await tester.tap(find.byKey(const Key('saved-view-confirm-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(es.libraryViewsSavedConfirmation('Mi vista')),
        findsOneWidget,
      );
      // La hoja sigue abierta —guardar no la cierra— y ya muestra la vista
      // recién creada, sin tener que volver a abrirla.
      expect(find.text('Mi vista'), findsOneWidget);
    });

    testWidgets('tocar una vista guardada la aplica y cierra la hoja', (
      tester,
    ) async {
      await harness.capture('https://ejemplo.org/uno', title: 'Uno');
      await pumpLibrary(tester);

      await harness.container
          .read(savedViewRepositoryProvider)
          .create(
            name: 'Por título',
            query: const LibraryQuery(sortBy: LibrarySort.title),
            viewMode: LibraryViewMode.table,
          );

      await tester.tap(find.byTooltip(es.libraryViewsAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Por título'));
      await tester.pumpAndSettle();

      // Se cerró la hoja, y el modo de vista cambió a tabla: no queda
      // rastro de la lista de siempre.
      expect(find.text(es.libraryViewsAction), findsNothing);
      expect(find.byType(LibraryTableView), findsOneWidget);
    });

    testWidgets('fijar una vista la muestra primero en la hoja', (
      tester,
    ) async {
      await pumpLibrary(tester);
      final repository = harness.container.read(savedViewRepositoryProvider);
      await repository.create(
        name: 'Primera',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );
      final second = await repository.create(
        name: 'Segunda',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );
      await repository.setPinned(second.id, pinned: true);

      await tester.tap(find.byTooltip(es.libraryViewsAction));
      await tester.pumpAndSettle();

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      final names = [
        for (final tile in tiles)
          if (tile.title case Text(:final data?)) data,
      ];
      expect(names.indexOf('Segunda'), lessThan(names.indexOf('Primera')));
    });

    testWidgets('eliminar una vista la saca de la lista', (tester) async {
      await pumpLibrary(tester);
      final repository = harness.container.read(savedViewRepositoryProvider);
      await repository.create(
        name: 'Para borrar',
        query: const LibraryQuery(),
        viewMode: LibraryViewMode.list,
      );

      await tester.tap(find.byTooltip(es.libraryViewsAction));
      await tester.pumpAndSettle();
      expect(find.text('Para borrar'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      // Sin `pumpAndSettle`: alcanza con que la base haya quedado sin la
      // fila, que es lo que esta prueba afirma —no hace falta esperar a que
      // la hoja termine de acomodarse a la lista vacía.
      await tester.pump();

      final db = harness.container.read(appDatabaseProvider);
      final rows = await db.customSelect('SELECT * FROM saved_view').get();
      expect(rows, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('vista de calendario (F16, D7)', () {
    late String fechaId;

    setUp(() async {
      fechaId =
          (await (harness.database.select(harness.database.propertyDefinitions)
                    ..where(
                      (d) =>
                          d.isSystem.equals(true) &
                          d.name.equals(kFechaDelHechoCategoryName),
                    ))
                  .getSingle())
              .id;
    });

    Future<void> switchToCalendar(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<LibraryViewMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(es.libraryViewCalendar));
      await tester.pumpAndSettle();
    }

    /// Toca el día [day] de la grilla. El `GridView.builder` de
    /// `_MonthGrid` —como cualquier sliver— solo MONTA de entrada los días
    /// que entran en el cache extent inicial; uno de fin de mes puede no
    /// estar montado todavía aunque ya esté construido, y ahí
    /// `tester.tap` no lo encuentra. `scrollUntilVisible` lo desplaza hasta
    /// que aparece.
    Future<void> tapDay(WidgetTester tester, int day) async {
      final finder = find.byKey(Key('calendar-day-$day'));
      await tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Scrollable),
        ),
      );
      // `scrollUntilVisible` termina con un salto (`Scrollable.ensureVisible`)
      // que recién se distribuye en el próximo cuadro: sin este `pump`, el
      // toque usaría la posición de antes del salto, y con una grilla más
      // alta el día puede quedar justo debajo del borde de la pantalla.
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    /// Le pone a [itemId] "Fecha del hecho" = hoy, día 15, con la precisión
    /// que se pida —"hoy" según el reloj fijo de las pruebas, el mismo que
    /// usa `LibraryCalendarView` para elegir el mes que muestra por
    /// defecto—.
    Future<void> setEventDate(
      String itemId, {
      required DatePrecision precision,
    }) async {
      final now = harness.container.read(clockProvider)();
      final organize = harness.container.read(organizeRepositoryProvider);
      final value = (await organize.getOrCreateHistoricalPropertyValue(
        definitionId: fechaId,
        date: HistoricalDate(
          year: now.year,
          month: now.month,
          day: 15,
          precision: precision,
        ),
      )).getRight().toNullable()!;
      await organize.assignProperty(
        itemId: itemId,
        definitionId: fechaId,
        value: value.value,
      );
    }

    testWidgets('el eje de fecha del hecho agrupa por día y lo abre al tocar', (
      tester,
    ) async {
      await harness.capture('Un hecho con fecha exacta');
      final item =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!
              .single;
      await setEventDate(item.id, precision: DatePrecision.day);

      await pumpLibrary(tester);
      await switchToCalendar(tester);

      expect(find.byType(LibraryCalendarView), findsOneWidget);
      await tapDay(tester, 15);

      expect(find.text('Un hecho con fecha exacta'), findsOneWidget);
    });

    testWidgets('un hecho sin precisión de día no aparece en el calendario', (
      tester,
    ) async {
      await harness.capture('Hecho impreciso');
      final item =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!
              .single;
      await setEventDate(item.id, precision: DatePrecision.month);

      await pumpLibrary(tester);
      await switchToCalendar(tester);
      await tapDay(tester, 15);

      expect(find.text('Hecho impreciso'), findsNothing);
    });

    testWidgets(
      'el eje de fecha de captura agrupa por cuándo se guardó, no por el '
      'hecho',
      (tester) async {
        await harness.capture('Guardado hoy');
        await pumpLibrary(tester);
        await switchToCalendar(tester);

        await tester.tap(find.text(es.libraryCalendarAxisCapturedAt));
        await tester.pumpAndSettle();

        // `harness.capture` guarda con el reloj fijo de las pruebas, no con
        // el de verdad: el día que hay que tocar es el de esa captura, no
        // el de hoy.
        final item =
            (await harness.container
                    .read(libraryRepositoryProvider)
                    .list(const LibraryQuery()))
                .getRight()
                .toNullable()!
                .single;
        await tapDay(tester, item.source.capturedAt.day);

        expect(find.text('Guardado hoy'), findsOneWidget);
      },
    );

    testWidgets('cambiar de mes deja el día tocado sin elementos', (
      tester,
    ) async {
      await harness.capture('Un hecho con fecha exacta');
      final item =
          (await harness.container
                  .read(libraryRepositoryProvider)
                  .list(const LibraryQuery()))
              .getRight()
              .toNullable()!
              .single;
      await setEventDate(item.id, precision: DatePrecision.day);

      await pumpLibrary(tester);
      await switchToCalendar(tester);
      await tester.tap(find.byTooltip(es.libraryCalendarNextMonth));
      await tester.pumpAndSettle();

      await tapDay(tester, 15);

      expect(find.text('Un hecho con fecha exacta'), findsNothing);
    });
  });

  group('la Bandeja en el panel de filtros (F28)', () {
    var counter = 0;

    /// Una fuente lista, pasada a [state] como la deja la Bandeja.
    Future<void> seedSource(String title, [ItemState? state]) async {
      final n = counter++;
      final now = DateTime(2026, 9, 18, 10).add(Duration(minutes: n));
      final item = KnowledgeItem(
        id: 'bandeja-$n',
        title: title,
        source: Source(
          id: 'src-bandeja-$n',
          kind: SourceKind.webPage,
          capturedAt: now,
          url: 'https://ejemplo.org/bandeja/$n',
        ),
        processingState: ProcessingState.ready,
        createdAt: now,
        updatedAt: now,
      );
      await harness.container.read(libraryRepositoryProvider).save(item);
      if (state != null) {
        await harness.container
            .read(inboxRepositoryProvider)
            .transitionState(itemId: item.id, to: state);
      }
    }

    Finder filtersBadge() => find.ancestor(
      of: find.byTooltip(es.libraryFiltersTooltip),
      matching: find.byType(Badge),
    );

    Finder inboxChip(String label) => find.widgetWithText(FilterChip, label);

    Future<void> tapInboxChip(WidgetTester tester, String label) async {
      await tester.ensureVisible(inboxChip(label));
      await tester.pumpAndSettle();
      await tester.tap(inboxChip(label));
      await tester.pumpAndSettle();
    }

    testWidgets('está la sección, con por revisar, triado y descartado', (
      tester,
    ) async {
      await seedSource('Algo');
      await pumpLibrary(tester);

      await openFilters(tester);

      expect(
        find.text(es.libraryFilterInboxLabel.toUpperCase()),
        findsOneWidget,
      );
      for (final label in [
        es.libraryFilterInboxPending,
        es.libraryFilterInboxTriaged,
        es.libraryFilterInboxDiscarded,
      ]) {
        expect(inboxChip(label), findsOneWidget);
      }
    });

    testWidgets('elegir «Triado» muestra solo lo triado y cuenta en la '
        'insignia', (tester) async {
      await seedSource('Pendiente');
      await seedSource('Ya triada', ItemState.triaged);
      await seedSource('Descartada', ItemState.discarded);
      await pumpLibrary(tester);

      await openFilters(tester);
      await tapInboxChip(tester, es.libraryFilterInboxTriaged);
      await closeFilters(tester);

      expect(find.text('Ya triada'), findsOneWidget);
      expect(find.text('Pendiente'), findsNothing);
      expect(find.text('Descartada'), findsNothing);
      final badge = tester.widget<Badge>(filtersBadge());
      expect((badge.label! as Text).data, '1');
      expect(
        harness.container.read(libraryQueryNotifierProvider).inboxStatuses,
        {InboxStatus.triaged},
      );
    });

    testWidgets('«Limpiar filtros» la suelta', (tester) async {
      await seedSource('Pendiente');
      await seedSource('Descartada', ItemState.discarded);
      await pumpLibrary(tester);

      await openFilters(tester);
      await tapInboxChip(tester, es.libraryFilterInboxDiscarded);
      await tester.tap(find.text(es.libraryClearFilters).last);
      await tester.pumpAndSettle();
      await closeFilters(tester);

      expect(
        harness.container.read(libraryQueryNotifierProvider).inboxStatuses,
        isEmpty,
      );
      expect(tester.widget<Badge>(filtersBadge()).isLabelVisible, isFalse);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Descartada'), findsOneWidget);
    });
  });
}
