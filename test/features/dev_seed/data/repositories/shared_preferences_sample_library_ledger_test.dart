import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/dev_seed/data/repositories/shared_preferences_sample_library_ledger.dart';

void main() {
  test('recuerda lo cargado entre una instancia y otra, sin repetir', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final ledger = SharedPreferencesSampleLibraryLedger(prefs);
    expect(ledger.loadedIds(), isEmpty);

    await ledger.markLoaded('web-roma');
    await ledger.markLoaded('nota-nicea');
    await ledger.markLoaded('web-roma');

    expect(SharedPreferencesSampleLibraryLedger(prefs).loadedIds(), {
      'web-roma',
      'nota-nicea',
    });
  });
}
