import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/app_theme_choice.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/study/presentation/study_highlighting.dart';

/// «Apariencia» del marco de lectura (F47, paso 1): una sola para todos los
/// lectores, guardada entre reinicios, con cinco letras que viajan con la app.
void main() {
  Future<ReadingAppearanceNotifier> notifier([
    Map<String, Object> stored = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(stored);
    return ReadingAppearanceNotifier(
      prefs: await SharedPreferences.getInstance(),
    );
  }

  test('de entrada: Lora, al 100 %, el amarillo de siempre, el modo de la '
      'app, la página original y la fila de IA abierta', () async {
    final state = (await notifier()).state;
    expect(state.font, ReadingFont.lora);
    expect(state.font.serif, isTrue);
    expect(state.scale, 1);
    expect(state.highlight.color, RenderedMarkdown.playingColor);
    expect(state.mode, ReadingMode.system);
    expect(state.paper, ReadingPaper.original);
    expect(state.aiRowOpen, isTrue);
  });

  test('el tamaño que ya se había elegido con A− A+ se conserva', () async {
    final state = (await notifier({'reader_font_scale': 1.3})).state;
    expect(state.scale, 1.3);
  });

  test('lo guardado se lee igual al volver a abrir; lo desconocido, de '
      'entrada', () async {
    final first = await notifier();
    await first.setFont(ReadingFont.nunito);
    await first.setHighlight(ReadingHighlight.peach);
    await first.setMode(ReadingMode.sepia);
    await first.setPaper(ReadingPaper.dark);
    await first.setAiRowOpen(open: false);
    await first.setScale(1.2);
    final prefs = await SharedPreferences.getInstance();
    final second = ReadingAppearanceNotifier(prefs: prefs);
    expect(second.state, first.state);

    final broken = await notifier({
      ReadingAppearanceNotifier.fontKey: 'comic',
      ReadingAppearanceNotifier.modeKey: 'neón',
      ReadingAppearanceNotifier.highlightKey: 'fucsia',
      ReadingAppearanceNotifier.paperKey: 'papiro',
      ReadingAppearanceNotifier.scaleKey: 9.0,
    });
    expect(broken.state.font, ReadingFont.lora);
    expect(broken.state.mode, ReadingMode.system);
    expect(broken.state.highlight, ReadingHighlight.yellow);
    expect(broken.state.paper, ReadingPaper.original);
    expect(broken.state.scale, ReadingAppearanceNotifier.maxScale);
  });

  test('el tamaño va de a 10 %, entre 80 % y 160 %', () async {
    final appearance = await notifier();
    expect(ReadingAppearanceNotifier.scaleStops, 9);
    await appearance.setScale(1.04);
    expect(appearance.state.scale, 1.0);
    await appearance.setScale(1.06);
    expect(appearance.state.scale, 1.1);
    for (var i = 0; i < 12; i++) {
      await appearance.increase();
    }
    expect(appearance.state.scale, 1.6);
    for (var i = 0; i < 12; i++) {
      await appearance.decrease();
    }
    expect(appearance.state.scale, 0.8);
  });

  test('la letra del texto: la elegida, a su tamaño, con interlineado de '
      'libro; los títulos, con la misma letra', () {
    final theme = AppThemeChoice.light.theme;
    const appearance = ReadingAppearance(
      font: ReadingFont.atkinson,
      scale: 1.5,
    );
    final body = appearance.bodyStyle(theme);
    expect(body.fontFamily, 'Atkinson Hyperlegible Next');
    // El tamaño de base del tema; fuera de una pantalla, sin la geometría de
    // la tipografía, el de 16.
    final base = theme.textTheme.bodyLarge?.fontSize ?? 16;
    expect(body.fontSize, closeTo(base * 1.06 * 1.5, 0.01));
    expect(body.height, 1.65);
    expect(appearance.titleStyle(theme).fontFamily, body.fontFamily);
  });

  test(
    'el modo: el de la app, o el claro, el oscuro o el Sepia de Ajustes',
    () {
      final app = AppThemeChoice.forest.theme;
      expect(ReadingMode.system.themeOver(app), same(app));
      expect(ReadingMode.light.themeOver(app).brightness, Brightness.light);
      expect(ReadingMode.dark.themeOver(app).brightness, Brightness.dark);
      expect(
        ReadingMode.sepia.themeOver(app).colorScheme.surface,
        AppThemeChoice.sepia.theme.colorScheme.surface,
      );
    },
  );

  test('ningún color de lo que suena se confunde con los de estudiar, y '
      'todos se leen con la letra oscura', () {
    for (final brightness in Brightness.values) {
      final palette = StudyPalette.of(brightness);
      for (final highlight in ReadingHighlight.values) {
        expect(
          highlight.color,
          isNot(anyOf(palette.summary, palette.synthesis, palette.keyword)),
        );
        final ink = StudyPalette.ink.withValues(alpha: 1);
        final lum = highlight.color.computeLuminance();
        final contrast = (lum + 0.05) / (ink.computeLuminance() + 0.05);
        expect(contrast, greaterThan(7), reason: highlight.name);
      }
    }
  });

  test('la página oscura invierte la luz sin cambiar el tono: el blanco da '
      'negro, el negro blanco, y el rosa sigue más rojo que verde', () {
    Color apply(List<double> m, Color c) {
      double ch(int row) =>
          (m[row * 5] * c.r * 255 +
                  m[row * 5 + 1] * c.g * 255 +
                  m[row * 5 + 2] * c.b * 255 +
                  m[row * 5 + 4])
              .clamp(0, 255);
      return Color.fromARGB(255, ch(0).round(), ch(1).round(), ch(2).round());
    }

    final dark = ReadingPaper.dark.matrix!;
    expect(apply(dark, Colors.white), const Color(0xFF000000));
    expect(apply(dark, Colors.black), const Color(0xFFFFFFFF));
    final pink = apply(dark, StudyPalette.of(Brightness.light).keyword);
    expect(pink.r, greaterThan(pink.g));
    expect(ReadingPaper.original.matrix, isNull);
    expect(ReadingPaper.sepia.matrix, hasLength(20));
  });

  group('las cinco letras viajan con la app', () {
    /// Las familias de pubspec.yaml con sus pesos.
    Map<String, Set<int>> declared() {
      final families = <String, Set<int>>{};
      String? family;
      for (final line in File('pubspec.yaml').readAsLinesSync()) {
        final name = RegExp(r'^\s+- family: (.+)$').firstMatch(line);
        if (name != null) {
          family = name.group(1)!.trim();
          families[family] = {};
          continue;
        }
        final weight = RegExp(r'^\s+weight: (\d+)$').firstMatch(line);
        if (weight != null && family != null) {
          families[family]!.add(int.parse(weight.group(1)!));
        }
      }
      return families;
    }

    test('cada una declarada en pubspec.yaml con el peso del texto y el de '
        'la negrita', () {
      final families = declared();
      expect(ReadingFont.values, hasLength(5));
      for (final font in ReadingFont.values) {
        final weights = ReadingFont.declaredWeights[font.family]!;
        for (final weight in weights) {
          expect(families[font.family], contains(weight), reason: font.family);
        }
      }
    });

    test('la que se sumó, con su archivo y su licencia OFL al lado', () {
      for (final name in [
        'AtkinsonHyperlegibleNext-Variable.ttf',
        'AtkinsonHyperlegibleNext-Italic-Variable.ttf',
      ]) {
        expect(File('assets/fonts/$name').existsSync(), isTrue, reason: name);
      }
      expect(
        File(
          'assets/fonts/AtkinsonHyperlegibleNext-OFL.txt',
        ).readAsStringSync(),
        contains('SIL Open Font License, Version 1.1'),
      );
    });
  });
}
