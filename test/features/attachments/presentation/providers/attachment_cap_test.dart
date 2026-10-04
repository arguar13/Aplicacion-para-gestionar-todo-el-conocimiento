import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/attachments/presentation/providers/attachment_cap.dart';

void main() {
  const megabyte = 1024 * 1024;

  test('de fábrica, 500 MB (decisión E)', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AttachmentCapNotifier(
      prefs: await SharedPreferences.getInstance(),
    );
    expect(notifier.state, 500 * megabyte);
    expect(AttachmentCapNotifier.defaultBytes, 500 * megabyte);
  });

  test('se cambia y se recuerda', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await AttachmentCapNotifier(prefs: prefs).setBytes(200 * megabyte);

    expect(AttachmentCapNotifier(prefs: prefs).state, 200 * megabyte);
  });

  test('solo los topes que se ofrecen', () async {
    SharedPreferences.setMockInitialValues({
      'attachments_max_bytes_per_item': 7,
    });
    final notifier = AttachmentCapNotifier(
      prefs: await SharedPreferences.getInstance(),
    );
    // Un valor raro guardado vuelve al de fábrica.
    expect(notifier.state, AttachmentCapNotifier.defaultBytes);
    await expectLater(notifier.setBytes(12345), throwsArgumentError);
  });
}
