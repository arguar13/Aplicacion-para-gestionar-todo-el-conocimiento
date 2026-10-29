import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';

/// El aviso de abajo que sabe solo si lleva su ✕ (F43, M1).
void main() {
  SnackBarAction undo() => SnackBarAction(label: 'Deshacer', onPressed: () {});

  group('cuándo lleva la ✕', () {
    test('con un botón, que además lo deja quieto hasta que lo cierren', () {
      final bar = AppSnackBar(content: const Text('Movido'), action: undo());
      expect(bar.showCloseIcon, isTrue);
      expect(bar.persist, isTrue);
    });

    test('largo: más de seis segundos', () {
      expect(
        AppSnackBar(
          content: const Text('x'),
          duration: const Duration(seconds: 7),
        ).showCloseIcon,
        isTrue,
      );
      expect(
        AppSnackBar(
          content: const Text('x'),
          duration: kSnackBarShortLimit,
        ).showCloseIcon,
        isFalse,
      );
    });

    test('el que se queda, aunque no tenga botón', () {
      expect(
        AppSnackBar(content: const Text('x'), persist: true).showCloseIcon,
        isTrue,
      );
    });

    test('una confirmación corta, no: queda como siempre', () {
      final bar = AppSnackBar(content: const Text('Copiado'));
      expect(bar.showCloseIcon, isFalse);
      expect(bar.duration, kSnackBarDefaultDuration);
      expect(bar.persist, isFalse);
    });

    test('con botón pero pedido que se vaya solo, la ✕ igual', () {
      final bar = AppSnackBar(
        content: const Text('x'),
        action: undo(),
        persist: false,
      );
      expect(bar.showCloseIcon, isTrue);
      expect(bar.persist, isFalse);
    });

    test('se puede pedir a mano, para un lado o para el otro', () {
      expect(
        AppSnackBar(
          content: const Text('x'),
          showCloseIcon: true,
        ).showCloseIcon,
        isTrue,
      );
      expect(
        AppSnackBar(
          content: const Text('x'),
          action: undo(),
          showCloseIcon: false,
        ).showCloseIcon,
        isFalse,
      );
    });
  });

  testWidgets('la ✕ cierra el aviso, con su nombre para el lector de '
      'pantalla, y el botón sigue a su lado', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                AppSnackBar(
                  content: const Text('Movido a la papelera'),
                  action: SnackBarAction(
                    label: 'Deshacer',
                    onPressed: () => undone = true,
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Deshacer'), findsOneWidget);
    // Se queda: el botón lo deja quieto.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Movido a la papelera'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Movido a la papelera'), findsNothing);
    expect(undone, isFalse);
  });
}
