import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/home_widgets/domain/home_screen_widgets.dart';
import 'package:sinapsis/features/home_widgets/presentation/providers/home_widgets_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

/// Conecta los widgets de la pantalla de inicio con la app (F47, paso 7),
/// por encima de toda pantalla. Donde no hay widgets no hace nada.
///
/// - **«Para hoy»**: mientras la bóveda está abierta, cada vez que cambia lo
///   que hay para estudiar hoy —el mismo número de la insignia de Repasar—,
///   se lo cuenta al widget, con el fin del día de estudio: pasado, el widget
///   no repite una cifra vieja. Al volver al frente se cuenta de nuevo, por
///   las tarjetas que vencieron mientras tanto.
/// - **«Seguir escuchando»**: lo que diga [continueListeningProvider]. Hasta
///   que llegue el reproductor anclado (F47, paso 2), lo alimenta el lector
///   en voz alta de hoy: ver `_feedFromReadAloud`.
/// - **Los toques**: «Para hoy» lleva a Repasar, «Guardar rápido» abre
///   Guardar listo para pegar o escribir, y «Seguir escuchando», la pantalla
///   desde donde se escuchó. Con la app abierta, de una vez; desde cero
///   (`takePendingOpen`), apenas se abre la bóveda: antes manda la pantalla
///   de desbloqueo, y el pedido no se pierde.
class HomeWidgetsBinding extends ConsumerStatefulWidget {
  const HomeWidgetsBinding({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<HomeWidgetsBinding> createState() => _HomeWidgetsBindingState();
}

class _HomeWidgetsBindingState extends ConsumerState<HomeWidgetsBinding> {
  late final HomeScreenWidgets _widgets = ref.read(homeScreenWidgetsProvider);
  AppLifecycleListener? _lifecycle;
  StreamSubscription<HomeWidgetKind>? _openRequests;
  ProviderSubscription<AsyncValue<int>>? _dueToday;
  ProviderSubscription<ContinueListening?>? _continueListening;
  ProviderSubscription<String?>? _readAloud;

  /// El widget que se tocó y todavía no se atendió.
  HomeWidgetKind? _pendingOpen;

  @override
  void initState() {
    super.initState();
    if (!_widgets.isSupported) return;
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          ref.invalidate(studyCountsProvider(const StudyScope.all())),
    );
    // Desde el stream de la plataforma y no desde un proveedor: dos toques
    // seguidos al mismo widget son dos pedidos.
    _openRequests = _widgets.openRequests.listen(_requestOpen);
    unawaited(_takePendingOpen());
    _continueListening = ref.listenManual(continueListeningProvider, (
      previous,
      current,
    ) {
      unawaited(_widgets.showContinueListening(current));
    }, fireImmediately: true);
    _readAloud = _feedFromReadAloud();
    _syncDueToday();
  }

  @override
  void dispose() {
    unawaited(_openRequests?.cancel());
    _dueToday?.close();
    _continueListening?.close();
    _readAloud?.close();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// El puente con el lector en voz alta (F25), hasta el reproductor anclado
  /// de F47 (paso 2), cuya sesión de medios llamará a
  /// `ContinueListeningNotifier.listened` por su cuenta.
  ///
  /// Cuando el lector empieza un texto nuevo, ese es lo último que se
  /// escuchó, y la pantalla de ahora —la que lo ofreció— es adonde vuelve
  /// el widget.
  ProviderSubscription<String?> _feedFromReadAloud() => ref.listenManual(
    readAloudControllerProvider.select((state) => state.document?.id),
    (previous, current) {
      final document = ref.read(readAloudControllerProvider).document;
      if (current == null || document == null) return;
      // La de arriba de todo, también si se abrió encima de otra (`push`):
      // `state` es la de la última ruta, no la de la base de la pila.
      final location = widget.router.state.uri.toString();
      unawaited(
        ref
            .read(continueListeningProvider.notifier)
            .listened(title: document.title, location: location),
      );
    },
  );

  Future<void> _takePendingOpen() async {
    final pending = await _widgets.takePendingOpen();
    if (pending != null && mounted) _requestOpen(pending);
  }

  void _requestOpen(HomeWidgetKind kind) {
    _pendingOpen = kind;
    _openIfReady();
  }

  /// Abre lo pedido si hay un pedido y la bóveda está abierta.
  void _openIfReady() {
    final kind = _pendingOpen;
    if (kind == null || !mounted) return;
    if (ref.read(vaultSessionControllerProvider) is! VaultUnlocked) return;
    _pendingOpen = null;
    // Un instante después: al abrirse la bóveda, el router también está
    // decidiendo a dónde ir, y el pedido de la persona va último (mismo
    // criterio que el aviso diario).
    scheduleMicrotask(() {
      if (!mounted) return;
      final router = widget.router;
      switch (kind) {
        case HomeWidgetKind.dueToday:
          router.go(RoutePaths.review);
        case HomeWidgetKind.quickCapture:
          unawaited(router.push<void>(RoutePaths.quickCapture));
        case HomeWidgetKind.continueListening:
          // Sin nada escuchado, el widget solo abre la app.
          final location = ref.read(continueListeningProvider)?.location;
          if (location != null) unawaited(router.push<void>(location));
      }
    });
  }

  /// Cuenta las tarjetas de hoy mientras la bóveda está abierta; cerrada, no
  /// hay base que contar y el widget sigue con lo último que se le dijo.
  void _syncDueToday() {
    if (ref.read(vaultSessionControllerProvider) is! VaultUnlocked) {
      _dueToday?.close();
      _dueToday = null;
      return;
    }
    _dueToday ??= ref.listenManual(studyDueTodayCountProvider, (
      previous,
      current,
    ) {
      final count = current.valueOrNull;
      if (count == null) return;
      final now = ref.read(clockProvider)();
      unawaited(
        _widgets.showDueToday(
          DueToday(count: count, validUntil: const StudyDay().endOf(now)),
        ),
      );
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_widgets.isSupported) {
      ref.listen(vaultSessionControllerProvider, (previous, current) {
        _syncDueToday();
        _openIfReady();
      });
    }
    return widget.child;
  }
}
