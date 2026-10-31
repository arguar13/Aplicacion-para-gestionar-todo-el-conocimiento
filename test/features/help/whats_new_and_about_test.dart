import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/help/presentation/bundled_font_licenses.dart';
import 'package:sinapsis/features/help/presentation/help_document.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/features/help/presentation/screens/about_screen.dart';
import 'package:sinapsis/features/help/presentation/screens/whats_new_screen.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import 'help_test_app.dart';

/// «Novedades» y «Acerca de» (F47, paso 7), a 360 dp con la letra al doble,
/// en claro y en oscuro.
void main() {
  final es = AppLocalizationsEs();
  final whatsNew = HelpDocument.parse(File(kWhatsNewAsset).readAsStringSync());
  const version = AppVersion(name: 'Sinapsis', version: '0.1.0', build: '7');

  for (final brightness in Brightness.values) {
    group('en ${brightness.name}', () {
      testWidgets('las novedades: la versión de ahora arriba, y la etapa de '
          'ahora primero', (tester) async {
        await pumpHelpScreen(
          tester,
          const WhatsNewScreen(),
          brightness: brightness,
          overrides: [
            whatsNewProvider.overrideWith((ref) async => whatsNew),
            appVersionProvider.overrideWith((ref) async => version),
          ],
        );

        expect(find.text(es.f47P7WhatsNew), findsOneWidget);
        // La versión de ahora, lo primero de todo.
        final card = find.byKey(const Key('whats-new-version'));
        expect(
          find.descendant(
            of: card,
            matching: find.text(es.f47P7WhatsNewCurrentVersion('0.1.0', '7')),
          ),
          findsOneWidget,
        );
        expect(tester.getTopLeft(card).dy, lessThan(120));
        // Y la etapa de ahora, la primera.
        final firstStage = find.text(whatsNew.chapters.first.title);
        await tester.scrollUntilVisible(
          firstStage,
          300,
          scrollable: find.descendant(
            of: find.byKey(const Key('whats-new-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(firstStage, findsOneWidget);
        expect(find.text(whatsNew.chapters[1].title), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('«Acerca de»: el nombre, la versión y la compilación', (
        tester,
      ) async {
        await pumpHelpScreen(
          tester,
          const AboutScreen(),
          brightness: brightness,
          overrides: [appVersionProvider.overrideWith((ref) async => version)],
        );

        expect(find.text('Sinapsis'), findsOneWidget);
        expect(find.text(es.f47P7AboutVersion('0.1.0', '7')), findsOneWidget);
        expect(find.text(es.f47P7AboutDescription), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('about-licenses')),
          300,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('about-licenses')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('las licencias', () {
    setUp(() {
      LicenseRegistry.reset();
      debugResetBundledFontLicenses();
    });

    test(
      'las de las letras empaquetadas, una vez aunque se pida dos',
      () async {
        registerBundledFontLicenses();
        registerBundledFontLicenses();

        final entries = await LicenseRegistry.licenses.toList();
        expect(
          entries.expand((e) => e.packages).toList(),
          kBundledFontLicenses.keys.toList(),
        );
        for (final entry in entries) {
          final text = entry.paragraphs.map((p) => p.text).join(' ');
          expect(text, contains('SIL Open Font License'));
        }
      },
    );

    testWidgets('la página de Flutter, con la versión y las letras', (
      tester,
    ) async {
      // Las letras se leen del disco: en una prueba de pantalla, leer de
      // verdad el paquete de la app no termina sin un reloj real.
      registerBundledFontLicenses(bundle: _DiskBundle());
      await pumpHelpScreen(
        tester,
        const AboutScreen(),
        overrides: [appVersionProvider.overrideWith((ref) async => version)],
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('about-licenses')),
        300,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about-licenses')));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text(es.f47P7AboutVersion('0.1.0', '7')), findsWidgets);
      expect(find.text('Inter'), findsOneWidget);
    });
  });

  test('censo: cada letra empaquetada tiene su licencia, y cada licencia '
      'está empaquetada', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final families =
        RegExp(
            r'^    - family: (.+)$',
            multiLine: true,
          ).allMatches(pubspec).map((m) => m.group(1)!.trim()).toSet()
          // «Inter Creation» es el mismo archivo de Inter con más pesos.
          ..remove('Inter Creation');
    expect(kBundledFontLicenses.keys.toSet(), families);

    final files = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.txt'))
        .map((name) => 'assets/fonts/$name')
        .toSet();
    expect(kBundledFontLicenses.values.toSet(), files);
    for (final path in files) {
      expect(pubspec, contains('    - $path'), reason: path);
    }
  });
}

/// Lo empaquetado, leído del disco y al instante.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(File(key).readAsStringSync());
}
