import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El aviso de abajo de toda la app (F45, paso 1): el texto a la izquierda,
/// hasta tres renglones; uno o dos botones a la derecha y la ✕ siempre. Si
/// el texto no entra en un renglón, los botones bajan juntos a la derecha y la
/// ✕ queda arriba a la derecha, como una tarjeta: nunca un hueco en el medio.
///
/// Todo en un teléfono de 360 de ancho con la letra al doble, salvo donde se
/// dice: es donde el aviso de Material dejaba el hueco.
void main() {
  const phone = Size(360, 760);
  final close = find.byTooltip('Cerrar aviso');

  /// La ✕ entera, con su lugar para el dedo: lo que se acomoda.
  Finder closeBox([Finder? of]) =>
      find.ancestor(of: of ?? close, matching: find.byType(IconButton));
  final notice = find.byType(SnackBar);

  /// Una pantalla con un botón que muestra [snackBar], en [theme] y con la
  /// letra a [textScale].
  Future<void> show(
    WidgetTester tester,
    AppSnackBar Function() snackBar, {
    ThemeData? theme,
    double textScale = 2,
    Size size = phone,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).showAppSnackBar(snackBar()),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  SnackBarAction undo([VoidCallback? onPressed]) =>
      SnackBarAction(label: 'Deshacer', onPressed: onPressed ?? () {});
  SnackBarAction view([VoidCallback? onPressed]) =>
      SnackBarAction(label: 'Ver', onPressed: onPressed ?? () {});

  /// El botón del aviso que dice [label].
  Finder button(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextButton));

  /// El borde del aviso, sin sus márgenes de afuera: la tarjeta que se ve.
  Rect card(WidgetTester tester) => tester.getRect(
    find.descendant(of: notice, matching: find.byType(Material)).first,
  );

  group('la ✕, siempre', () {
    testWidgets('también en una confirmación corta, que igual se va sola', (
      tester,
    ) async {
      await show(tester, () => AppSnackBar(content: const Text('Copiado')));

      expect(close, findsOneWidget);
      // Una sola: la de Material no se suma.
      expect(find.byIcon(Icons.close), findsOneWidget);
      // Sin botón, no se queda: se va a los cuatro segundos, como siempre.
      await tester.pump(kSnackBarDefaultDuration);
      await tester.pumpAndSettle();
      expect(find.text('Copiado'), findsNothing);
    });

    testWidgets('cierra el aviso en el acto, sin tocar sus botones', (
      tester,
    ) async {
      var undone = false;
      await show(
        tester,
        () => AppSnackBar(
          content: const Text('Movido a la papelera'),
          action: undo(() => undone = true),
        ),
      );
      // Con un botón, se queda hasta que lo cierren.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Movido a la papelera'), findsOneWidget);

      await tester.tap(close);
      await tester.pumpAndSettle();

      expect(find.text('Movido a la papelera'), findsNothing);
      expect(undone, isFalse);
    });

    testWidgets('el lector de pantalla la anuncia como un botón que cierra '
        'el aviso', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, () => AppSnackBar(content: const Text('Copiado')));

      expect(
        tester.getSemantics(close),
        containsSemantics(
          tooltip: 'Cerrar aviso',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    for (final (name, theme) in [
      ('claro', AppTheme.lightTheme),
      ('oscuro', AppTheme.darkTheme),
    ]) {
      testWidgets('en el tema $name, con el color del texto del aviso', (
        tester,
      ) async {
        await show(
          tester,
          () => AppSnackBar(content: const Text('Copiado'), action: undo()),
          theme: theme,
        );

        final icon = tester.widget<IconButton>(
          find.ancestor(of: close, matching: find.byType(IconButton)),
        );
        expect(icon.color, theme.colorScheme.onInverseSurface);
        expect(
          tester
              .widget<Material>(
                find
                    .descendant(of: notice, matching: find.byType(Material))
                    .first,
              )
              .color,
          theme.colorScheme.inverseSurface,
        );
      });
    }
  });

  group('cómo se acomoda', () {
    testWidgets('corto: el texto, los botones y la ✕ en un renglón', (
      tester,
    ) async {
      await show(
        tester,
        () => AppSnackBar(content: const Text('Listo'), action: view()),
      );

      final text = tester.getCenter(find.text('Listo'));
      expect(tester.getCenter(find.text('Ver')).dy, closeTo(text.dy, 0.5));
      expect(tester.getCenter(closeBox()).dy, closeTo(text.dy, 0.5));
      // El botón, pegado a la ✕; la ✕, a la derecha de la tarjeta.
      expect(
        tester.getRect(button('Ver')).right,
        closeTo(tester.getRect(closeBox()).left, 0.5),
      );
      expect(card(tester).right - tester.getRect(closeBox()).right, 4);
    });

    testWidgets('en la computadora, con dos botones, también en un renglón', (
      tester,
    ) async {
      await show(
        tester,
        () => AppSnackBar(
          content: const Text('Triado: Roma'),
          secondaryAction: view(),
          action: undo(),
        ),
        textScale: 1,
        size: const Size(900, 700),
      );

      final y = tester.getCenter(find.text('Triado: Roma')).dy;
      expect(tester.getCenter(find.text('Ver')).dy, closeTo(y, 0.5));
      expect(tester.getCenter(find.text('Deshacer')).dy, closeTo(y, 0.5));
      expect(tester.getCenter(closeBox()).dy, closeTo(y, 0.5));
      // En el orden en que se leen: «Ver», «Deshacer» y la ✕.
      expect(
        tester.getRect(find.text('Ver')).right,
        lessThan(tester.getRect(find.text('Deshacer')).left),
      );
      expect(
        tester.getRect(find.text('Deshacer')).right,
        lessThan(tester.getRect(closeBox()).left),
      );
    });

    /// El aviso de la captura de F45: un título largo con «Ver» y
    /// «Deshacer».
    Future<({Rect text, Rect close, Rect view, Rect undo, Rect card})> showLong(
      WidgetTester tester, {
      required double textScale,
    }) async {
      const message = 'Procesado actualizado: Historia de Heródoto';
      await show(
        tester,
        () => AppSnackBar(
          content: const Text(message),
          secondaryAction: view(),
          action: undo(),
        ),
        textScale: textScale,
      );
      final parts = (
        text: tester.getRect(find.text(message)),
        close: tester.getRect(closeBox()),
        view: tester.getRect(button('Ver')),
        undo: tester.getRect(button('Deshacer')),
        card: card(tester),
      );
      // El texto toma todo el ancho hasta la ✕: nada reservado a su derecha.
      expect(parts.text.right, closeTo(parts.close.left, 0.5));
      // La ✕, arriba a la derecha, a la altura del primer renglón.
      expect(parts.close.top, lessThan(parts.text.top + parts.text.height / 2));
      expect(parts.card.right - parts.close.right, 4);
      // Los botones, debajo del texto y de la ✕, a la derecha —el último
      // pegado al borde, como la ✕— y sin aire de más.
      expect(parts.card.right - parts.undo.right, 4);
      expect(parts.view.top, greaterThanOrEqualTo(parts.text.bottom));
      expect(parts.view.top, greaterThanOrEqualTo(parts.close.bottom));
      expect(parts.view.top - parts.text.bottom, lessThanOrEqualTo(16));
      expect(parts.card.bottom - parts.undo.bottom, 4);
      return parts;
    }

    testWidgets('si no entra, los dos botones bajan juntos a la derecha y la '
        '✕ queda arriba: sin hueco en el medio', (tester) async {
      final parts = await showLong(tester, textScale: 1);

      // Juntos en un renglón, «Ver» y después «Deshacer».
      expect(parts.view.center.dy, closeTo(parts.undo.center.dy, 0.5));
      expect(parts.view.right, lessThanOrEqualTo(parts.undo.left));
      expect(parts.undo.left - parts.view.right, lessThanOrEqualTo(4));
    });

    testWidgets('con la letra al doble, si los botones tampoco entran juntos, '
        'se apilan a la derecha', (tester) async {
      final parts = await showLong(tester, textScale: 2);

      expect(parts.view.bottom, lessThanOrEqualTo(parts.undo.top));
      expect(parts.undo.top - parts.view.bottom, lessThanOrEqualTo(4));
      expect(parts.view.right, parts.undo.right);
    });

    testWidgets('un texto largo, en hasta tres renglones', (tester) async {
      final message = List.filled(12, 'una palabra más').join(' ');
      await show(
        tester,
        () => AppSnackBar(content: Text(message), action: undo()),
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(message),
      );
      expect(paragraph.maxLines, kSnackBarMaxLines);
      expect(paragraph.didExceedMaxLines, isTrue);
      final line = paragraph.preferredLineHeight;
      expect(
        tester.getRect(find.text(message)).height,
        closeTo(kSnackBarMaxLines * line, 1),
      );
      // Con la ✕ arriba y «Deshacer» debajo, a la derecha.
      expect(
        tester.getRect(closeBox()).top,
        lessThan(tester.getRect(find.text(message)).top + line),
      );
      expect(
        tester.getRect(find.text('Deshacer')).top,
        greaterThan(tester.getRect(find.text(message)).bottom),
      );
    });

    testWidgets('sin botones, el texto largo se acomoda al lado de la ✕', (
      tester,
    ) async {
      const message = 'No se pudo abrir el archivo que elegiste';
      await show(tester, () => AppSnackBar(content: const Text(message)));

      final text = tester.getRect(find.text(message));
      expect(text.right, closeTo(tester.getRect(closeBox()).left, 0.5));
      expect(tester.getRect(closeBox()).top, lessThan(text.center.dy));
      expect(card(tester).bottom - text.bottom, 14);
    });

    testWidgets('en un idioma que se escribe al revés, todo al revés', (
      tester,
    ) async {
      tester.view
        ..physicalSize = phone
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context).showAppSnackBar(
                        AppSnackBar(
                          content: const Text('Listo'),
                          action: view(),
                        ),
                      ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final closeRect = tester.getRect(closeBox(find.byTooltip('Close')));
      expect(closeRect.left - card(tester).left, 4);
      expect(
        tester.getRect(find.text('Listo')).left,
        greaterThan(tester.getRect(find.text('Ver')).right),
      );
    });
  });

  group('los dos botones', () {
    testWidgets('cada uno hace lo suyo y cierra el aviso', (tester) async {
      final pressed = <String>[];
      await show(
        tester,
        () => AppSnackBar(
          content: const Text('Triado: Roma'),
          secondaryAction: view(() => pressed.add('ver')),
          action: undo(() => pressed.add('deshacer')),
        ),
      );

      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(pressed, ['ver']);
      expect(find.text('Triado: Roma'), findsNothing);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(pressed, ['ver', 'deshacer']);
      expect(find.text('Triado: Roma'), findsNothing);
    });

    testWidgets('mientras el aviso se va, ya no recibe toques', (tester) async {
      final pressed = <String>[];
      await show(
        tester,
        () => AppSnackBar(
          content: const Text('Triado: Roma'),
          secondaryAction: view(() => pressed.add('ver')),
          action: undo(() => pressed.add('deshacer')),
        ),
      );

      await tester.tap(find.text('Deshacer'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Ver'), findsOneWidget);
      await tester.tap(find.text('Ver'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(pressed, ['deshacer']);
    });

    testWidgets('un solo botón secundario va solo, pegado a la ✕', (
      tester,
    ) async {
      await show(
        tester,
        () =>
            AppSnackBar(content: const Text('Listo'), secondaryAction: view()),
      );

      expect(find.byType(SnackBarAction), findsOneWidget);
      expect(
        tester.getRect(button('Ver')).right,
        closeTo(tester.getRect(closeBox()).left, 0.5),
      );
      // Con un botón, también se queda hasta que lo cierren.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Listo'), findsOneWidget);
    });
  });

  test('con un botón se queda, salvo que se pida que se vaya solo', () {
    expect(AppSnackBar(content: const Text('x'), action: undo()).persist, true);
    expect(
      AppSnackBar(content: const Text('x'), secondaryAction: view()).persist,
      true,
    );
    expect(
      AppSnackBar(
        content: const Text('x'),
        action: undo(),
        persist: false,
      ).persist,
      false,
    );
    expect(AppSnackBar(content: const Text('x')).persist, false);
    expect(
      AppSnackBar(content: const Text('x')).showCloseIcon,
      isFalse,
      reason:
          'la ✕ la pone el aviso, no Material: la de Material dejaba '
          'el hueco',
    );
  });
}
