import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/vault/domain/entities/unlock_result.dart';
import 'package:sinapsis/features/vault/domain/repositories/vault_repository.dart';
import 'package:sinapsis/features/vault/domain/usecases/check_vault_exists_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/create_vault_usecase.dart';
import 'package:sinapsis/features/vault/domain/usecases/unlock_vault_usecase.dart';

class MockVaultRepository extends Mock implements VaultRepository {}

void main() {
  late MockVaultRepository repository;

  const tPin = '246810';

  setUp(() {
    repository = MockVaultRepository();
  });

  group('CheckVaultExistsUseCase', () {
    test('delega en el repositorio', () async {
      when(repository.exists).thenAnswer((_) async => right(true));

      final result = await CheckVaultExistsUseCase(repository)(
        const NoParams(),
      );

      expect(result, right<Failure, bool>(true));
      verify(repository.exists).called(1);
    });
  });

  group('CreateVaultUseCase', () {
    test(
      'crea la bóveda cuando las dos claves coinciden y son válidas',
      () async {
        when(
          () => repository.create(pin: any(named: 'pin')),
        ).thenAnswer((_) async => right(unit));

        final result = await CreateVaultUseCase(repository)(
          const CreateVaultParams(pin: tPin, confirmation: tPin),
        );

        expect(result.isRight(), isTrue);
        verify(() => repository.create(pin: tPin)).called(1);
      },
    );

    test(
      'si las claves no coinciden, ni siquiera llama al repositorio',
      () async {
        final result = await CreateVaultUseCase(repository)(
          const CreateVaultParams(pin: tPin, confirmation: 'otra'),
        );

        expect(result.isLeft(), isTrue);
        verifyNever(() => repository.create(pin: any(named: 'pin')));
      },
    );

    test('si la clave es demasiado corta, tampoco', () async {
      final result = await CreateVaultUseCase(repository)(
        const CreateVaultParams(pin: '123', confirmation: '123'),
      );

      expect(result.isLeft(), isTrue);
      verifyNever(() => repository.create(pin: any(named: 'pin')));
    });

    test('la regla vive en el caso de uso, no solo en la pantalla: llamarlo '
        'directamente topa con la misma exigencia', () async {
      // Es la razón de que esta validación esté duplicada respecto del
      // formulario. La pantalla señala el campo exacto mientras se escribe;
      // esto hace que la regla valga aunque la llamada venga de otro lado.
      final result = await CreateVaultUseCase(repository)(
        const CreateVaultParams(pin: '1', confirmation: '1'),
      );

      result.getLeft().fold(
        () => fail('se esperaba un Failure'),
        (f) => expect(f, isA<ValidationFailure>()),
      );
    });
  });

  group('UnlockVaultUseCase', () {
    test('delega en el repositorio y devuelve su resultado', () async {
      when(
        () => repository.unlock(pin: any(named: 'pin')),
      ).thenAnswer((_) async => right(const UnlockResult.granted()));

      final result = await UnlockVaultUseCase(repository)(
        const UnlockVaultParams(pin: tPin),
      );

      expect(result.getRight().toNullable(), const UnlockResult.granted());
    });

    test('NO valida la longitud: una clave corta tiene que llegar al '
        'repositorio y gastar un intento como cualquier otra', () async {
      when(() => repository.unlock(pin: any(named: 'pin'))).thenAnswer(
        (_) async => right(const UnlockResult.rejected(remainingAttempts: 4)),
      );

      await UnlockVaultUseCase(repository)(const UnlockVaultParams(pin: '1'));

      verify(() => repository.unlock(pin: '1')).called(1);
    });
  });

  group('igualdad por valor de los params', () {
    test('dos CreateVaultParams con los mismos datos son iguales', () {
      expect(
        const CreateVaultParams(pin: tPin, confirmation: tPin),
        const CreateVaultParams(pin: tPin, confirmation: tPin),
      );
    });

    test('dos UnlockVaultParams con el mismo PIN son iguales', () {
      expect(
        const UnlockVaultParams(pin: tPin),
        const UnlockVaultParams(pin: tPin),
      );
      expect(
        const UnlockVaultParams(pin: tPin).hashCode,
        const UnlockVaultParams(pin: tPin).hashCode,
      );
    });

    test('con datos distintos, no', () {
      expect(
        const CreateVaultParams(pin: tPin, confirmation: tPin),
        isNot(const CreateVaultParams(pin: tPin, confirmation: 'otra')),
      );
    });
  });
}
