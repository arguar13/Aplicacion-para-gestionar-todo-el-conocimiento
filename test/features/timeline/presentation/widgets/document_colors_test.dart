import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/timeline/presentation/widgets/document_colors.dart';

import '../../timeline_fixtures.dart';

/// Un color por documento en la línea de tiempo (F40): el mismo siempre, que se
/// lea en cualquier tema.
void main() {
  /// Todos los temas de la app: el claro, el oscuro y los seis con nombre.
  final themes = <String, ThemeData>{
    'claro': AppThemeChoice.light.theme,
    'oscuro': AppThemeChoice.dark.darkTheme,
    for (final choice in AppThemeChoice.values)
      if (choice.palette != null) choice.name: choice.theme,
  };

  /// Un identificador por cada uno de los 24 lugares de la paleta.
  List<String> idsForEverySlot() {
    final bySlot = <int, String>{};
    for (var i = 0; bySlot.length < DocumentColors.paletteSize; i++) {
      bySlot.putIfAbsent(DocumentColors.slotOf('doc-$i'), () => 'doc-$i');
    }
    return bySlot.values.toList();
  }

  group('el color de un documento es siempre el mismo', () {
    test('no cambia de una instancia a otra, ni por lo que se pidió antes', () {
      final a = DocumentColors(AppThemeChoice.light.theme);
      final b = DocumentColors(AppThemeChoice.light.theme);

      // `b` pide otros documentos antes: el orden y la cantidad no importan.
      for (final id in ['x', 'y', 'z', 'w']) {
        b.of(id);
      }

      expect(a.of('darwin'), b.of('darwin'));
      expect(a.of('roma'), b.of('roma'));
    });

    test('se guarda: pedir dos veces da el mismo color', () {
      final colors = DocumentColors(AppThemeChoice.light.theme);

      expect(identical(colors.of('darwin'), colors.of('darwin')), isTrue);
    });

    test('sale solo del identificador: filtrar no lo mueve', () {
      // Lo único que decide el lugar es el identificador.
      expect(DocumentColors.slotOf('darwin'), DocumentColors.slotOf('darwin'));
      expect(DocumentColors.slotOf('darwin'), inInclusiveRange(0, 23));
    });

    test('los lugares se reparten parejo entre muchos documentos', () {
      final counts = List.filled(DocumentColors.paletteSize, 0);
      for (var i = 0; i < 4800; i++) {
        counts[DocumentColors.slotOf('item-$i')]++;
      }

      // Con 4800 documentos, 200 por lugar en promedio.
      for (final count in counts) {
        expect(count, inInclusiveRange(120, 280));
      }
    });
  });

  group('la paleta', () {
    test('tiene veinticuatro colores y todos se distinguen entre sí', () {
      for (final MapEntry(key: name, value: theme) in themes.entries) {
        final colors = DocumentColors(theme);
        final all = {for (final id in idsForEverySlot()) colors.of(id)};

        expect(all, hasLength(DocumentColors.paletteSize), reason: name);
      }
    });

    test('contrasta con el fondo en cada tema: 3:1 como mínimo', () {
      for (final MapEntry(key: name, value: theme) in themes.entries) {
        final colors = DocumentColors(theme);
        final grounds = [
          theme.scaffoldBackgroundColor,
          theme.colorScheme.surface,
        ];

        for (final id in idsForEverySlot()) {
          for (final ground in grounds) {
            expect(
              documentColorContrast(colors.of(id), ground),
              greaterThanOrEqualTo(kDocumentColorMinContrast),
              reason: '$name: $id sobre $ground',
            );
          }
        }
      }
    });

    test('en un tema oscuro los tonos son claros, y en uno claro, oscuros', () {
      final light = DocumentColors(AppThemeChoice.light.theme);
      final dark = DocumentColors(AppThemeChoice.dark.darkTheme);

      for (final id in idsForEverySlot()) {
        expect(
          dark.of(id).computeLuminance(),
          greaterThan(light.of(id).computeLuminance()),
          reason: id,
        );
      }
    });

    test('sepia, con su papel crema, también contrasta', () {
      final sepia = AppThemeChoice.sepia.theme;
      final colors = DocumentColors(sepia);

      for (final id in idsForEverySlot()) {
        expect(
          documentColorContrast(colors.of(id), sepia.scaffoldBackgroundColor),
          greaterThanOrEqualTo(kDocumentColorMinContrast),
        );
      }
    });

    test('el mismo documento tiene otro tono en cada tema, no el mismo color '
        'para todos', () {
      final light = DocumentColors(AppThemeChoice.light.theme).of('darwin');
      final dark = DocumentColors(AppThemeChoice.dark.darkTheme).of('darwin');

      expect(light, isNot(dark));
    });

    test('documentos cualquiera casi nunca caen en el mismo lugar: de a '
        'diez, la mayoría se distingue', () {
      final colors = DocumentColors(AppThemeChoice.light.theme);
      final ten = {for (var i = 0; i < 10; i++) colors.of('libro-$i')};

      expect(ten.length, greaterThanOrEqualTo(7));
    });
  });

  group('contra qué fondos contrasta', () {
    test('también contra una superficie que no es el fondo de la pantalla', () {
      // Un fondo blanco y una superficie gris media: lo que se ve bien sobre
      // el blanco se pierde sobre el gris.
      final theme = ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(surface: Color(0xFF808080)),
      );
      final colors = DocumentColors(theme);

      for (final id in idsForEverySlot()) {
        expect(
          documentColorContrast(colors.of(id), const Color(0xFF808080)),
          greaterThanOrEqualTo(kDocumentColorMinContrast),
          reason: id,
        );
        expect(
          documentColorContrast(colors.of(id), Colors.white),
          greaterThanOrEqualTo(kDocumentColorMinContrast),
          reason: id,
        );
      }
    });
  });

  group('cuándo se pinta por documento', () {
    test('sin hechos, o de un solo documento, no', () {
      expect(showsSeveralDocuments(const []), isFalse);
      expect(
        showsSeveralDocuments([
          eventAt('a', dateOf(1)),
          eventAt('a', dateOf(2)),
          eventAt('a', dateOf(3)),
        ]),
        isFalse,
      );
    });

    test('con dos documentos, sí', () {
      expect(
        showsSeveralDocuments([
          eventAt('a', dateOf(1)),
          eventAt('b', dateOf(2)),
        ]),
        isTrue,
      );
    });

    test('lo dice apenas ve el segundo: no recorre diez mil hechos de dos '
        'documentos', () {
      var visited = 0;
      Iterable<int> endless() sync* {
        for (var i = 0; i < 100000; i++) {
          visited++;
          yield i;
        }
      }

      final events = endless().map(
        (i) => eventAt(i < 2 ? 'a' : 'b', dateOf(1 + i % 2000)),
      );

      expect(showsSeveralDocuments(events), isTrue);
      expect(visited, 3);
    });

    test('dos hechos del mismo documento cuentan como uno', () {
      expect(
        showsSeveralDocuments([
          eventAt('a', dateOf(1)),
          eventAt('a', dateOf(1000)),
        ]),
        isFalse,
      );
    });
  });

  group('no cambia entre versiones', () {
    test('el lugar de un documento en la paleta está fijo', () {
      // Si esto cambia, todos los documentos cambian de color de un día para
      // el otro: no es un detalle interno.
      expect(DocumentColors.slotOf('darwin'), 2);
      expect(DocumentColors.slotOf('roma'), 16);
      expect(DocumentColors.slotOf('beagle'), 23);
      expect(DocumentColors.slotOf('a'), 4);
      expect(
        DocumentColors.slotOf(''),
        0x811c9dc5 % DocumentColors.paletteSize,
      );
    });
  });
}
