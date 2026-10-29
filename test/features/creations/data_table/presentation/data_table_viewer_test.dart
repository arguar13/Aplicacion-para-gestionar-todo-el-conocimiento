import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/creations/data_table/data_table_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../presentation/repasar_harness.dart';

/// F43, paso 9: el visor de la tabla de datos —la primera columna fija, los
/// encabezados arriba, ordenar, abrir una celda larga, copiar y exportar a
/// CSV—, en la app de verdad con su router.
void main() {
  final es = AppLocalizationsEs();
  late RepasarHarness harness;
  final clipboard = <String>[];

  const longNote =
      'Moisés guía al pueblo fuera de Egipto, atraviesa el mar, recibe la Ley '
      'en el Sinaí y conduce a Israel durante cuarenta años por el desierto '
      'hasta la frontera de la tierra prometida, que no llega a pisar.';

  Map<String, Object?> json() => {
    'title': 'Personajes',
    'columns': [
      {'name': 'Personaje', 'type': 'text'},
      {'name': 'Edad', 'type': 'number'},
      {'name': 'Cuándo', 'type': 'date'},
      {'name': 'Papel', 'type': 'text'},
      {'name': 'Nota', 'type': 'text'},
    ],
    'rows': [
      ['Moisés', '120', '1446 a. C.', 'Guía', longNote],
      ['Aarón', '83', '1440 a. C.', 'Vocero', 'Hermano mayor.'],
      ['Ñahuel', '9', '30 d. C.', 'Ejemplo', ''],
      ['abigail', '1.250', '1200 a. C.', 'Otra', 'Corta.'],
    ],
  };

  setUp(() async {
    clipboard.clear();
    harness = await RepasarHarness.create(specs: [dataTableKindSpec()]);
  });

  Future<StudyCreation> ready({Map<String, Object?>? content}) async {
    await harness.processed('p-1', 'Éxodo');
    final queued = await harness.creation(
      StudyCreationKind.dataTable,
      scope: const CreationScope.document('p-1'),
      sources: const ['p-1'],
      status: CreationStatus.generating,
    );
    await harness.creations.complete(
      queued.id,
      title: 'Personajes',
      content: jsonEncode(content ?? json()),
    );
    return queued;
  }

  Future<void> open(
    WidgetTester tester,
    StudyCreation creation, {
    Size size = const Size(420, 900),
    AppThemeChoice theme = AppThemeChoice.light,
    double textScale = 1,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
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
    await harness.openRepasar(
      tester,
      size: size,
      theme: theme,
      textScale: textScale,
      location: '/creations/${creation.id}',
    );
  }

  /// La primera columna, de arriba abajo.
  List<String> firstColumn(WidgetTester tester) {
    final cells = find.descendant(
      of: find.byKey(const Key('data-table-fixed')),
      matching: find.byType(Text),
    );
    final texts = [
      for (final e in cells.evaluate())
        (e.widget as Text, tester.getTopLeft(find.byWidget(e.widget)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final t in texts) t.$1.data!];
  }

  Finder header(int column) =>
      find.byKey(ValueKey('data-table-header-$column'));

  testWidgets('las filas en el orden de la IA, cuántas hay y la primera '
      'columna fija mientras las demás se corren', (tester) async {
    final creation = await ready();
    await open(tester, creation);

    expect(firstColumn(tester), ['Moisés', 'Aarón', 'Ñahuel', 'abigail']);
    expect(find.text(es.f43TableSize(4, 5)), findsOneWidget);

    final fixedBefore = tester.getTopLeft(find.text('Moisés'));
    final papelBefore = tester.getTopLeft(find.text('Guía'));
    final headerBefore = tester.getTopLeft(find.text('Papel'));
    await tester.drag(
      find.byKey(const Key('data-table-body-scroll')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    // La fija no se mueve; las demás y su encabezado, juntos.
    expect(tester.getTopLeft(find.text('Moisés')), fixedBefore);
    final moved = papelBefore.dx - tester.getTopLeft(find.text('Guía')).dx;
    expect(moved, greaterThan(100));
    expect(
      headerBefore.dx - tester.getTopLeft(find.text('Papel')).dx,
      closeTo(moved, 0.01),
    );
  });

  testWidgets('los encabezados quedan arriba al bajar, y la fija baja con '
      'las demás', (tester) async {
    final rows = [
      for (var i = 0; i < 60; i++) ['Fila $i', '$i', '', 'x', 'y'],
    ];
    final creation = await ready(content: {...json(), 'rows': rows});
    await open(tester, creation, size: const Size(420, 700));
    final headerTop = tester.getTopLeft(find.text('Personaje')).dy;

    await tester.drag(
      find.byKey(const Key('data-table-fixed')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Personaje')).dy, headerTop);
    double offset(String key) =>
        tester.widget<ListView>(find.byKey(Key(key))).controller!.offset;
    expect(offset('data-table-fixed'), greaterThan(300));
    expect(offset('data-table-body'), offset('data-table-fixed'));
    // La celda fija y las de su fila, a la misma altura.
    final row = tester.getTopLeft(find.text('Fila 10')).dy;
    expect(tester.getTopLeft(find.text('10')).dy, closeTo(row, 0.5));
  });

  group('ordenar', () {
    testWidgets('tocar un encabezado ordena por él; otra vez, al revés', (
      tester,
    ) async {
      final creation = await ready();
      await open(tester, creation);

      await tester.tap(header(0));
      await tester.pumpAndSettle();
      // Como un diccionario: sin mayúsculas primero, la ñ después de la n.
      expect(firstColumn(tester), ['Aarón', 'abigail', 'Moisés', 'Ñahuel']);
      expect(find.byKey(const Key('data-table-sorted')), findsOneWidget);

      await tester.tap(header(0));
      await tester.pumpAndSettle();
      expect(firstColumn(tester), ['Ñahuel', 'Moisés', 'abigail', 'Aarón']);
    });

    testWidgets('los números como números y las fechas como fechas', (
      tester,
    ) async {
      final creation = await ready();
      await open(tester, creation);

      await tester.tap(header(1));
      await tester.pumpAndSettle();
      expect(firstColumn(tester), ['Ñahuel', 'Aarón', 'Moisés', 'abigail']);

      await tester.tap(header(2));
      await tester.pumpAndSettle();
      expect(firstColumn(tester), ['Moisés', 'Aarón', 'abigail', 'Ñahuel']);
    });

    testWidgets('la hoja de ordenar: el ✓ en lo elegido, hacia dónde y el '
        'orden original', (tester) async {
      final creation = await ready();
      await open(tester, creation);

      await tester.tap(find.byKey(const Key('data-table-sort')));
      await tester.pumpAndSettle();
      Finder check(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(check('data-table-sort-original'), findsOneWidget);

      await tester.tap(find.byKey(const Key('data-table-sort-column-1')));
      await tester.pumpAndSettle();
      expect(check('data-table-sort-column-1'), findsOneWidget);
      expect(check('data-table-sort-original'), findsNothing);
      await tester.tap(find.byKey(const Key('data-table-direction-desc')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(firstColumn(tester), ['abigail', 'Moisés', 'Aarón', 'Ñahuel']);

      // La ✕ de la ficha vuelve al orden de la IA.
      await tester.tap(find.byTooltip(es.f43TableSortOriginal));
      await tester.pumpAndSettle();
      expect(firstColumn(tester), ['Moisés', 'Aarón', 'Ñahuel', 'abigail']);
    });
  });

  testWidgets('tocar una celda que no entra la abre entera; una corta, no', (
    tester,
  ) async {
    final creation = await ready();
    await open(tester, creation);

    await tester.tap(find.text('Hermano mayor.'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data-table-cell-sheet')), findsNothing);

    await tester.drag(
      find.byKey(const Key('data-table-body-scroll')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('data-table-cell-0-4')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('data-table-cell-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('${es.f43TableRow(1)} · Moisés'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Nota')),
      findsOneWidget,
    );
    expect(find.widgetWithText(SelectableText, longNote), findsOneWidget);

    await tester.tap(find.byKey(const Key('data-table-cell-copy')));
    await tester.pumpAndSettle();
    expect(clipboard.last, longNote);
    expect(find.text(es.f43TableCellCopied), findsOneWidget);
  });

  testWidgets('«Copiar la tabla»: TSV en el orden que se ve', (tester) async {
    final creation = await ready();
    await open(tester, creation);
    await tester.tap(header(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('data-table-copy')));
    await tester.pumpAndSettle();
    final lines = clipboard.last.split('\n');
    expect(lines.first, 'Personaje\tEdad\tCuándo\tPapel\tNota');
    expect(
      [for (final l in lines.skip(1)) l.split('\t').first],
      ['Ñahuel', 'Aarón', 'Moisés', 'abigail'],
    );
    expect(find.text(es.f43TableCopied), findsOneWidget);
  });

  testWidgets('«Exportar a CSV»: con BOM, «;» en castellano y el orden que '
      'se ve', (tester) async {
    final creation = await ready();
    await open(tester, creation);
    await tester.tap(header(1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('data-table-csv')));
    await tester.pumpAndSettle();
    final saver = harness.library.fileSaver;
    expect(saver.savedFileName, 'Personajes.csv');
    final bytes = saver.savedBytes!;
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(bytes.sublist(3));
    expect(text, startsWith('Personaje;Edad;Cuándo;Papel;Nota\r\nÑahuel;9;'));
    expect(find.text(es.f43StudioDownloaded('Personajes.csv')), findsOneWidget);
  });

  testWidgets('para el lector de pantalla: columna y valor, y cómo está '
      'ordenada', (tester) async {
    final handle = tester.ensureSemantics();
    final creation = await ready();
    await open(tester, creation);
    expect(find.bySemanticsLabel('Papel: Guía'), findsOneWidget);
    await tester.tap(header(1));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(es.f43TableSortedAsc('Edad')), findsWidgets);
    handle.dispose();
  });

  testWidgets('una tabla vacía lo dice', (tester) async {
    final creation = await ready(content: {'nada': 1});
    await open(tester, creation);
    expect(find.text(es.f43TableEmpty), findsOneWidget);
  });

  testWidgets('a 360 de ancho con la letra al doble: sin desbordes, y la '
      'fija no se come la pantalla', (tester) async {
    final creation = await ready();
    await open(tester, creation, size: const Size(360, 720), textScale: 2);
    expect(tester.takeException(), isNull);
    final fixed = tester.getRect(find.byKey(const Key('data-table-fixed')));
    expect(fixed.width, lessThanOrEqualTo(360 * 0.45));
    await tester.tap(find.byKey(const Key('data-table-sort')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final theme in AppThemeChoice.values) {
    testWidgets('en el tema ${theme.name}: las filas alternan y la letra se '
        'lee', (tester) async {
      final creation = await ready();
      await open(tester, creation, theme: theme);
      expect(tester.takeException(), isNull);
      Color fill(String text) => tester
          .widget<Container>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Container))
                .first,
          )
          .color!;
      final even = fill('Moisés');
      final odd = fill('Aarón');
      expect(even, isNot(odd));
      final color = tester.widget<Text>(find.text('Aarón')).style!.color!;
      expect(_contrast(color, odd), greaterThanOrEqualTo(4.5));
      expect(_contrast(color, even), greaterThanOrEqualTo(4.5));
    });
  }
}

double _contrast(Color a, Color b) {
  final la = a.withValues(alpha: 1).computeLuminance();
  final lb = b.withValues(alpha: 1).computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
