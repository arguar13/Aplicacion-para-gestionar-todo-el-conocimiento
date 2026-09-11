import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

void main() {
  final en = AppLocalizationsEn();
  final es = AppLocalizationsEs();

  const allFailures = <Failure>[
    Failure.network(message: 'mensaje interno de red'),
    Failure.unauthorized(message: 'mensaje interno de sesión'),
    Failure.server(message: 'mensaje interno de servidor'),
    Failure.validation(message: 'mensaje interno de validación'),
    Failure.cache(message: 'mensaje interno de almacenamiento'),
    Failure.unexpected(message: 'mensaje interno inesperado'),
  ];

  test('cada tipo de Failure tiene su propio mensaje traducido', () {
    final messages = allFailures.map((f) => f.localizedMessage(es)).toList();

    expect(messages.toSet(), hasLength(allFailures.length));
    for (final message in messages) {
      expect(message, isNotEmpty);
    }
  });

  test('el mensaje interno del Failure NUNCA llega al usuario', () {
    // Es la razón de ser de este helper: esos textos están escritos en
    // español dentro de las capas `data` y `domain`, y las versiones
    // anteriores los mostraban tal cual. Con la app en inglés, un error de
    // red salía en español.
    for (final failure in allFailures) {
      final message = failure.localizedMessage(en);
      expect(message, isNot(contains('mensaje interno')));
    }
  });

  test(
    'el idioma sale del AppLocalizations recibido, no de un estado global',
    () {
      const failure = Failure.network(message: 'x');

      expect(failure.localizedMessage(en), isNot(failure.localizedMessage(es)));
    },
  );
}
