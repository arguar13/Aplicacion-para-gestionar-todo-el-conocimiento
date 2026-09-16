import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/flashcard.dart';
import 'package:sinapsis/features/export/domain/services/anki_deck_builder.dart';
import 'package:sinapsis/features/export/domain/usecases/export_flashcards_to_anki_usecase.dart';
import 'package:sinapsis/features/export/presentation/providers/export_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/flashcard_providers.dart';
import 'package:sinapsis/features/flashcards/presentation/screens/review_screen.dart';

import '../../../../support/library_harness.dart';

/// Un doble en vez de `AnkiPackageBuilder` de verdad: ese ya se prueba a
/// fondo en `anki_package_builder_test.dart`, y abrir ahí una segunda
/// conexión SQLite cruda mientras corre bajo `testWidgets` se cuelga —un
/// problema del entorno de pruebas de Flutter, no de la clase en sí (un
/// `test()` liso, sin bindings de Flutter, la abre sin problema). Lo que
/// importa acá es solo que la pantalla la llame y reaccione bien.
class _FakeAnkiDeckBuilder implements AnkiDeckBuilder {
  @override
  Future<Uint8List> build(List<Flashcard> cards) async {
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<void> pumpReview(WidgetTester tester) async {
    await tester.pumpWidget(
      harness.wrap(
        ProviderScope(
          overrides: [
            exportFlashcardsToAnkiUseCaseProvider.overrideWith(
              (ref) => ExportFlashcardsToAnkiUseCase(
                flashcards: ref.watch(flashcardRepositoryProvider),
                builder: _FakeAnkiDeckBuilder(),
                saver: ref.watch(fileSaverProvider),
              ),
            ),
          ],
          child: const ReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el botón de exportar a Anki aparece en la barra superior', (
    tester,
  ) async {
    await pumpReview(tester);

    expect(find.byTooltip('Exportar mazo a Anki'), findsOneWidget);
  });

  testWidgets('tocar el botón arma el .apkg y lo pasa al selector', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.byTooltip('Exportar mazo a Anki'));
    await tester.pumpAndSettle();

    expect(harness.fileSaver.savedFileName, 'sinapsis.apkg');
    expect(harness.fileSaver.savedBytes, isNotNull);
  });

  testWidgets('si el selector de guardado falla, avisa con un mensaje', (
    tester,
  ) async {
    harness.fileSaver.error = StateError('el diálogo se cayó');
    await pumpReview(tester);

    await tester.tap(find.byTooltip('Exportar mazo a Anki'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
