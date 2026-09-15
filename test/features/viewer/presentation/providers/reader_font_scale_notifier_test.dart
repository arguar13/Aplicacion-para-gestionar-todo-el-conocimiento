import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/features/viewer/presentation/providers/reader_font_scale_notifier.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('arranca en 1.0 si nunca se guardó nada', () {
    final notifier = ReaderFontScaleNotifier(prefs: prefs);
    expect(notifier.state, 1.0);
  });

  test('aumentar y disminuir cambian el estado de a pasos', () async {
    final notifier = ReaderFontScaleNotifier(prefs: prefs);

    await notifier.increase();
    expect(notifier.state, closeTo(1.1, 0.001));

    await notifier.decrease();
    await notifier.decrease();
    expect(notifier.state, closeTo(0.9, 0.001));
  });

  test('no pasa del techo ni del piso', () async {
    final notifier = ReaderFontScaleNotifier(prefs: prefs);

    for (var i = 0; i < 20; i++) {
      await notifier.increase();
    }
    expect(notifier.state, ReaderFontScaleNotifier.max);

    for (var i = 0; i < 20; i++) {
      await notifier.decrease();
    }
    expect(notifier.state, ReaderFontScaleNotifier.min);
  });

  test('el valor elegido se recuerda entre instancias', () async {
    final first = ReaderFontScaleNotifier(prefs: prefs);
    await first.increase();
    await first.increase();

    final second = ReaderFontScaleNotifier(prefs: prefs);
    expect(second.state, closeTo(1.2, 0.001));
  });
}
