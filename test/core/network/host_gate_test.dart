import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/network/host_gate.dart';

void main() {
  group('HostGate', () {
    test('al mismo servidor, de a uno; a otro, a la vez', () async {
      final gate = HostGate(gap: Duration.zero);
      final log = <String>[];
      final first = Completer<void>();

      final a1 = gate.run('upload.wikimedia.org', () async {
        log.add('a1 empieza');
        await first.future;
        log.add('a1 termina');
      });
      final a2 = gate.run('UPLOAD.wikimedia.org', () async {
        log.add('a2 empieza');
      });
      final b = gate.run('otro.org', () async => log.add('b empieza'));

      await b;
      expect(log, ['a1 empieza', 'b empieza']);
      first.complete();
      await Future.wait([a1, a2]);
      expect(log, ['a1 empieza', 'b empieza', 'a1 termina', 'a2 empieza']);
    });

    test('respeta el respiro entre pedidos al mismo servidor', () async {
      final gate = HostGate(gap: const Duration(milliseconds: 120));
      final watch = Stopwatch()..start();
      await gate.run('x.org', () async {});
      await gate.run('x.org', () async {});
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(100));
    });

    test('pause: el próximo pedido a ese servidor espera', () async {
      final gate = HostGate(gap: Duration.zero)
        ..pause('x.org', const Duration(milliseconds: 150));
      final watch = Stopwatch()..start();
      await gate.run('x.org', () async {});
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(120));

      final other = Stopwatch()..start();
      await gate.run('y.org', () async {});
      expect(other.elapsedMilliseconds, lessThan(100));
    });

    test('un fallo no traba al servidor', () async {
      final gate = HostGate(gap: Duration.zero);
      await expectLater(
        gate.run('x.org', () async => throw StateError('falla')),
        throwsStateError,
      );
      expect(await gate.run('x.org', () async => 7), 7);
    });
  });

  group('parseRetryAfter', () {
    final now = DateTime.utc(2026, 10, 4, 12);

    test('segundos', () {
      expect(parseRetryAfter('30', now: now), const Duration(seconds: 30));
      expect(parseRetryAfter(' 0 ', now: now), Duration.zero);
    });

    test('una fecha HTTP', () {
      expect(
        parseRetryAfter('Sun, 04 Oct 2026 12:01:00 GMT', now: now),
        const Duration(minutes: 1),
      );
      expect(
        parseRetryAfter('Sun, 04 Oct 2026 11:00:00 GMT', now: now),
        Duration.zero,
      );
    });

    test('lo que no se entiende es null; lo exagerado se acota', () {
      expect(parseRetryAfter(null, now: now), isNull);
      expect(parseRetryAfter('mañana', now: now), isNull);
      expect(parseRetryAfter('-3', now: now), isNull);
      expect(parseRetryAfter('86400', now: now), const Duration(minutes: 5));
    });
  });
}
