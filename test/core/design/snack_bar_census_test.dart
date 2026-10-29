import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de los avisos de abajo (F43, M1): todo aviso con un botón, con
/// un tiempo propio o que se queda es un `AppSnackBar`, que se sabe cerrar
/// con su ✕. Un `SnackBar` común queda para las confirmaciones cortas
/// —«Copiado», «Guardado»—, que se van solas a los cuatro segundos.
///
/// Antes había veintinueve avisos con botón y ninguno se podía cerrar: con
/// botón, un aviso se queda hasta que lo cierren, y la única forma era tocar
/// el botón, que hace otra cosa. Esta prueba es lo que impide que vuelva a
/// pasar con el aviso que se agregue mañana.
///
/// Es una comprobación de texto, no de tipos, como el censo de escrituras: no
/// ve un aviso armado a propósito para esconderse; sí el que se escribe sin
/// pensar, que es el que ocurre.
void main() {
  test('el detector ve un botón, un tiempo propio y uno que se queda', () {
    expect(
      plainSnackBarsThatNeedClose('''
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.moved),
            action: SnackBarAction(label: l10n.undo, onPressed: undo),
          ),
        );'''),
      hasLength(1),
    );
    expect(
      plainSnackBarsThatNeedClose(
        'messenger.showSnackBar(const SnackBar(content: Text("x"), '
        'duration: Duration(seconds: 10)));',
      ),
      hasLength(1),
    );
    expect(
      plainSnackBarsThatNeedClose(
        'showSnackBar(SnackBar(content: Text(f(a, b)), persist: true));',
      ),
      hasLength(1),
    );
  });

  test('y no confunde una confirmación corta, un AppSnackBar ni un '
      'comentario', () {
    expect(
      plainSnackBarsThatNeedClose('''
        messenger.showSnackBar(SnackBar(content: Text(l10n.copied)));
        messenger.showSnackBar(
          SnackBar(content: Text(describe(x, action: y))),
        );
        messenger.showSnackBar(
          AppSnackBar(content: Text(l10n.moved), action: undoAction),
        );
        // SnackBar(content: Text('x'), action: a)
        /// Un `SnackBar(action: …)` se queda.
        '''),
      isEmpty,
    );
  });

  test('ningún aviso de la app con botón, largo o que se queda está sin su '
      '✕', () {
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

    final offenders = <String>[
      for (final file in files)
        for (final line in plainSnackBarsThatNeedClose(file.readAsStringSync()))
          '${file.path.replaceAll(r'\', '/')}:$line',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Estos avisos tienen un botón, un tiempo propio o se quedan, y son '
          'un SnackBar común: sin la ✕ no hay cómo cerrarlos. Usar '
          'AppSnackBar (lib/core/design/widgets/app_snack_bar.dart).',
    );
  });
}

/// Los renglones de [source] donde empieza un `SnackBar(` común —no un
/// `AppSnackBar(`— que pasa un `action:`, un `duration:` o un `persist:`
/// propios. Mira solo los argumentos de ESE constructor, no los de lo que
/// lleva adentro, y no mira los comentarios.
List<int> plainSnackBarsThatNeedClose(String source) {
  final code = _withoutComments(source);
  final found = <int>[];
  for (final match in RegExp(r'(?<![A-Za-z0-9_])SnackBar\(').allMatches(code)) {
    final arguments = _topLevelArguments(code, match.end);
    if (RegExp(r'^\s*(action|duration|persist)\s*:').hasMatch(arguments) ||
        RegExp(r',\s*(action|duration|persist)\s*:').hasMatch(arguments)) {
      found.add('\n'.allMatches(code.substring(0, match.start)).length + 1);
    }
  }
  return found;
}

/// Lo que va entre los paréntesis del constructor que abre en [start], con
/// lo que va dentro de otros paréntesis, corchetes o llaves borrado: así un
/// `action:` de una función de adentro no cuenta como suyo.
String _topLevelArguments(String code, int start) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = start; i < code.length; i++) {
    final char = code[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      if (depth == 0) break;
      depth--;
    } else if (depth == 0) {
      out.write(char);
    }
  }
  return out.toString();
}

/// [source] sin sus comentarios de renglón, con los saltos de línea en su
/// lugar para que los números de renglón sigan valiendo.
String _withoutComments(String source) =>
    source.replaceAll(RegExp(r'//[^\n]*'), '');
