import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_settings_notifier.dart';

void main() {
  test('arranca con todo prendido', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AiOrganizeSettingsNotifier(
      prefs: await SharedPreferences.getInstance(),
    );

    for (final toggle in AiOrganizeToggle.values) {
      expect(toggle.valueIn(notifier.state), isTrue, reason: toggle.name);
    }
  });

  test('cada interruptor se guarda y se recuerda solo, sin tocar los '
      'demás', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = AiOrganizeSettingsNotifier(prefs: prefs);

    for (final toggle in AiOrganizeToggle.values) {
      await notifier.set(toggle, on: false);
      final reread = AiOrganizeSettingsNotifier(prefs: prefs).state;
      expect(toggle.valueIn(reread), isFalse, reason: toggle.name);
      await notifier.set(toggle, on: true);
    }

    await notifier.set(AiOrganizeToggle.flashcards, on: false);
    final reread = AiOrganizeSettingsNotifier(prefs: prefs).state;
    expect(reread, const AiOrganizeSettings(flashcards: false));
  });
}
