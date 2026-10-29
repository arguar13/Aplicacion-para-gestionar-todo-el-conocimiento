import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/app.dart';
import 'package:sinapsis/app/repair_stored_text.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

import '../support/item_rows.dart';
import '../support/library_harness.dart';
import '../support/vault_test_doubles.dart';

/// Con la app entera montada: los títulos guardados con las letras rotas se
/// arreglan apenas se abre la bóveda, y antes no se toca la base (F43, M7).
void main() {
  const title = 'Declaración de los Derechos del Hombre';
  final broken = latin1.decode(utf8.encode(title));

  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    await insertItemRows(harness.database, id: 'pdf', title: broken);
  });

  FakeVaultLocalDataSource vault() =>
      harness.container.read(vaultLocalDataSourceProvider)
          as FakeVaultLocalDataSource;

  Future<String> storedTitle() async => (await (harness.database.select(
    harness.database.knowledgeEntries,
  )..where((e) => e.id.equals('pdf'))).getSingle()).title;

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('con la bóveda abierta, el título vuelve a estar bien escrito', (
    tester,
  ) async {
    await vault().writeOpenBoot(kTestDeviceBoot);

    await openApp(tester);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(storedTitle), title);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool(utf8MojibakeRepairDoneKey), isTrue);
  });

  testWidgets('con la bóveda cerrada no toca la base: espera a que se abra', (
    tester,
  ) async {
    await vault().writeOpenBoot('un-arranque-anterior');

    await openApp(tester);

    expect(await tester.runAsync(storedTitle), broken);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool(utf8MojibakeRepairDoneKey), isNull);
  });
}
