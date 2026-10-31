import 'dart:async';

import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';

/// Un [HomeScreenWidgets] de mentira (F47, paso 7): anota lo que se le
/// muestra y lo que se le pide, y deja simular los toques a los widgets.
class FakeHomeScreenWidgets implements HomeScreenWidgets {
  FakeHomeScreenWidgets({this.supported = true, this.canAdd = true});

  final bool supported;
  bool canAdd;

  /// Cada «Para hoy» que se le mostró, en orden.
  final dueToday = <DueToday>[];

  /// Cada «Seguir escuchando» que se le mostró, en orden.
  final continueListening = <ContinueListening?>[];

  /// Los widgets que se pidió agregar.
  final added = <HomeWidgetKind>[];

  /// El toque que abrió la app desde cero, para [takePendingOpen].
  HomeWidgetKind? pendingOpen;

  final openController = StreamController<HomeWidgetKind>.broadcast();

  /// Simula tocar [kind] con la app andando.
  void tap(HomeWidgetKind kind) => openController.add(kind);

  @override
  bool get isSupported => supported;

  @override
  Future<void> showDueToday(DueToday dueToday) async =>
      this.dueToday.add(dueToday);

  @override
  Future<void> showContinueListening(ContinueListening? listening) async =>
      continueListening.add(listening);

  @override
  Future<bool> canAddFromApp() async => canAdd;

  @override
  Future<void> add(HomeWidgetKind kind) async => added.add(kind);

  @override
  Stream<HomeWidgetKind> get openRequests => openController.stream;

  @override
  Future<HomeWidgetKind?> takePendingOpen() async {
    final pending = pendingOpen;
    pendingOpen = null;
    return pending;
  }
}
