import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/design/app_theme.dart';
import 'package:sinapsis/features/home_widgets/data/android_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';

/// Censos de los widgets de Android (F47, paso 7): lo que vive de los dos
/// lados —Dart y `android/`— tiene que decir lo mismo en los dos.
void main() {
  const res = 'android/app/src/main/res';
  const kotlin = 'android/app/src/main/kotlin/app/sinapsis';
  String read(String path) => File(path).readAsStringSync();

  Map<String, Color> colors(String path) => {
    for (final match in RegExp(
      '<color name="(home_widget_[a-z_]+)">#([0-9A-Fa-f]{8})</color>',
    ).allMatches(read(path)))
      match.group(1)!: Color(int.parse(match.group(2)!, radix: 16)),
  };

  Map<String, Color> roles(ThemeData theme) {
    final scheme = theme.colorScheme;
    return {
      'home_widget_surface': scheme.surface,
      'home_widget_on_surface': scheme.onSurface,
      'home_widget_on_surface_variant': scheme.onSurfaceVariant,
      'home_widget_primary': scheme.primary,
      'home_widget_primary_container': scheme.primaryContainer,
      'home_widget_on_primary_container': scheme.onPrimaryContainer,
    };
  }

  test('los colores, los del tema claro de la app', () {
    expect(
      colors('$res/values/home_widget_colors.xml'),
      roles(AppTheme.lightTheme),
    );
  });

  test('y en modo oscuro, los del tema oscuro', () {
    expect(
      colors('$res/values-night/home_widget_colors.xml'),
      roles(AppTheme.darkTheme),
    );
  });

  test('cada widget de Dart tiene su clase, su receptor y su diseño', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    final providers = read('$kotlin/HomeWidgetProviders.kt');
    final widgets = read('$kotlin/HomeWidgets.kt');
    for (final kind in HomeWidgetKind.values) {
      final className = kind.androidProvider.split('.').last;
      expect(kind.androidProvider, 'app.sinapsis.$className');
      expect(providers, contains('class $className : HomeWidgetProvider()'));
      expect(manifest, contains('android:name=".$className"'));
      // El nombre con que se lo toca, el mismo de los dos lados.
      expect(widgets, contains('= "${kind.name}"'));
    }
    for (final info in [
      'home_widget_due_today_info',
      'home_widget_quick_capture_info',
      'home_widget_continue_listening_info',
    ]) {
      expect(manifest, contains('@xml/$info'));
      expect(File('$res/xml/$info.xml').existsSync(), isTrue, reason: info);
    }
  });

  test('las claves de lo que muestran son las mismas en Kotlin', () {
    final widgets = read('$kotlin/HomeWidgets.kt');
    for (final key in [
      kDueTodayCountKey,
      kDueTodayValidUntilKey,
      kContinueListeningTitleKey,
      kContinueListeningShowLockedKey,
      kContinueListeningOpenBootKey,
    ]) {
      expect(widgets, contains('"$key"'), reason: key);
    }
  });

  test('«abierta en este encendido» se decide con un solo criterio, el de '
      'la bóveda, en Dart y en Kotlin (paso 7a-bis)', () {
    // El contador de arranques se lee en un solo lugar...
    final readers = [
      for (final file in Directory(kotlin).listSync().whereType<File>())
        if (file.readAsStringSync().contains('Settings.Global.BOOT_COUNT'))
          file.uri.pathSegments.last,
    ];
    expect(readers, ['DeviceBoot.kt']);
    // ...que da el encendido a la bóveda, por el canal que lee Dart...
    expect(read('$kotlin/SinapsisEngine.kt'), contains('DeviceBoot.count('));
    // ...y al widget, que lo compara con el que le dejó Dart.
    final widgets = read('$kotlin/HomeWidgets.kt');
    expect(widgets, contains('currentBoot = DeviceBoot.id(context)'));
    // La regla de Kotlin tiene los mismos tres casos que la de Dart.
    for (final shown in ContinueListeningShown.values) {
      expect(
        widgets,
        contains('ContinueListeningShown.${shown.name.toUpperCase()}'),
      );
    }
  });

  test('«Seguir escuchando» se vuelve a dibujar al arrancar el teléfono '
      '(paso 7a-bis)', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    final receiver = RegExp(
      r'<receiver\s+android:name="\.ContinueListeningWidget"[\s\S]*?</receiver>',
    ).firstMatch(manifest)!.group(0)!;
    expect(receiver, contains('android.intent.action.BOOT_COMPLETED'));
    expect(
      read('$kotlin/HomeWidgetProviders.kt'),
      contains('intent.action != Intent.ACTION_BOOT_COMPLETED'),
    );
  });

  test('cada texto de los widgets está en castellano y en inglés', () {
    Set<String> names(String path) => RegExp(
      '<(?:string|plurals) name="([a-z_]+)"',
    ).allMatches(read(path)).map((m) => m.group(1)!).toSet();
    final es = names('$res/values/home_widget_strings.xml');
    expect(es, isNotEmpty);
    expect(names('$res/values-en/home_widget_strings.xml'), es);

    final used =
        RegExp(
              r'@string/(home_widget_[a-z_]+)|R\.(?:string|plurals)\.(home_widget_[a-z_]+)',
            )
            .allMatches(
              [
                read('android/app/src/main/AndroidManifest.xml'),
                read('$kotlin/HomeWidgets.kt'),
                for (final file in Directory(
                  '$res/layout',
                ).listSync().whereType<File>())
                  file.readAsStringSync(),
                for (final file in Directory(
                  '$res/xml',
                ).listSync().whereType<File>())
                  file.readAsStringSync(),
              ].join('\n'),
            )
            .map((m) => m.group(1) ?? m.group(2)!)
            .toSet();
    expect(es, containsAll(used));
  });
}
