import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/core/design/widgets/snack_bar_footprint.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que flota abajo se corre arriba del aviso (F45, paso 1, decisión C):
/// el aviso publica lo que ocupa en el anfitrión de la app y
/// `LiftAboveSnackBar` sube a lo suyo, como un botón flotante de Android. Es
/// el mecanismo del lector en voz alta, y el de cualquier cosa que flote
/// encima de las pantallas.
void main() {
  const phone = Size(360, 760);
  const floating = Key('floating');
  final close = find.byTooltip('Cerrar aviso');

  /// La app con algo que flota abajo a la derecha, parado a [bottom] del
  /// borde, por encima de las pantallas: como el lector flotante.
  Future<void> pump(WidgetTester tester, {double bottom = 16}) async {
    tester.view
      ..physicalSize = phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: SnackBarFootprintHost(
            child: Stack(
              children: [
                child!,
                Positioned(
                  right: 16,
                  bottom: bottom,
                  child: LiftAboveSnackBar(
                    bottom: bottom,
                    child: FloatingActionButton(
                      key: floating,
                      onPressed: () {},
                      child: const Icon(Icons.play_arrow),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showAppSnackBar(
                  AppSnackBar(
                    content: const Text('Movido a la papelera'),
                    action: SnackBarAction(label: 'Deshacer', onPressed: () {}),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect card(WidgetTester tester) => tester.getRect(
    find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first,
  );
  double floatingBottom(WidgetTester tester) =>
      tester.getRect(find.byKey(floating)).bottom;

  testWidgets('se corre arriba del aviso, sin tapar su ✕, y vuelve cuando se '
      'va', (tester) async {
    await pump(tester);
    expect(floatingBottom(tester), phone.height - 16);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(floatingBottom(tester), closeTo(card(tester).top - 12, 0.5));
    final closeRect = tester.getRect(close);
    expect(tester.getRect(find.byKey(floating)).overlaps(closeRect), isFalse);

    // La ✕ se puede tocar: no hay nada encima.
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(floatingBottom(tester), phone.height - 16);
  });

  testWidgets('sube y baja con la animación del aviso', (tester) async {
    await pump(tester);
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final halfway = floatingBottom(tester);
    expect(halfway, lessThan(phone.height - 16));

    await tester.pumpAndSettle();
    final up = floatingBottom(tester);
    expect(up, lessThan(halfway));

    // Al irse, espera a que el aviso se desvanezca y después baja.
    await tester.tap(close);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(floatingBottom(tester), up);
    await tester.pump(const Duration(milliseconds: 120));
    expect(floatingBottom(tester), greaterThan(up));
    expect(floatingBottom(tester), lessThan(phone.height - 16));

    await tester.pumpAndSettle();
    expect(floatingBottom(tester), phone.height - 16);
  });

  for (final (name, features) in [
    (
      'con «sin animaciones»',
      const FakeAccessibilityFeatures(disableAnimations: true),
    ),
    // Con el lector de pantalla, Material muestra el aviso sin animación,
    // aunque la suya siga corriendo por debajo.
    (
      'con el lector de pantalla',
      const FakeAccessibilityFeatures(accessibleNavigation: true),
    ),
  ]) {
    testWidgets('$name, salta arriba y vuelve de una vez', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = features;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester);
      const base = 760.0 - 16;

      /// Dónde estuvo cuadro por cuadro, hasta que todo se quedó quieto.
      Future<Set<double>> watch() async {
        final seen = <double>{};
        do {
          await tester.pump(const Duration(milliseconds: 4));
          seen.add(floatingBottom(tester));
        } while (tester.binding.hasScheduledFrame);
        return seen;
      }

      await tester.tap(find.text('abrir'));
      final rising = await watch();
      final up = floatingBottom(tester);
      expect(up, closeTo(card(tester).top - 12, 0.5));
      // Nunca a mitad de camino: abajo, mientras el aviso se arma, y arriba.
      expect(rising.difference({base, up}), isEmpty);

      await tester.tap(close);
      final falling = await watch();
      expect(find.byType(SnackBar), findsNothing);
      expect(floatingBottom(tester), base);
      expect(falling.difference({base, up}), isEmpty);
    });
  }

  testWidgets('si se apagan las animaciones con el aviso a la vista, sigue '
      'arriba y vuelve igual', (tester) async {
    await pump(tester);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final up = floatingBottom(tester);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    expect(floatingBottom(tester), up);

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(floatingBottom(tester), phone.height - 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lo que ya está por encima del aviso no se mueve', (
    tester,
  ) async {
    await pump(tester, bottom: 400);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(floatingBottom(tester), phone.height - 400);
  });

  testWidgets('se toca donde se ve: el toque también se corre', (tester) async {
    await pump(tester);
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final button = find.byKey(floating);
    final hit = tester.hitTestOnBinding(tester.getCenter(button));
    expect(
      hit.path.any((entry) => entry.target == tester.renderObject(button)),
      isTrue,
    );
  });

  testWidgets('sin anfitrión, el aviso no publica nada y nada se rompe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showAppSnackBar(AppSnackBar(content: const Text('Copiado'))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Copiado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('las huellas', () {
    test('la más alta es la que se esquiva, y se va con su dueño', () {
      final footprints = SnackBarFootprints();
      addTearDown(footprints.dispose);
      var notified = 0;
      footprints.addListener(() => notified++);
      const low = SnackBarFootprint(
        height: 80,
        presence: kAlwaysCompleteAnimation,
      );
      const high = SnackBarFootprint(
        height: 140,
        presence: kAlwaysCompleteAnimation,
      );
      final a = Object();
      final b = Object();

      footprints.report(a, low);
      expect(footprints.value, low);
      footprints.report(b, high);
      expect(footprints.value, high);
      // Lo mismo otra vez no avisa a nadie.
      footprints.report(b, high);
      expect(notified, 2);

      footprints.withdraw(b);
      expect(footprints.value, low);
      footprints.withdraw(a);
      expect(footprints.value, isNull);
      expect(notified, 4);
    });
  });
}
