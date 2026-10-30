import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/features/library/presentation/widgets/list_controls.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Lo que el panel muestra en su pie: la cuenta y si algo acota.
typedef _Footer = ({AsyncValue<int> results, bool narrowed});

/// El marco del panel de filtros (F47, mejora 21): el pie fijo «Ver N
/// resultados», que lo cierra con la cifra contada en la base. Acá con una
/// cuenta de mentira que se mueve a mano —sin base—; cada pantalla que lo usa
/// se prueba con la suya (`list_filters_footer_screens_test.dart`).
void main() {
  final es = AppLocalizationsEs();
  final footer = find.byKey(ListFiltersSheet.showResultsKey);

  /// La cuenta que ve el panel abierto: se cambia y el pie la sigue.
  late ValueNotifier<_Footer> shown;

  /// Lo que devolvió `showListFiltersSheet` al cerrarse; `null` mientras
  /// sigue abierto.
  bool? closedWithResults;

  setUp(() {
    shown = ValueNotifier((results: const AsyncData(12), narrowed: true));
    closedWithResults = null;
  });
  tearDown(() => shown.dispose());

  /// Una pantalla con un botón que abre el panel, con [sections] chips de
  /// relleno —muchos, para que haya que desplazarse—, en [size] con la letra
  /// a [textScale], en [brightness] y con [bottomInset] de borde seguro
  /// abajo (la barra de gestos del sistema).
  Future<void> openSheet(
    WidgetTester tester, {
    Size size = const Size(360, 780),
    double textScale = 2,
    Brightness brightness = Brightness.light,
    double bottomInset = 0,
    int sections = 3,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..padding = FakeViewPadding(bottom: bottomInset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  closedWithResults = await showListFiltersSheet(
                    context,
                    builder: (_) => ValueListenableBuilder<_Footer>(
                      valueListenable: shown,
                      builder: (_, footer, _) => ListFiltersSheet(
                        onClear: footer.narrowed ? () {} : null,
                        results: footer.results,
                        narrowed: footer.narrowed,
                        children: [
                          for (var s = 0; s < sections; s++) ...[
                            FilterSectionLabel('Sección $s'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var c = 0; c < 6; c++)
                                  FilterChip(
                                    label: Text('Filtro $s.$c'),
                                    onSelected: (_) {},
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester,
    AsyncValue<int> results, {
    bool narrowed = true,
  }) async {
    shown.value = (results: results, narrowed: narrowed);
    await tester.pump();
  }

  FilledButton button(WidgetTester tester) =>
      tester.widget<FilledButton>(footer);

  /// Lo que dice el pie, sin la frase que solo guarda el lugar.
  String label(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: footer, matching: find.byType(Text)),
        )
        .where(
          (text) => find
              .ancestor(
                of: find.byWidget(text),
                matching: find.byWidgetPredicate(
                  (w) => w is Visibility && !w.visible,
                ),
              )
              .evaluate()
              .isEmpty,
        );
    return texts.single.data!;
  }

  group('lo que dice', () {
    testWidgets('con filtros, cuántos quedan, con su plural', (tester) async {
      await openSheet(tester);
      expect(label(tester), es.f47P0FiltersShowResults(12));
      expect(label(tester), 'Ver 12 resultados');

      await show(tester, const AsyncData(1));
      expect(label(tester), 'Ver 1 resultado');
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('sin nada que acote, «Ver todo» con el total', (tester) async {
      await openSheet(tester);
      await show(tester, const AsyncData(340), narrowed: false);

      expect(label(tester), 'Ver todo (340)');
      expect(button(tester).onPressed, isNotNull);

      // Y al volver a acotar, de nuevo cuántos quedan: «Ver todo» es solo
      // sin filtros.
      await show(tester, const AsyncData(340));
      expect(label(tester), 'Ver 340 resultados');
    });

    testWidgets('mientras cuenta, sin cifra: tampoco la de antes', (
      tester,
    ) async {
      await openSheet(tester);

      await show(tester, const AsyncLoading());
      expect(label(tester), es.f47P0FiltersCounting);
      expect(button(tester).onPressed, isNotNull);

      // Una cuenta que se repite recuerda la cifra de antes: ya no es cierta.
      await show(
        tester,
        const AsyncLoading<int>().copyWithPrevious(const AsyncData(12)),
      );
      expect(label(tester), es.f47P0FiltersCounting);

      // Si no se pudo contar, la lista igual se ve: el pie la ofrece.
      await show(tester, AsyncError<int>(StateError('roto'), StackTrace.empty));
      expect(label(tester), es.f47P0FiltersCounting);
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('con cero, «Ningún resultado», apagado, con «Limpiar '
        'filtros» arriba', (tester) async {
      await openSheet(tester);
      await show(tester, const AsyncData(0));

      expect(label(tester), es.f47P0FiltersNoResults);
      expect(button(tester).onPressed, isNull);
      expect(find.text(es.libraryClearFilters), findsOneWidget);

      // Apagado de verdad: tocarlo no cierra nada.
      await tester.tap(footer, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(footer, findsOneWidget);
      expect(closedWithResults, isNull);
    });
  });

  group('al tocarlo', () {
    testWidgets('cierra el panel y avisa que se pidió ver los resultados', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(footer);
      await tester.pumpAndSettle();

      expect(footer, findsNothing);
      expect(closedWithResults, isTrue);
    });

    testWidgets('cerrado de otra forma, lo elegido vale igual pero no pide '
        'nada', (tester) async {
      await openSheet(tester);

      Navigator.of(tester.element(footer)).pop();
      await tester.pumpAndSettle();

      expect(footer, findsNothing);
      expect(closedWithResults, isFalse);
    });

    testWidgets('mientras cuenta también cierra: los filtros ya se aplicaron', (
      tester,
    ) async {
      await openSheet(tester);
      await show(tester, const AsyncLoading());

      await tester.tap(footer);
      await tester.pumpAndSettle();

      expect(closedWithResults, isTrue);
    });
  });

  testWidgets('no salta de tamaño mientras cuenta: guarda el lugar de la '
      'cifra de antes', (tester) async {
    // A 360 con la letra al doble, «Ver 12 resultados» entra en una línea,
    // como «Ver resultados»; una cifra larga ocupa dos.
    await openSheet(tester);
    final oneLine = tester.getSize(footer);
    await show(tester, const AsyncData(1234567));
    final counted = tester.getSize(footer);
    expect(counted.height, greaterThan(oneLine.height));

    await show(tester, const AsyncLoading());
    expect(label(tester), es.f47P0FiltersCounting);
    expect(tester.getSize(footer), counted);

    // Lo que guarda el lugar no se lee.
    expect(
      find.bySemanticsLabel(es.f47P0FiltersShowResults(1234567)),
      findsNothing,
    );

    // Contado de nuevo, toma el tamaño de su frase: dejar de guardar el
    // lugar no es quedarse grande.
    await show(tester, const AsyncData(12));
    expect(tester.getSize(footer), oneLine);
  });

  testWidgets('para el lector de pantalla, un botón con la frase entera y una '
      'región viva, que cambia con la cifra', (tester) async {
    final semantics = tester.ensureSemantics();
    await openSheet(tester);

    expect(
      tester.getSemantics(footer),
      isSemantics(
        label: 'Ver 12 resultados',
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
        isLiveRegion: true,
      ),
    );

    await show(tester, const AsyncData(3));
    expect(tester.getSemantics(footer).label, 'Ver 3 resultados');

    await show(tester, const AsyncData(0));
    expect(
      tester.getSemantics(footer),
      isSemantics(
        label: es.f47P0FiltersNoResults,
        isButton: true,
        isEnabled: false,
        hasTapAction: false,
        isLiveRegion: true,
      ),
    );
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    group('en ${brightness.name}', () {
      testWidgets('a 360 con la letra al doble, el pie queda fijo abajo '
          'mientras se desplazan los filtros, sin desbordar', (tester) async {
        await openSheet(tester, brightness: brightness, sections: 8);
        expect(tester.takeException(), isNull);

        final before = tester.getRect(footer);
        expect(before.bottom, lessThanOrEqualTo(780));
        expect(before.width, greaterThan(300));

        // Las secciones se desplazan; el pie, no.
        await tester.drag(find.text('SECCIÓN 1'), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.getRect(footer), before);
        expect(find.text('SECCIÓN 0').hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
        expect(Theme.of(tester.element(footer)).brightness, brightness);
      });

      testWidgets('en horizontal, por encima de la barra de gestos', (
        tester,
      ) async {
        await openSheet(
          tester,
          size: const Size(780, 360),
          brightness: brightness,
          bottomInset: 24,
          sections: 8,
        );
        expect(tester.takeException(), isNull);

        final rect = tester.getRect(footer);
        expect(rect.bottom, lessThanOrEqualTo(360 - 24));
        expect(rect.top, greaterThan(0));
      });
    });
  }
}
