import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/features/creations/design/creation_controls.dart';

/// Los controles de las hojas de lo creado (F43): los segmentados con ✓ y la
/// ✕ redonda, en un teléfono angosto y con letra grande.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 360,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view
      ..physicalSize = Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );
  }

  Widget segmented(ValueChanged<String> onChanged, {String selected = 'b'}) =>
      CreationSegmented<String>(
        keyPrefix: 'seg',
        selected: selected,
        onChanged: onChanged,
        segments: const [
          CreationSegment(value: 'a', label: 'Fundido'),
          CreationSegment(value: 'b', label: 'Deslizar'),
          CreationSegment(value: 'c', label: 'Zoom suave'),
          CreationSegment(value: 'd', label: 'Ninguna'),
        ],
      );

  testWidgets('en ancho, las opciones van unidas; la elegida con ✓', (
    tester,
  ) async {
    await pump(tester, segmented((_) {}), width: 900);
    expect(find.byType(Wrap), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
    final check = tester.getCenter(find.byIcon(Icons.check));
    final b = tester.getRect(find.byKey(const ValueKey('seg-b')));
    expect(b.contains(check), isTrue);
  });

  testWidgets('en un teléfono con letra grande bajan de renglón sin cortar', (
    tester,
  ) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      await pump(tester, segmented((_) {}), textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.byType(Wrap), findsOneWidget);
      for (final label in ['Fundido', 'Deslizar', 'Zoom suave', 'Ninguna']) {
        expect(find.text(label), findsOneWidget);
      }
    }
  });

  testWidgets('tocar una opción la elige', (tester) async {
    String? chosen;
    await pump(tester, segmented((v) => chosen = v));
    await tester.tap(find.byKey(const ValueKey('seg-c')));
    expect(chosen, 'c');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('seg-b'))),
      containsSemantics(isSelected: true),
    );
  });

  testWidgets('la ✕ redonda cierra la hoja', (tester) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => const Align(
              alignment: Alignment.topRight,
              child: CreationCloseButton(tooltip: 'Cerrar'),
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cerrar'), findsNothing);
  });

  testWidgets('el rótulo de sección', (tester) async {
    await pump(tester, const CreationSectionLabel('Paleta'));
    expect(find.text('Paleta'), findsOneWidget);
  });
}
