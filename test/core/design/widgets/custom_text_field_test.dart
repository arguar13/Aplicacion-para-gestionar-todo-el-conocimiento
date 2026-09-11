import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/widgets/custom_text_field.dart';

/// Estos tests existen por una regresión concreta: `CustomTextField` traía
/// un `border: const OutlineInputBorder()` en su `InputDecoration`, y eso
/// anulaba el `inputDecorationTheme` entero de `AppTheme` (radio 12,
/// colores de `outline`/`primary`/`error`) devolviendo el default de
/// Material (radio 4, borde negro).
///
/// La causa es sutil y fácil de reintroducir: `InputDecoration.applyDefaults`
/// solo rellena los campos que están en `null`, así que fijar uno —aunque
/// sea con un valor "vacío"— lo saca de la jerarquía del tema para siempre.
/// Un comentario en el widget no impide que alguien lo vuelva a escribir;
/// esta prueba sí.
void main() {
  /// Lee la decoración **efectiva**, la que queda después de que
  /// `TextField` fusione la del widget con la del tema. Es lo que termina
  /// pintándose, y por lo tanto lo único que vale la pena afirmar: mirar
  /// la `InputDecoration` que el widget declara probaría la
  /// implementación, no el resultado.
  InputDecoration effectiveDecorationOf(WidgetTester tester) {
    return tester
        .widget<InputDecorator>(find.byType(InputDecorator))
        .decoration;
  }

  Widget buildTestableWidget(ThemeData theme) {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: CustomTextField(
          label: 'Correo electrónico',
          controller: controller,
          validator: (_) => null,
        ),
      ),
    );
  }

  group('integración con el tema', () {
    testWidgets('el borde sale del inputDecorationTheme, no de Material', (
      tester,
    ) async {
      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(buildTestableWidget(theme));

      // Se compara contra el propio tema en vez de contra un 12 escrito a
      // mano: lo que se está afirmando es "el campo respeta el tema",
      // no "el radio vale 12". Si mañana el diseño cambia el radio, este
      // test sigue siendo correcto sin tocarlo.
      expect(
        effectiveDecorationOf(tester).border,
        theme.inputDecorationTheme.border,
      );
    });

    testWidgets('el radio del borde es el de la app (12), no el default de '
        'Material (4)', (tester) async {
      await tester.pumpWidget(buildTestableWidget(AppTheme.lightTheme));

      final border = effectiveDecorationOf(tester).border;

      // Redundante con el test anterior a propósito: deja el síntoma
      // original escrito, para que un fallo futuro se lea como "volvió el
      // borde de Material" y no como una comparación abstracta.
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(12),
      );
    });

    testWidgets('el borde enfocado usa el color primario del tema', (
      tester,
    ) async {
      final theme = AppTheme.lightTheme;
      await tester.pumpWidget(buildTestableWidget(theme));

      expect(
        effectiveDecorationOf(tester).focusedBorder,
        theme.inputDecorationTheme.focusedBorder,
      );
    });

    testWidgets('en tema oscuro toma los colores oscuros: el widget no '
        'hardcodea ningún color propio', (tester) async {
      final theme = AppTheme.darkTheme;
      await tester.pumpWidget(buildTestableWidget(theme));

      final decoration = effectiveDecorationOf(tester);

      expect(decoration.border, theme.inputDecorationTheme.border);
      expect(
        decoration.focusedBorder,
        theme.inputDecorationTheme.focusedBorder,
      );
      expect(decoration.fillColor, theme.inputDecorationTheme.fillColor);
    });
  });

  group('comportamiento propio del widget', () {
    testWidgets('muestra la etiqueta recibida', (tester) async {
      await tester.pumpWidget(buildTestableWidget(AppTheme.lightTheme));

      expect(find.text('Correo electrónico'), findsOneWidget);
    });

    testWidgets('valida apenas el usuario interactúa, sin esperar al submit', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: CustomTextField(
              label: 'Correo electrónico',
              controller: controller,
              validator: (value) =>
                  (value?.isEmpty ?? true) ? 'Campo obligatorio' : null,
            ),
          ),
        ),
      );

      // `autovalidateMode: onUserInteraction` es parte del contrato del
      // widget: el error aparece al escribir y borrar, sin que nadie llame
      // a `FormState.validate()`.
      await tester.enterText(find.byType(TextField), 'a');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Campo obligatorio'), findsOneWidget);
    });
  });
}
