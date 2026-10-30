import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de los avisos de abajo (F45, paso 1): todos son el aviso común,
/// `AppSnackBar`, y se muestran con `showAppSnackBar`. Así todos tienen su ✕,
/// sus dos botones bien puestos y le avisan al lector flotante que se corra.
///
/// Antes (F43, M1) solo se exigía el aviso común a los que tenían un botón o
/// duraban más; los cortos eran un `SnackBar` de Material, sin ✕. Ahora la ✕
/// va en todos (decisión A), y un aviso que no pasa por el común tapa al
/// lector o queda tapado por él.
///
/// Fuera del aviso común no puede haber:
/// - un `showSnackBar(`: `showAppSnackBar` solo acepta un `AppSnackBar`, así
///   que un aviso armado a mano no compila por ahí;
/// - un `SnackBar(` armado a mano, ni su `SnackBar.new`;
/// - otro aviso que herede de `SnackBar`.
///
/// Es una comprobación de texto, no de tipos, como el censo de escrituras: no
/// ve un aviso armado a propósito para esconderse; sí el que se escribe sin
/// pensar, que es el que ocurre.
void main() {
  const common = 'lib/core/design/widgets/app_snack_bar.dart';

  test('el detector ve un aviso mostrado a mano, armado a mano o heredado', () {
    for (final source in [
      'ScaffoldMessenger.of(context).showSnackBar(x);',
      'messenger\n  ..hideCurrentSnackBar()\n  ..showSnackBar(x);',
      'messenger?.showSnackBar(x);',
      'final bar = SnackBar(content: Text(l10n.copied));',
      'return const SnackBar(content: Text("x"));',
      'material.SnackBar(content: child)',
      'final make = SnackBar.new;',
      'show(SnackBar (content: child));',
      'class QuietBar extends SnackBar {',
    ]) {
      expect(
        snackBarsOutsideTheCommonOne(source),
        hasLength(1),
        reason: source,
      );
    }
  });

  test('y no confunde el aviso común, sus piezas ni un comentario', () {
    expect(
      snackBarsOutsideTheCommonOne('''
        messenger.showAppSnackBar(AppSnackBar(content: Text(l10n.copied)));
        messenger
          ..hideCurrentSnackBar()
          ..showAppSnackBar(
            AppSnackBar(
              content: Text(l10n.moved),
              action: SnackBarAction(label: l10n.undo, onPressed: undo),
            ),
          );
        final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> c;
        context.findAncestorWidgetOfExactType<SnackBar>();
        final theme = SnackBarThemeData(behavior: SnackBarBehavior.floating);
        // messenger.showSnackBar(SnackBar(content: Text('x')));
        /// Un `SnackBar(action: …)` se queda.
        /* SnackBar(content: x) */
        '''),
      isEmpty,
    );
  });

  test('el detector da el renglón de cada uno', () {
    expect(
      snackBarsOutsideTheCommonOne(
        'a();\n// SnackBar(\nmessenger.showSnackBar(\n  SnackBar(content: x),\n);',
      ),
      [3, 4],
    );
  });

  test('ningún aviso de la app queda fuera del aviso común', () {
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
      shown += RegExp(r'\bshowAppSnackBar\(').allMatches(source).length;
      for (final line in snackBarsOutsideTheCommonOne(source)) {
        offenders.add('$path:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Estos avisos no pasan por el aviso común: sin él no tienen su ✕, '
          'sus botones quedan donde Material los ponga y el lector flotante '
          'los tapa. Usar `showAppSnackBar(AppSnackBar(...))` '
          '($common).',
    );
    // Y los avisos están: la app tiene más de ciento ochenta.
    expect(shown, greaterThan(150));
  });
}

/// Los renglones de [source] con un aviso de abajo que no es el común: un
/// `showSnackBar(`, un `SnackBar(` o `SnackBar.new` armado a mano —no un
/// `AppSnackBar(`— o una clase que hereda de `SnackBar`. No mira los
/// comentarios.
List<int> snackBarsOutsideTheCommonOne(String source) {
  final code = _withoutComments(source);
  final found = <int>{};
  for (final pattern in [
    RegExp(r'(?<![A-Za-z0-9_])showSnackBar\s*\('),
    RegExp(r'(?<![A-Za-z0-9_])SnackBar\s*(\(|\.new\b)'),
    RegExp(r'\bextends\s+SnackBar\b'),
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
