import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';

/// [HomeScreenWidgets] de las plataformas sin widgets (la web y el
/// escritorio): no los hay y no hace nada.
class NullHomeScreenWidgets implements HomeScreenWidgets {
  const NullHomeScreenWidgets();

  @override
  bool get isSupported => false;

  @override
  Future<void> showDueToday(DueToday dueToday) async {}

  @override
  Future<void> showContinueListening(ContinueListening? listening) async {}

  @override
  Future<bool> canAddFromApp() async => false;

  @override
  Future<void> add(HomeWidgetKind kind) async {}

  @override
  Stream<HomeWidgetKind> get openRequests => const Stream.empty();

  @override
  Future<HomeWidgetKind?> takePendingOpen() async => null;
}
