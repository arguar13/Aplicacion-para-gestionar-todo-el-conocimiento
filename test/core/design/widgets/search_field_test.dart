import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/widgets/search_field.dart';

/// El campo de búsqueda suelta el teclado cuando ya no se escribe y no lo
/// recupera al volver (F46, paso 5i): en el emulador, de vuelta de un
/// resultado de la Biblioteca, el teclado se abría solo y tapaba la mitad de
/// la lista.
void main() {
  final field = find.byKey(const Key('busqueda'));

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

  /// Una lista con su buscador, como la Biblioteca: cada resultado abre su
  /// pantalla; el primero con un toque, y [onOpenWithoutTouch] por código,
  /// como lo abre el lector de pantalla.
  Future<void> pump(
    WidgetTester tester, {
    bool nested = false,
    void Function(BuildContext context)? onOpenWithoutTouch,
  }) async {
    Widget list(BuildContext context) => Scaffold(
      body: Column(
        children: [
          const SearchField(key: Key('busqueda')),
          ListTile(
            title: const Text('Fotosíntesis'),
            onTap: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('El detalle')),
              ),
            ),
          ),
          Builder(
            builder: (inner) => TextButton(
              onPressed: () => onOpenWithoutTouch?.call(inner),
              child: const Text('sin tocar'),
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: nested
            // Como una pestaña: la lista en el navegador de su rama, y el
            // resultado en el de la raíz, encima de todo.
            ? Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(builder: list),
              )
            : Builder(builder: list),
      ),
    );
  }

  Future<void> typeAndCloseKeyboard(WidgetTester tester) async {
    await tester.tap(field);
    await tester.enterText(field, 'Fotosintesis');
    await tester.pump();
    expect(fieldHasFocus(tester), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    // «Atrás» cierra el teclado, pero el campo sigue con el foco.
    tester.testTextInput.hide();
    await tester.pump();
    expect(fieldHasFocus(tester), isTrue);
  }

  Future<void> goBack(WidgetTester tester) async {
    Navigator.of(tester.element(find.text('El detalle'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Fotosíntesis'), findsOneWidget);
  }

  for (final nested in [false, true]) {
    final where = nested ? ', desde una pestaña' : '';

    testWidgets('tocar un resultado le saca el foco, y al volver el teclado '
        'no se abre$where', (tester) async {
      await pump(tester, nested: nested);
      await typeAndCloseKeyboard(tester);

      await tester.tap(find.text('Fotosíntesis'));
      await tester.pumpAndSettle();
      expect(find.text('El detalle'), findsOneWidget);
      await goBack(tester);

      expect(fieldHasFocus(tester), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('abierto sin tocar la pantalla —por el lector de pantalla, '
        'por código—, al volver tampoco lo recupera$where', (tester) async {
      await pump(
        tester,
        nested: nested,
        onOpenWithoutTouch: (context) =>
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('El detalle')),
              ),
            ),
      );
      await typeAndCloseKeyboard(tester);

      // Sin un toque: el foco sigue en el campo cuando se abre lo de encima.
      final button = tester.widget<TextButton>(find.byType(TextButton));
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('El detalle'), findsOneWidget);
      await goBack(tester);

      expect(fieldHasFocus(tester), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // Y se puede volver a escribir: tocarlo lo enfoca.
      await tester.tap(field);
      await tester.pump();
      expect(fieldHasFocus(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  }

  testWidgets('una hoja abierta encima tampoco se lo devuelve al '
      'cerrarse', (tester) async {
    await pump(
      tester,
      onOpenWithoutTouch: (context) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 200, child: Text('La hoja')),
      ),
    );
    await typeAndCloseKeyboard(tester);

    tester.widget<TextButton>(find.byType(TextButton)).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('La hoja'), findsOneWidget);
    Navigator.of(tester.element(find.text('La hoja'))).pop();
    await tester.pumpAndSettle();

    expect(fieldHasFocus(tester), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('buscar con la tecla del teclado suelta el foco', (tester) async {
    await pump(tester);
    await tester.tap(field);
    await tester.enterText(field, 'Fotosintesis');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(fieldHasFocus(tester), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('tocar fuera —la lista— suelta el foco', (tester) async {
    await pump(tester);
    await tester.tap(field);
    await tester.pump();
    expect(fieldHasFocus(tester), isTrue);

    await tester.tapAt(const Offset(400, 500));
    await tester.pump();

    expect(fieldHasFocus(tester), isFalse);
    // Soltado así no queda tapado: tocarlo lo vuelve a enfocar.
    await tester.tap(field);
    await tester.pump();
    expect(fieldHasFocus(tester), isTrue);
  });

  testWidgets('tocar lo de adentro —la ✕ de borrar— no lo suelta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchField(
            key: const Key('busqueda'),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(field);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(fieldHasFocus(tester), isTrue);
  });

  testWidgets('con un foco de afuera, el mismo: el campo lo usa y lo deja '
      'como estaba', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchField(key: const Key('busqueda'), focusNode: focus),
        ),
      ),
    );

    focus.requestFocus();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(focus.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox());
    // Sigue andando después de que el campo se fue.
    expect(focus.canRequestFocus, isTrue);
  });

  testWidgets('si cambia el foco de afuera, la regla sigue al nuevo', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget app(FocusNode focus) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              SearchField(key: const Key('busqueda'), focusNode: focus),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('El detalle')),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(first));
    await tester.pumpWidget(app(second));

    second.requestFocus();
    await tester.pump();
    tester.widget<TextButton>(find.byType(TextButton)).onPressed!();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('El detalle'))).pop();
    await tester.pumpAndSettle();

    expect(second.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  test('el censo: todo buscador de una lista es un SearchField', () {
    /// Los campos con la tecla de buscar que no son el buscador de una lista,
    /// con el motivo.
    const allowed = <String, String>{
      'lib/core/design/widgets/search_field.dart': 'es el buscador',
      'lib/features/help/presentation/screens/user_guide_screen.dart':
          'además del buscador, la barra de «Buscar en la guía»: la tecla de '
          'buscar va a la coincidencia siguiente y el foco tiene que quedar',
      'lib/features/notebooks/presentation/widgets/ai_notebook_sheet.dart':
          'un formulario: lo que se escribe es el tema del cuaderno, y la '
          'tecla de buscar lo pide; no hay lista debajo',
    };
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      final text = file.readAsStringSync();
      final uses = 'TextInputAction.search'.allMatches(text).length;
      if (uses == 0) continue;
      final reason = allowed[path];
      if (reason == null) offenders.add(path);
    }
    expect(offenders, isEmpty);
    // La Ayuda tiene, además de la barra, el buscador: ese es un SearchField.
    final guide = File(
      'lib/features/help/presentation/screens/user_guide_screen.dart',
    ).readAsStringSync();
    expect('TextInputAction.search'.allMatches(guide).length, 1);
    expect(guide, contains('SearchField('));
  });
}
