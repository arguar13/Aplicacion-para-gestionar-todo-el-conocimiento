import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/viewer/presentation/widgets/embedded_file_viewer.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

import '../../../../core/design/overlay_control_colors_test.dart'
    show contrastOver;

/// Los dos botones del visor embebido se leen sobre cualquier original (F46,
/// paso 5i): en el emulador, «Ver la página» era blanco sobre negro al 40 %
/// encima de una página blanca, unos 2,9 a 1.
void main() {
  final bigButton = find.byKey(const Key('embedded-viewer-read-as-book'));
  final cornerButton = find.byKey(const Key('embedded-viewer-expand'));

  /// El marco con el original de un solo color, [under], y el botón grande
  /// con [label] o, sin él, el de la esquina.
  Future<void> pump(
    WidgetTester tester, {
    required ThemeData theme,
    required Color under,
    String? label,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EmbeddedViewerFrame(
            onExpand: () {},
            bigButtonLabel: label,
            child: ColoredBox(color: under),
          ),
        ),
      ),
    );
  }

  final themes = <String, ThemeData>{
    'claro': AppThemeChoice.light.theme,
    'oscuro': AppThemeChoice.dark.darkTheme,
    'sepia': AppThemeChoice.sepia.theme,
    'noche': AppThemeChoice.night.theme,
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    for (final under in [Colors.white, Colors.black]) {
      final where = under == Colors.white
          ? 'una página blanca'
          : 'una foto negra';

      testWidgets('el botón grande se lee con al menos 4,5 a 1 sobre $where, '
          'en el tema $name', (tester) async {
        await pump(tester, theme: theme, under: under, label: 'Ver la página');

        final background = tester.widget<Material>(bigButton).color!;
        final text = tester.widget<Text>(find.text('Ver la página'));
        final icon = tester.widget<Icon>(
          find.descendant(
            of: bigButton,
            matching: find.byIcon(Icons.open_in_full),
          ),
        );
        expect(
          contrastOver(text.style!.color!, background, under),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastOver(icon.color!, background, under),
          greaterThanOrEqualTo(4.5),
        );
        // Sigue dejando ver el original debajo.
        expect(background.a, lessThan(1));
      });

      testWidgets('el de la esquina, también, sobre $where, en el tema '
          '$name', (tester) async {
        await pump(tester, theme: theme, under: under);

        final box = tester.widget<DecoratedBox>(cornerButton);
        final background = (box.decoration as BoxDecoration).color!;
        final button = tester.widget<IconButton>(
          find.descendant(of: cornerButton, matching: find.byType(IconButton)),
        );
        expect(
          contrastOver(button.color!, background, under),
          greaterThanOrEqualTo(4.5),
        );
        expect(background.a, lessThan(1));
      });
    }
  }
}
