import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El aviso de abajo de toda la app (F45, paso 1): el texto a la izquierda,
/// hasta tres renglones; uno o dos botones a la derecha y la ✕ siempre. Si
/// el texto no entra en un renglón, se arma como una tarjeta: el texto arriba,
/// con todo el ancho, y abajo los botones y la ✕ en un renglón a la derecha,
/// sin aire de más (F46, paso 5d); sin botones, la ✕ queda arriba a la
/// derecha. Nunca un hueco en el medio.
///
/// Las pruebas van en un teléfono de 360 de ancho con la letra al doble,
/// salvo donde se dice: es donde el aviso de Material dejaba el hueco.
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
    TextDirection textDirection = TextDirection.ltr,
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
          child: Directionality(textDirection: textDirection, child: child!),
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
        isSemantics(
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
      // El texto toma el ancho entero, menos los márgenes: la ✕ ya no le
      // saca lugar, porque baja con los botones (F46, paso 5d).
      expect(parts.text.left - parts.card.left, 16);
      expect(parts.text.right, lessThanOrEqualTo(parts.card.right - 16));
      expect(parts.text.right, greaterThan(parts.close.left));
      // Abajo a la derecha, «Deshacer» pegado a la ✕, y la ✕ pegada al
      // borde, centrada con él.
      expect(parts.card.right - parts.close.right, 4);
      expect(parts.undo.right, closeTo(parts.close.left, 0.5));
      expect(parts.close.center.dy, closeTo(parts.undo.center.dy, 0.5));
      // Debajo del texto y sin aire de más: los botones ya lo traen adentro.
      expect(parts.view.top, closeTo(parts.text.bottom, 0.5));
      expect(parts.card.bottom, closeTo(parts.undo.bottom, 0.5));
      return parts;
    }

    testWidgets('si no entra, los dos botones bajan juntos a la derecha, con '
        'la ✕ al final de su renglón: sin hueco en el medio', (tester) async {
      final parts = await showLong(tester, textScale: 1);

      // Juntos en un renglón, «Ver», «Deshacer» y la ✕.
      expect(parts.view.center.dy, closeTo(parts.undo.center.dy, 0.5));
      expect(parts.view.right, lessThanOrEqualTo(parts.undo.left));
      expect(parts.undo.left - parts.view.right, lessThanOrEqualTo(4));
    });

    testWidgets('con la letra al doble, si los botones tampoco entran juntos, '
        'se apilan a la derecha y la ✕ queda al lado del último', (
      tester,
    ) async {
      final parts = await showLong(tester, textScale: 2);

      expect(parts.view.bottom, closeTo(parts.undo.top, 0.5));
      expect(parts.view.right, parts.undo.right);
      // Arriba de la ✕, nada: «Ver» termina donde empieza ella.
      expect(parts.view.right, closeTo(parts.close.left, 0.5));
      expect(parts.close.top, greaterThanOrEqualTo(parts.view.bottom));
    });

    testWidgets('un texto corto con un botón largo: el botón baja y el texto '
        'no se aprieta', (tester) async {
      // «Movido» entra al lado de la ✕, pero no al lado de «Deshacer».
      await show(
        tester,
        () => AppSnackBar(content: const Text('Movido'), action: undo()),
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('Movido'),
      );
      expect(
        tester.getRect(find.text('Movido')).height,
        closeTo(paragraph.preferredLineHeight, 0.5),
      );
      expect(
        tester.getRect(button('Deshacer')).top,
        greaterThanOrEqualTo(tester.getRect(find.text('Movido')).bottom),
      );
      // Baja con la ✕, que queda al final de su renglón.
      expect(
        tester.getRect(button('Deshacer')).right,
        closeTo(tester.getRect(closeBox()).left, 0.5),
      );
      expect(
        tester.getRect(closeBox()).center.dy,
        closeTo(tester.getRect(button('Deshacer')).center.dy, 0.5),
      );
      expect(card(tester).right - tester.getRect(closeBox()).right, 4);
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
      // «Deshacer» y la ✕ debajo, a la derecha.
      expect(
        tester.getRect(closeBox()).top,
        greaterThanOrEqualTo(tester.getRect(find.text(message)).bottom),
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

  group('la ✕ en el renglón de los botones (F46, paso 5d)', () {
    /// El acomodo del aviso que está en pantalla, para leerle las
    /// intrínsecas y la línea base.
    RenderBox layoutOf(WidgetTester tester) => tester.renderObject<RenderBox>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_NoticeLayout',
      ),
    );

    /// Que el aviso con [message] y los botones [labels] —en el orden en que
    /// se leen— esté prolijo: nada encimado, la ✕ al final y el último botón
    /// pegado a ella; en un renglón si entra todo, y si no, el texto arriba con
    /// el ancho entero y abajo los botones con la ✕ en su renglón, sin aire de
    /// más. [lines] es cuántos renglones tiene el texto si va en una tarjeta.
    void expectTidy(
      WidgetTester tester, {
      required String message,
      required List<String> labels,
      required int lines,
      required TextDirection textDirection,
    }) {
      final ltr = textDirection == TextDirection.ltr;
      final box = card(tester);
      final text = tester.getRect(find.text(message));
      final closeRect = tester.getRect(closeBox());
      final buttons = [
        for (final label in labels) tester.getRect(button(label)),
      ];
      double fromEnd(Rect rect) =>
          ltr ? box.right - rect.right : rect.left - box.left;
      double fromStart(Rect rect) =>
          ltr ? rect.left - box.left : box.right - rect.right;

      // Ninguna caja se encima con otra, y todas quedan en la tarjeta.
      final parts = {
        'el texto': text,
        'la ✕': closeRect,
        for (var i = 0; i < labels.length; i++) labels[i]: buttons[i],
      };
      final names = parts.keys.toList();
      for (var i = 0; i < names.length; i++) {
        final a = parts[names[i]]!;
        expect(box.inflate(0.5).contains(a.topLeft), isTrue);
        expect(box.inflate(0.5).contains(a.bottomRight), isTrue);
        for (var j = i + 1; j < names.length; j++) {
          final overlap = a.intersect(parts[names[j]]!);
          expect(
            overlap.width > 0.5 && overlap.height > 0.5,
            isFalse,
            reason: '${names[i]} se encima con ${names[j]}',
          );
        }
      }
      // Las cajas de 48 para el dedo, enteras.
      expect(closeRect.height, greaterThanOrEqualTo(48));
      for (final rect in buttons) {
        expect(rect.height, greaterThanOrEqualTo(48));
      }

      // La ✕, al final; el último botón, pegado a ella; el texto, al
      // principio.
      expect(fromEnd(closeRect), closeTo(4, 0.5));
      final last = buttons.last;
      expect(
        ltr ? closeRect.left - last.right : last.left - closeRect.right,
        closeTo(0, 0.5),
      );
      expect(fromStart(text), closeTo(16, 0.5));

      /// Uno al lado del otro, con 4 entre un botón y el siguiente.
      void expectSideBySide() {
        for (var i = 1; i < buttons.length; i++) {
          expect(
            ltr
                ? buttons[i].left - buttons[i - 1].right
                : buttons[i - 1].left - buttons[i].right,
            closeTo(4, 0.5),
          );
        }
      }

      // Si todo entra en un renglón, va en uno, como siempre.
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(message),
      );
      final buttonsWidth =
          [
            for (final label in labels)
              tester
                  .renderObject<RenderBox>(button(label))
                  .getMaxIntrinsicWidth(double.infinity),
          ].reduce((a, b) => a + b) +
          4 * (labels.length - 1);
      final inline =
          16 +
              paragraph.getMaxIntrinsicWidth(double.infinity) +
              8 +
              buttonsWidth +
              closeRect.width +
              4 <=
          box.width;
      if (inline) {
        for (final rect in [closeRect, ...buttons]) {
          expect(rect.center.dy, closeTo(text.center.dy, 0.5));
        }
        expectSideBySide();
        expect(
          box.height,
          closeTo(
            [
              text.height + 28,
              closeRect.height,
              for (final rect in buttons) rect.height,
            ].reduce(math.max),
            0.5,
          ),
        );
        return;
      }

      // Si no, una tarjeta: el texto arriba, con el ancho entero.
      expect(text.top - box.top, closeTo(14, 0.5));
      expect(fromEnd(text), greaterThanOrEqualTo(16 - 0.5));
      expect(text.height, closeTo(lines * paragraph.preferredLineHeight, 0.5));
      // Abajo, los botones empiezan donde termina el texto, la ✕ va en el
      // renglón del último, y el aviso termina donde terminan ellos.
      final top = buttons.map((rect) => rect.top).reduce(math.min);
      expect(top, closeTo(text.bottom, 0.5));
      expect(closeRect.center.dy, closeTo(last.center.dy, 0.5));
      expect(closeRect.top, greaterThanOrEqualTo(text.bottom - 0.5));
      expect(box.bottom, closeTo(math.max(closeRect.bottom, last.bottom), 0.5));
      // Juntos en el renglón si entran al lado de la ✕; si no, apilados en
      // el orden en que se leen, con el final pegado a la ✕.
      final room = box.width - 4 - closeRect.width - 16;
      final rowWidth =
          buttons.map((rect) => rect.width).reduce((a, b) => a + b) +
          4 * (buttons.length - 1);
      if (rowWidth <= room + 0.5) {
        for (final rect in buttons) {
          expect(rect.center.dy, closeTo(closeRect.center.dy, 0.5));
        }
        expectSideBySide();
      } else {
        for (var i = 1; i < buttons.length; i++) {
          expect(buttons[i].top, closeTo(buttons[i - 1].bottom, 0.5));
          expect(fromEnd(buttons[i]), closeTo(fromEnd(buttons[i - 1]), 0.5));
        }
      }
    }

    /// Lo que mide el acomodo por adentro tiene que decir lo mismo que lo que
    /// se ve: la medida en seco, las intrínsecas y la línea base. [labels]
    /// son los botones del aviso.
    void expectConsistent(
      WidgetTester tester,
      String message, {
      List<String> labels = const [],
    }) {
      final layout = layoutOf(tester);
      final size = layout.size;
      expect(
        layout.getDryLayout(BoxConstraints.tightFor(width: size.width)),
        size,
      );
      expect(layout.getMinIntrinsicHeight(size.width), size.height);
      expect(layout.getMaxIntrinsicHeight(size.width), size.height);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(message),
      );
      final close = tester.renderObject<RenderBox>(closeBox());
      final buttons = [
        for (final label in labels)
          tester.renderObject<RenderBox>(button(label)),
      ];
      // Lo más angosto: sin botones, la palabra más larga al lado de la ✕;
      // con botones, la palabra más larga con el ancho entero, y debajo el
      // botón más angosto que se pueda, apilado, al lado de la ✕.
      final closeMin = close.getMinIntrinsicWidth(double.infinity);
      final messageMin = paragraph.getMinIntrinsicWidth(double.infinity);
      expect(
        layout.getMinIntrinsicWidth(double.infinity),
        closeTo(
          buttons.isEmpty
              ? 16 + messageMin + closeMin + 4
              : math.max(
                  16 + messageMin + 16,
                  16 +
                      buttons
                          .map((b) => b.getMinIntrinsicWidth(double.infinity))
                          .reduce(math.max) +
                      closeMin +
                      4,
                ),
          0.01,
        ),
      );
      // Lo más ancho: todo en un renglón.
      expect(
        layout.getMaxIntrinsicWidth(double.infinity),
        closeTo(
          16 +
              paragraph.getMaxIntrinsicWidth(double.infinity) +
              8 +
              [for (final b in buttons) b.getMaxIntrinsicWidth(double.infinity)]
                  .fold<double>(0, (a, b) => a + b) +
              4 * math.max(0, buttons.length - 1) +
              close.getMaxIntrinsicWidth(double.infinity) +
              4,
          0.01,
        ),
      );
      // La línea base en seco es la del texto, donde quedó.
      expect(
        layout.getDryBaseline(
          BoxConstraints.tightFor(width: size.width),
          TextBaseline.alphabetic,
        ),
        closeTo(
          tester.getTopLeft(find.text(message)).dy -
              layout.localToGlobal(Offset.zero).dy +
              paragraph.getDryBaseline(
                paragraph.constraints,
                TextBaseline.alphabetic,
              )!,
          0.01,
        ),
      );
    }

    final threeLines = List.filled(12, 'una palabra más').join(' ');
    for (final width in [360.0, 412.0, 427.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final (buttonsName, secondary, primary) in [
          ('un botón corto', null, 'Ver'),
          ('un botón largo', null, 'Ver qué falló'),
          ('dos botones', 'Ver', 'Deshacer'),
        ]) {
          for (final (linesName, message, lines) in [
            ('un renglón', 'Con error', 1),
            ('tres renglones', threeLines, kSnackBarMaxLines),
          ]) {
            for (final textDirection in TextDirection.values) {
              testWidgets('a $width de ancho, con la letra a $scale, '
                  '$buttonsName y un texto de $linesName, '
                  '${textDirection.name}', (tester) async {
                await show(
                  tester,
                  () => AppSnackBar(
                    content: Text(message),
                    secondaryAction: secondary == null
                        ? null
                        : SnackBarAction(label: secondary, onPressed: () {}),
                    action: SnackBarAction(label: primary, onPressed: () {}),
                  ),
                  textScale: scale,
                  size: Size(width, 800),
                  textDirection: textDirection,
                );

                expectTidy(
                  tester,
                  message: message,
                  labels: [?secondary, primary],
                  lines: lines,
                  textDirection: textDirection,
                );
                expectConsistent(
                  tester,
                  message,
                  labels: [?secondary, primary],
                );
              });
            }
          }
        }
      }
    }

    testWidgets('con un renglón y un botón abajo, mide lo justo: 14 arriba, '
        'el renglón y la caja de 48 de los botones y la ✕', (tester) async {
      // A 427 de ancho, como en el emulador: el texto entra en un renglón
      // con el ancho entero, pero no al lado de «Ver qué falló» y la ✕.
      const message = 'Cargados 76, con error 4';
      await show(
        tester,
        () => AppSnackBar(
          content: const Text(message),
          action: SnackBarAction(label: 'Ver qué falló', onPressed: () {}),
        ),
        textScale: 1,
        size: const Size(427, 800),
      );

      final box = card(tester);
      final text = tester.getRect(find.text(message));
      final line = tester
          .renderObject<RenderParagraph>(find.text(message))
          .preferredLineHeight;
      // Con la letra de las pruebas, un renglón de 14 mide 14.
      expect(line, 14);
      expect(text.height, closeTo(line, 0.01));
      expect(text.top - box.top, 14);
      // Los botones y la ✕, en la misma caja de 48, justo debajo del texto.
      for (final rect in [
        tester.getRect(button('Ver qué falló')),
        tester.getRect(closeBox()),
      ]) {
        expect(rect.top - box.top, closeTo(14 + line, 0.01));
        expect(rect.height, 48);
      }
      // 14 + 14 + 48 = 76 (en el teléfono, con Inter y su renglón de 20, 82):
      // antes medía 100 —en el teléfono, 14 + 20 dejaba la ✕ en 0..48, los
      // botones en 48..96 y 4 más abajo—, y acá 14 + 14 no llegaba a los 48 de
      // la ✕: también 100.
      expect(box.height, closeTo(14 + line + 48, 0.01));
      expect(box.height, 76);
    });

    testWidgets('si todo entra en un renglón, no cambia: 48 de alto, todo '
        'centrado', (tester) async {
      await show(
        tester,
        () => AppSnackBar(content: const Text('Listo'), action: view()),
        textScale: 1,
      );

      final box = card(tester);
      expect(box.height, 48);
      expect(tester.getRect(find.text('Listo')).left - box.left, 16);
      for (final rect in [
        tester.getRect(button('Ver')),
        tester.getRect(closeBox()),
      ]) {
        expect(rect.top, box.top);
        expect(rect.height, 48);
      }
      expect(
        tester.getRect(find.text('Listo')).center.dy,
        closeTo(box.center.dy, 0.5),
      );
      expect(
        tester.getRect(button('Ver')).right,
        tester.getRect(closeBox()).left,
      );
      expect(box.right - tester.getRect(closeBox()).right, 4);
    });

    testWidgets('sin botones, la ✕ sigue arriba a la derecha', (tester) async {
      const message = 'No se pudo abrir el archivo que elegiste';
      await show(
        tester,
        () => AppSnackBar(content: const Text(message)),
        textScale: 1,
      );

      final box = card(tester);
      final text = tester.getRect(find.text(message));
      final closeRect = tester.getRect(closeBox());
      final line = tester
          .renderObject<RenderParagraph>(find.text(message))
          .preferredLineHeight;
      expect(text.right, closeTo(closeRect.left, 0.5));
      // Centrada con el primer renglón, salvo que eso la saque por arriba.
      expect(
        closeRect.top - box.top,
        closeTo(math.max(0, 14 + line / 2 - closeRect.height / 2), 0.5),
      );
      expect(box.bottom - text.bottom, 14);
      expectConsistent(tester, message);
    });

    testWidgets('en la tarjeta, cada toque va a lo suyo: la ✕ cierra sin '
        'tocar el botón, y el botón hace lo suyo', (tester) async {
      final pressed = <String>[];
      Future<void> open() => show(
        tester,
        () => AppSnackBar(
          content: const Text('Cargados 76, con error 4'),
          secondaryAction: view(() => pressed.add('ver')),
          action: undo(() => pressed.add('deshacer')),
        ),
        textScale: 1,
      );
      await open();
      // Abajo, uno al lado del otro con la ✕.
      expect(
        tester.getRect(closeBox()).center.dy,
        closeTo(tester.getRect(button('Ver')).center.dy, 0.5),
      );

      // En el borde de la ✕ que da a «Deshacer», todavía la ✕.
      await tester.tapAt(
        tester.getRect(closeBox()).centerLeft + const Offset(1, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cargados 76, con error 4'), findsNothing);
      expect(pressed, isEmpty);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getRect(button('Deshacer')).centerRight - const Offset(1, 0),
      );
      await tester.pumpAndSettle();
      expect(pressed, ['deshacer']);
    });

    testWidgets('el aviso de la Biblioteca de ejemplo, a 427 de ancho', (
      tester,
    ) async {
      const message = 'Biblioteca de ejemplo: cargados 76 · con error 4';
      await show(
        tester,
        () => AppSnackBar(
          content: const Text(message),
          action: SnackBarAction(label: 'Ver qué falló', onPressed: () {}),
        ),
        textScale: 1,
        size: const Size(427, 800),
      );

      // Con la letra de las pruebas, cuadrada, ocupa dos renglones.
      expectTidy(
        tester,
        message: message,
        labels: const ['Ver qué falló'],
        lines: 2,
        textDirection: TextDirection.ltr,
      );
      expectConsistent(tester, message, labels: const ['Ver qué falló']);
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
