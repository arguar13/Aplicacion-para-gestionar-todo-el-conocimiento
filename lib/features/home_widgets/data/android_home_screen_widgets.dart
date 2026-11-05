import 'dart:async';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';

/// Las claves de lo que leen los widgets en sus preferencias (las de
/// `home_widget`). Del otro lado las lee `HomeWidgets.kt`: cambiar una acá es
/// cambiarla allá.
const kDueTodayCountKey = 'due_today_count';
const kDueTodayValidUntilKey = 'due_today_valid_until';
const kContinueListeningTitleKey = 'continue_listening_title';

/// Si el título de «Seguir escuchando» se ve también con la bóveda cerrada
/// (F47, paso 7a-bis). Solo `true` lo deja a la vista: sin la clave —lo que
/// dejó una versión anterior—, se oculta.
const kContinueListeningShowLockedKey = 'continue_listening_show_locked';

/// El encendido del teléfono en que la bóveda está abierta (F47, paso 7a-bis):
/// el widget lo compara con el de ahora. Sin la clave, no está abierta.
const kContinueListeningOpenBootKey = 'continue_listening_open_boot';

/// [HomeScreenWidgets] en Android (F47, paso 7, decisión G).
///
/// - **Lo que muestran** va por `home_widget`: guarda los datos en las
///   preferencias que lee cada widget y le pide al sistema que los vuelva a
///   dibujar. Los diseños y cómo se dibujan son propios, en Kotlin
///   (`DueTodayWidget`, `QuickCaptureWidget`, `ContinueListeningWidget`).
/// - **Los toques** van por el canal `app.sinapsis/home_widgets` (ver
///   `HomeWidgetsChannel`), y no por los de `home_widget`, por cómo vive la
///   app (F29): el motor de Dart sobrevive a la actividad, así que un toque
///   con la app cerrada puede abrir una actividad nueva sobre un Dart que ya
///   andaba y ya preguntó cómo arrancó —`home_widget` lo perdería—, y su
///   toque lleva una dirección que Flutter mandaría además como ruta. El canal
///   propio sigue el mismo camino que la notificación del aviso diario: avisa
///   si Dart escucha y, si no, el toque queda pendiente hasta
///   [takePendingOpen].
class AndroidHomeScreenWidgets implements HomeScreenWidgets {
  AndroidHomeScreenWidgets({
    MethodChannel channel = const MethodChannel('app.sinapsis/home_widgets'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _openRequests = StreamController<HomeWidgetKind>.broadcast();

  @override
  bool get isSupported => true;

  @override
  Future<void> showDueToday(DueToday dueToday) async {
    await HomeWidget.saveWidgetData<int>(kDueTodayCountKey, dueToday.count);
    await HomeWidget.saveWidgetData<int>(
      kDueTodayValidUntilKey,
      dueToday.validUntil.millisecondsSinceEpoch,
    );
    await _redraw(HomeWidgetKind.dueToday);
  }

  @override
  Future<void> showContinueListening(ContinueListeningDisplay display) async {
    // Cada clave se guarda por separado, y el sistema podría dibujar el
    // widget entre una y otra: primero lo que restringe —si se ve con la
    // bóveda cerrada y en qué encendido está abierta— y el título al final.
    // Así, cuando algo pasa a ocultarse, nunca hay un instante en que se vea.
    await HomeWidget.saveWidgetData<bool>(
      kContinueListeningShowLockedKey,
      display.showWhileLocked,
    );
    await HomeWidget.saveWidgetData<String>(
      kContinueListeningOpenBootKey,
      display.openBoot,
    );
    await HomeWidget.saveWidgetData<String>(
      kContinueListeningTitleKey,
      display.title,
    );
    await _redraw(HomeWidgetKind.continueListening);
  }

  @override
  Future<bool> canAddFromApp() async =>
      await HomeWidget.isRequestPinWidgetSupported() ?? false;

  @override
  Future<void> add(HomeWidgetKind kind) =>
      HomeWidget.requestPinWidget(qualifiedAndroidName: kind.androidProvider);

  @override
  Stream<HomeWidgetKind> get openRequests => _openRequests.stream;

  @override
  Future<HomeWidgetKind?> takePendingOpen() async => HomeWidgetKind.fromWire(
    await _channel.invokeMethod<String>('takePendingOpen'),
  );

  Future<void> _redraw(HomeWidgetKind kind) =>
      HomeWidget.updateWidget(qualifiedAndroidName: kind.androidProvider);

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'open') {
      final kind = HomeWidgetKind.fromWire(call.arguments as String?);
      if (kind != null) _openRequests.add(kind);
      return null;
    }
    throw MissingPluginException('Método desconocido: ${call.method}');
  }
}
