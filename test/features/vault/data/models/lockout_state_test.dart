import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/vault/data/models/lockout_state.dart';
import 'package:sinapsis/features/vault/domain/entities/pin_policy.dart';

void main() {
  final now = DateTime(2026, 9, 11, 10);

  group('estado inicial', () {
    test('empieza sin fallos, sin tandas y sin espera', () {
      const state = LockoutState.initial;

      expect(state.failedAttempts, 0);
      expect(state.completedRounds, 0);
      expect(state.lockedUntil, isNull);
      expect(state.isLockedAt(now), isFalse);
      expect(state.remainingAttempts, PinPolicy.maxAttemptsBeforeLockout);
    });
  });

  group('afterFailedAttempt', () {
    test('mientras queden intentos, solo sube el contador', () {
      final state = LockoutState.initial.afterFailedAttempt(now);

      expect(state.failedAttempts, 1);
      expect(state.lockedUntil, isNull);
      expect(state.isLockedAt(now), isFalse);
    });

    test('al llegar al límite, empieza la espera', () {
      var state = LockoutState.initial;
      for (var i = 0; i < PinPolicy.maxAttemptsBeforeLockout; i++) {
        state = state.afterFailedAttempt(now);
      }

      expect(state.isLockedAt(now), isTrue);
      expect(state.lockedUntil, now.add(PinPolicy.lockoutDurations.first));
      // Y la tanda queda cerrada, con el contador limpio para la siguiente.
      expect(state.completedRounds, 1);
      expect(state.failedAttempts, 0);
    });

    test('cada tanda impone una espera más larga', () {
      var state = LockoutState.initial;
      final durations = <Duration>[];
      var clock = now;

      for (var round = 0; round < PinPolicy.lockoutDurations.length; round++) {
        for (var i = 0; i < PinPolicy.maxAttemptsBeforeLockout; i++) {
          state = state.afterFailedAttempt(clock);
        }
        durations.add(state.lockedUntil!.difference(clock));
        clock = state.lockedUntil!.add(const Duration(seconds: 1));
      }

      expect(durations, PinPolicy.lockoutDurations);
    });

    test('pasada la última tanda, la espera se estanca en la más larga en '
        'vez de crecer sin fin', () {
      // Bloquear un dispositivo durante días no protege más de lo que ya
      // protege una hora, y sí deja afuera a su dueño.
      final veryLate = PinPolicy.lockoutFor(99);

      expect(veryLate, PinPolicy.lockoutDurations.last);
    });
  });

  group('isLockedAt', () {
    test('es true mientras no se llegue al instante de desbloqueo', () {
      final state = LockoutState(
        lockedUntil: now.add(const Duration(minutes: 5)),
      );

      expect(state.isLockedAt(now), isTrue);
      expect(state.isLockedAt(now.add(const Duration(minutes: 4))), isTrue);
    });

    test('deja de serlo justo al llegar al instante de desbloqueo', () {
      final until = now.add(const Duration(minutes: 5));
      final state = LockoutState(lockedUntil: until);

      expect(state.isLockedAt(until), isFalse);
      expect(state.isLockedAt(until.add(const Duration(seconds: 1))), isFalse);
    });
  });

  group('serialización', () {
    test('sobrevive una ida y vuelta a JSON: el contador tiene que persistir '
        'entre arranques de la app', () {
      final original = LockoutState(
        failedAttempts: 3,
        completedRounds: 2,
        lockedUntil: now,
      );

      final restored = LockoutState.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.failedAttempts, original.failedAttempts);
      expect(restored.completedRounds, original.completedRounds);
      expect(restored.lockedUntil, original.lockedUntil);
    });

    test('un estado sin espera vigente también va y vuelve', () {
      final restored = LockoutState.fromJson(
        jsonDecode(jsonEncode(LockoutState.initial.toJson()))
            as Map<String, dynamic>,
      );

      expect(restored.lockedUntil, isNull);
      expect(restored.failedAttempts, 0);
    });
  });
}
