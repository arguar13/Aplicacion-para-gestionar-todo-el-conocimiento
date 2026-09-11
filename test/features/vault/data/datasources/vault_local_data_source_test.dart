import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/exceptions.dart';
import 'package:sinapsis/features/vault/data/datasources/vault_local_data_source.dart';
import 'package:sinapsis/features/vault/data/models/lockout_state.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockSecureStorage storage;
  late SecureVaultLocalDataSource dataSource;

  const tCredential = r'pbkdf2-sha256$120000$c2FsdA==$a2V5';

  setUp(() {
    storage = MockSecureStorage();
    dataSource = SecureVaultLocalDataSource(storage: storage);
  });

  group('credencial', () {
    test('devuelve lo guardado', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => tCredential);

      expect(await dataSource.readCredential(), tCredential);
    });

    test('devuelve null cuando no hay bóveda', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);

      expect(await dataSource.readCredential(), isNull);
    });

    test('lo escribe bajo su propia clave', () async {
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await dataSource.writeCredential(tCredential);

      verify(
        () => storage.write(key: 'vault_pin_credential', value: tCredential),
      ).called(1);
    });

    test('un almacén que no responde se convierte en CacheException, no en '
        'una excepción de plataforma cruda', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'storage-unavailable'));

      expect(dataSource.readCredential, throwsA(isA<CacheException>()));
    });

    test('lo mismo al escribir', () async {
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenThrow(PlatformException(code: 'storage-unavailable'));

      expect(
        () => dataSource.writeCredential(tCredential),
        throwsA(isA<CacheException>()),
      );
    });
  });

  group('control de intentos', () {
    test('sin registro previo devuelve el estado inicial, no null', () async {
      // "No hay registro de fallos" y "cero fallos" son lo mismo para quien
      // llama; devolver null obligaría a cada consumidor a decidirlo.
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);

      final lockout = await dataSource.readLockout();

      expect(lockout.failedAttempts, 0);
      expect(lockout.lockedUntil, isNull);
    });

    test('restaura lo guardado', () async {
      final stored = LockoutState(
        failedAttempts: 3,
        completedRounds: 1,
        lockedUntil: DateTime(2026, 9, 11, 10),
      );
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => jsonEncode(stored.toJson()));

      final lockout = await dataSource.readLockout();

      expect(lockout.failedAttempts, 3);
      expect(lockout.completedRounds, 1);
      expect(lockout.lockedUntil, DateTime(2026, 9, 11, 10));
    });

    test('un contador ilegible se trata como "sin fallos" en vez de dejar al '
        'usuario afuera', () async {
      // Es la única concesión de este tipo en el archivo, y es deliberada:
      // el contador es auxiliar. Negarle el acceso a alguien a su propio
      // conocimiento porque se corrompió un contador sería mucho peor que
      // regalarle unos intentos.
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => 'esto no es json');

      final lockout = await dataSource.readLockout();

      expect(lockout.failedAttempts, 0);
    });

    test('el credencial, en cambio, NO recibe ese trato: si el almacén falla '
        'al leerlo, falla ruidosamente', () async {
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'boom'));

      expect(dataSource.readCredential, throwsA(isA<CacheException>()));
    });

    test('lo persiste como JSON', () async {
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      await dataSource.writeLockout(const LockoutState(failedAttempts: 2));

      final captured =
          verify(
                () => storage.write(
                  key: 'vault_lockout_state',
                  value: captureAny(named: 'value'),
                ),
              ).captured.single
              as String;

      expect(
        (jsonDecode(captured) as Map<String, dynamic>)['failedAttempts'],
        2,
      );
    });
  });
}
