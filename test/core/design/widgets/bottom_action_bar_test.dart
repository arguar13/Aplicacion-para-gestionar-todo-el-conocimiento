import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/bottom_action_bar.dart';

/// La barra con el botón de una pantalla (F46, paso 5g): queda a la vista
/// arriba de lo que tape el pie —el reproductor de lectura, que llega como
/// el teclado—, y respeta el borde seguro.
void main() {
  const screen = Size(400, 800);
  final button = find.text('Elegir temas');

  Future<void> pump(WidgetTester tester, MediaQueryData Function(Size) media) {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: media(MediaQuery.sizeOf(context)),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: BottomActionBar(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () {},
                  child: const Text('Elegir temas'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('con el borde seguro de abajo, el botón va encima de él', (
    tester,
  ) async {
    await pump(
      tester,
      (size) => MediaQueryData(
        size: size,
        padding: const EdgeInsets.only(bottom: 24),
        viewPadding: const EdgeInsets.only(bottom: 24),
      ),
    );

    final rect = tester.getRect(find.byType(FilledButton));
    expect(rect.bottom, screen.height - 24 - 16);
    expect(button, findsOneWidget);
  });

  testWidgets('con algo que tapa el pie —el reproductor, o el teclado—, el '
      'botón queda arriba de eso, sin sumar el borde seguro que quedó debajo', (
    tester,
  ) async {
    await pump(
      tester,
      (size) => MediaQueryData(
        size: size,
        viewPadding: const EdgeInsets.only(bottom: 24),
        viewInsets: const EdgeInsets.only(bottom: 150),
      ),
    );

    final rect = tester.getRect(find.byType(FilledButton));
    expect(rect.bottom, screen.height - 150 - 16);
  });
}
