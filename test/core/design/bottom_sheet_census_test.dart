import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de los paneles de abajo (F46, paso 5j, decisión 1b): todos se
/// abren con el ayudante común, `showAppBottomSheet`, que los abre en el
/// navegador de la raíz. Así tapan la barra de pestañas y su sombreado cubre
/// la pantalla entera, y todos esquivan el teclado y la barra del sistema.
///
/// Antes cada pantalla llamaba a `showModalBottomSheet` por su cuenta, sin
/// pedir el navegador de la raíz: abierto desde una pestaña, el panel quedaba
/// arriba de la barra, que seguía sin sombrear y se podía tocar.
///
/// Fuera del ayudante no puede haber:
/// - un `showModalBottomSheet`, llamado o pasado como función;
/// - una `ModalBottomSheetRoute` armada a mano;
/// - un panel fijo de `Scaffold` (`showBottomSheet`), que no tapa nada.
///
/// Es una comprobación de texto, como el censo de los avisos: no ve un panel
/// escondido a propósito; sí el que se escribe sin pensar, que es el que
/// ocurre.
void main() {
  const common = 'lib/core/design/widgets/app_bottom_sheet.dart';

  test('el detector ve un panel abierto a mano, de cualquier forma', () {
    for (final source in [
      'showModalBottomSheet<void>(context: context, builder: build);',
      'await showModalBottomSheet(\n  context: context,\n  builder: b,\n);',
      'showModalBottomSheet<({RelationKind kind, String? note})>(',
      'final open = showModalBottomSheet;',
      'material.showModalBottomSheet<bool>(context: c, builder: b)',
      'navigator.push(ModalBottomSheetRoute<void>(builder: b));',
      'Scaffold.of(context).showBottomSheet((context) => x);',
    ]) {
      expect(
        bottomSheetsOutsideTheCommonOne(source),
        hasLength(1),
        reason: source,
      );
    }
  });

  test('y no confunde el ayudante, sus piezas ni un comentario', () {
    expect(
      bottomSheetsOutsideTheCommonOne('''
        showAppBottomSheet<void>(context: context, builder: build);
        await showAppBottomSheet<bool>(context: context, ownSurface: true,
            builder: (sheetContext) => const Sheet());
        final theme = BottomSheetThemeData(showDragHandle: true);
        find.byType(BottomSheet);
        // showModalBottomSheet(context: context, builder: b);
        /// Un `showModalBottomSheet` de antes.
        /* ModalBottomSheetRoute<void>(builder: b) */
        '''),
      isEmpty,
    );
  });

  test('el detector da el renglón de cada uno', () {
    expect(
      bottomSheetsOutsideTheCommonOne(
        'a();\n// showModalBottomSheet(\nshowModalBottomSheet<void>(\n'
        '  context: c,\n);\nfinal r = ModalBottomSheetRoute<void>(b);',
      ),
      [3, 6],
    );
  });

  test('ningún panel de la app queda fuera del ayudante', () {
    final files = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.path.endsWith('.freezed.dart'))
          entity,
    ];
    // El recorrido mira algo: sin esto, un cambio de ruta lo dejaría verde
    // sin revisar nada.
    expect(files.length, greaterThan(200));

    final offenders = <String>[];
    var shown = 0;
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith(common)) continue;
      final source = file.readAsStringSync();
      shown += RegExp(r'\bshowAppBottomSheet\b').allMatches(source).length;
      for (final line in bottomSheetsOutsideTheCommonOne(source)) {
        offenders.add('$path:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Estos paneles no pasan por el ayudante común: abiertos desde una '
          'pestaña dejan la barra sin sombrear y se puede tocar. Usar '
          '`showAppBottomSheet` ($common).',
    );
    // Y los paneles están: la app abre más de ochenta.
    expect(shown, greaterThan(80));
  });
}

/// Los renglones de [source] con un panel de abajo que no pasa por el
/// ayudante: un `showModalBottomSheet` —llamado o como función—, una
/// `ModalBottomSheetRoute` o un `showBottomSheet` de `Scaffold`. No mira los
/// comentarios.
List<int> bottomSheetsOutsideTheCommonOne(String source) {
  final code = _withoutComments(source);
  final found = <int>{};
  for (final pattern in [
    RegExp(r'(?<![A-Za-z0-9_])showModalBottomSheet\b'),
    RegExp(r'(?<![A-Za-z0-9_])ModalBottomSheetRoute\b'),
    RegExp(r'(?<![A-Za-z0-9_])showBottomSheet\s*(<|\()'),
  ]) {
    for (final match in pattern.allMatches(code)) {
      found.add('\n'.allMatches(code.substring(0, match.start)).length + 1);
    }
  }
  return found.toList()..sort();
}

/// [source] sin sus comentarios —de renglón y de bloque—, con los saltos de
/// línea en su lugar para que los números de renglón sigan valiendo.
String _withoutComments(String source) => source
    .replaceAllMapped(
      RegExp(r'/\*.*?\*/', dotAll: true),
      (match) => '\n' * '\n'.allMatches(match[0]!).length,
    )
    .replaceAll(RegExp(r'//[^\n]*'), '');
