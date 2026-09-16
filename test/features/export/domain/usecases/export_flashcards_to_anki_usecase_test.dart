// El doble lanza lo que el test le dé, igual que `FakeFileSaver`.
// ignore_for_file: only_throw_errors

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/core/usecase/usecase.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/flashcards/domain/repositories/flashcard_repository.dart';

import '../../../../support/fake_file_saver.dart';

class _MockFlashcardRepository extends Mock implements FlashcardRepository {}

/// Devuelve bytes fijos en vez de armar un `.apkg` de verdad: lo que prueba
/// este archivo es que el caso de uso encadena bien el repositorio, el
/// armador y el guardado, no el formato del paquete —eso ya lo cubre
/// `anki_package_builder_test.dart`.
class _FakeAnkiDeckBuilder implements AnkiDeckBuilder {
  /// Se activa a mitad de una prueba, después de armar el resto del
  /// escenario — igual que `FakeFileSaver.error`.
  Object? error;
  List<Flashcard>? receivedCards;

  @override
  Future<Uint8List> build(List<Flashcard> cards) async {
    if (error != null) throw error!;
    receivedCards = cards;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  late _MockFlashcardRepository repository;
  late _FakeAnkiDeckBuilder builder;
  late FakeFileSaver saver;

  setUpAll(() {
    registerFallbackValue(
      Flashcard(
        id: 'fallback',
        itemId: 'fallback',
        front: 'f',
        back: 'b',
        dueAt: DateTime(2024),
        createdAt: DateTime(2024),
      ),
    );
  });

  setUp(() {
    repository = _MockFlashcardRepository();
    builder = _FakeAnkiDeckBuilder();
    saver = FakeFileSaver();
  });

  ExportFlashcardsToAnkiUseCase useCase() => ExportFlashcardsToAnkiUseCase(
    flashcards: repository,
    builder: builder,
    saver: saver,
  );

  Flashcard sampleCard() => Flashcard(
    id: 'c1',
    itemId: 'item-1',
    front: 'Pregunta',
    back: 'Respuesta',
    dueAt: DateTime(2024),
    createdAt: DateTime(2024),
  );

  test('arma el mazo con todas las tarjetas y lo guarda', () async {
    final cards = [sampleCard()];
    when(() => repository.getAll()).thenAnswer((_) async => right(cards));

    final result = await useCase()(const NoParams());

    expect(result.isRight(), isTrue);
    expect(builder.receivedCards, cards);
    expect(saver.savedFileName, 'sinapsis.apkg');
    expect(saver.savedBytes, isNotNull);
  });

  test('si el repositorio falla, no llega a armar nada', () async {
    when(
      () => repository.getAll(),
    ).thenAnswer((_) async => left(const Failure.unexpected(message: 'x')));

    final result = await useCase()(const NoParams());

    expect(result.isLeft(), isTrue);
    expect(builder.receivedCards, isNull);
    expect(saver.savedFileName, isNull);
  });

  test('si armar el paquete falla, es un fallo de exportación', () async {
    when(() => repository.getAll()).thenAnswer((_) async => right([]));
    builder.error = StateError('no se pudo armar el .apkg');

    final result = await useCase()(const NoParams());

    expect(result.isLeft(), isTrue);
    expect(result.getLeft().toNullable(), isA<ExportFailedFailure>());
  });
}
