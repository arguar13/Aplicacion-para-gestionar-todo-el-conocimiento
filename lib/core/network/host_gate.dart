import 'dart:async';

import 'package:sinapsis/core/util/clock.dart';

/// De a un pedido por servidor (F30).
///
/// Bajar todo lo de una página —sus fotos, sus PDF, sus audios— son decenas
/// de pedidos, casi todos al mismo servidor. Pedirlos todos juntos es lo que
/// hace que un sitio chico conteste 429 («demasiados pedidos») o corte la
/// conexión, y lo que no corresponde hacerle a quien publica: por eso a cada
/// servidor se le pide de a uno, con [gap] de respiro entre uno y otro, y
/// si pide esperar —un 429 o un 503 con `Retry-After`— se lo espera
/// ([pause]). A servidores distintos, en cambio, se les puede pedir a la vez.
///
/// Salió de la carga de la biblioteca de ejemplo (F29), que ya bajaba así.
class HostGate {
  HostGate({this.gap = const Duration(seconds: 1), Clock clock = DateTime.now})
    : _clock = clock;

  /// Cuánto se espera, después de un pedido, antes del siguiente al mismo
  /// servidor.
  final Duration gap;

  final Clock _clock;

  /// El último pedido encolado para cada servidor: el siguiente espera a que
  /// termine.
  final _tails = <String, Future<void>>{};

  /// Desde cuándo se le puede volver a pedir a cada servidor: el fin del
  /// último pedido más [gap], o lo que el servidor pidió esperar.
  final _readyAt = <String, DateTime>{};

  /// Corre [run] cuando [host] quede libre y haya pasado su espera. La espera
  /// la hace quien llega, no quien termina: así no queda ningún temporizador
  /// vivo cuando nadie más espera ese servidor.
  Future<T> run<T>(String host, Future<T> Function() run) async {
    final key = host.toLowerCase();
    final previous = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[key] = tail;
    try {
      await previous;
      final readyAt = _readyAt[key];
      if (readyAt != null) {
        final wait = readyAt.difference(_clock());
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      return await run();
    } finally {
      final next = _clock().add(gap);
      final current = _readyAt[key];
      if (current == null || next.isAfter(current)) _readyAt[key] = next;
      _tails.removeWhere((_, pending) => identical(pending, tail));
      done.complete();
    }
  }

  /// [host] pidió que se espere [wait] antes de volver a pedirle algo: el
  /// próximo pedido a ese servidor —de quien sea— espera hasta entonces.
  void pause(String host, Duration wait) {
    final key = host.toLowerCase();
    final until = _clock().add(wait);
    final current = _readyAt[key];
    if (current == null || until.isAfter(current)) _readyAt[key] = until;
  }
}

/// Cuánto pide esperar un `Retry-After` —segundos, o una fecha HTTP—, o
/// `null` si no dice nada que se entienda.
///
/// Se acota a [max]: un servidor que pide volver en un día no puede dejar la
/// descarga colgada un día; quien llama decide qué hacer pasado el tope.
Duration? parseRetryAfter(
  String? header, {
  required DateTime now,
  Duration max = const Duration(minutes: 5),
}) {
  final value = header?.trim();
  if (value == null || value.isEmpty) return null;
  final seconds = int.tryParse(value);
  Duration? wait;
  if (seconds != null) {
    if (seconds < 0) return null;
    wait = Duration(seconds: seconds);
  } else {
    final DateTime date;
    try {
      date = HttpDate.parse(value);
    } on FormatException {
      return null;
    }
    wait = date.difference(now.toUtc());
    if (wait.isNegative) wait = Duration.zero;
  }
  return wait > max ? max : wait;
}

/// Las fechas de HTTP (RFC 7231, `IMF-fixdate`), sin depender de `dart:io`:
/// esto también corre en la web.
abstract final class HttpDate {
  static const _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// "Sun, 06 Nov 1994 08:49:37 GMT".
  static DateTime parse(String value) {
    final match = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    final month = match == null ? null : _months[match[2]];
    if (match == null || month == null) {
      throw FormatException('No es una fecha HTTP', value);
    }
    return DateTime.utc(
      int.parse(match[3]!),
      month,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }
}
