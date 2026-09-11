import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/placeholder_screen.dart';

void main() {
  testWidgets('dibuja el título recibido dentro de un Scaffold', (
    tester,
  ) async {
    // Arrange
    await tester.pumpWidget(
      const MaterialApp(home: PlaceholderScreen(title: 'Ruta no encontrada')),
    );

    // Act: ninguna interacción — se verifica el render.

    // Assert
    expect(find.text('Ruta no encontrada'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
