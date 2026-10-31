import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/home_widgets/data/android_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/data/null_home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';

/// Los widgets en Android (F47, paso 7), con `home_widget` y el canal de los
/// toques reemplazados por dobles: lo que se guarda, a quién se le pide
/// dibujarse y qué widget se tocó.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const homeWidget = MethodChannel('home_widget');
  const taps = MethodChannel('app.sinapsis/home_widgets');

  late List<MethodCall> stored;
  late List<MethodCall> tapsCalls;
  String? pending;
  bool? pinSupported;

  setUp(() {
    stored = [];
    tapsCalls = [];
    pending = null;
    pinSupported = true;
    messenger
      ..setMockMethodCallHandler(homeWidget, (call) async {
        stored.add(call);
        return switch (call.method) {
          'isRequestPinWidgetSupported' => pinSupported,
          'getWidgetData' => null,
          _ => true,
        };
      })
      ..setMockMethodCallHandler(taps, (call) async {
        tapsCalls.add(call);
        return call.method == 'takePendingOpen' ? pending : null;
      });
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(homeWidget, null)
      ..setMockMethodCallHandler(taps, null);
  });

  Map<String, Object?> saved(String id) => stored
      .where((c) => c.method == 'saveWidgetData')
      .map((c) => Map<String, Object?>.from(c.arguments as Map))
      .lastWhere((args) => args['id'] == id);

  List<String?> redrawn() => [
    for (final call in stored)
      if (call.method == 'updateWidget')
        (call.arguments as Map)['qualifiedAndroidName'] as String?,
  ];

  test(
    '«Para hoy» guarda la cifra y hasta cuándo vale, y se redibuja',
    () async {
      final widgets = AndroidHomeScreenWidgets();
      final until = DateTime(2026, 10, 31, 4);

      await widgets.showDueToday(DueToday(count: 12, validUntil: until));

      expect(saved(kDueTodayCountKey)['data'], 12);
      expect(
        saved(kDueTodayValidUntilKey)['data'],
        until.millisecondsSinceEpoch,
      );
      expect(redrawn(), ['app.sinapsis.DueTodayWidget']);
    },
  );

  test('«Seguir escuchando» guarda solo el título: la dirección no sale de '
      'la app', () async {
    final widgets = AndroidHomeScreenWidgets();

    await widgets.showContinueListening(
      const ContinueListening(title: 'El Imperio', location: '/processed/p1'),
    );

    expect(saved(kContinueListeningTitleKey)['data'], 'El Imperio');
    expect(
      stored.where((c) => c.toString().contains('/processed/p1')),
      isEmpty,
    );
    expect(redrawn(), ['app.sinapsis.ContinueListeningWidget']);
  });

  test('sin nada escuchado, borra el título', () async {
    final widgets = AndroidHomeScreenWidgets();

    await widgets.showContinueListening(null);

    expect(saved(kContinueListeningTitleKey)['data'], isNull);
  });

  test('agregar le pide al sistema el widget de cada clase', () async {
    final widgets = AndroidHomeScreenWidgets();

    expect(await widgets.canAddFromApp(), isTrue);
    pinSupported = null;
    expect(await widgets.canAddFromApp(), isFalse);

    for (final kind in HomeWidgetKind.values) {
      await widgets.add(kind);
    }
    expect(
      [
        for (final call in stored)
          if (call.method == 'requestPinWidget')
            (call.arguments as Map)['qualifiedAndroidName'],
      ],
      [
        'app.sinapsis.DueTodayWidget',
        'app.sinapsis.QuickCaptureWidget',
        'app.sinapsis.ContinueListeningWidget',
      ],
    );
  });

  test('el toque que abrió la app se recoge una vez, con su widget', () async {
    final widgets = AndroidHomeScreenWidgets();

    pending = 'quickCapture';
    expect(await widgets.takePendingOpen(), HomeWidgetKind.quickCapture);
    pending = null;
    expect(await widgets.takePendingOpen(), isNull);
    pending = 'otraCosa';
    expect(await widgets.takePendingOpen(), isNull);
  });

  test('un toque con la app andando llega por el canal', () async {
    final widgets = AndroidHomeScreenWidgets();
    final opened = <HomeWidgetKind>[];
    final subscription = widgets.openRequests.listen(opened.add);

    for (final name in ['dueToday', 'continueListening', 'otraCosa']) {
      await messenger.handlePlatformMessage(
        taps.name,
        taps.codec.encodeMethodCall(MethodCall('open', name)),
        (_) {},
      );
    }
    await Future<void>.delayed(Duration.zero);

    expect(opened, [HomeWidgetKind.dueToday, HomeWidgetKind.continueListening]);
    await subscription.cancel();
  });

  test('fuera de Android no hay widgets y nada hace nada', () async {
    const widgets = NullHomeScreenWidgets();

    expect(widgets.isSupported, isFalse);
    expect(await widgets.canAddFromApp(), isFalse);
    expect(await widgets.takePendingOpen(), isNull);
    await widgets.showDueToday(DueToday(count: 1, validUntil: DateTime(2026)));
    await widgets.showContinueListening(null);
    await widgets.add(HomeWidgetKind.dueToday);
    expect(stored, isEmpty);
    expect(await widgets.openRequests.isEmpty, isTrue);
  });
}
