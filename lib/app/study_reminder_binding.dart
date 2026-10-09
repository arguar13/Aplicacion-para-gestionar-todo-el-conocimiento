import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/data/repositories/study_repository_impl.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_limits_provider.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';
import 'package:sinapsis/features/study_reminder/presentation/providers/study_reminder_providers.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_session.dart';
import 'package:sinapsis/features/vault/presentation/providers/vault_providers.dart';

/// Cuántas tarjetas hay para estudiar **cuando suene el aviso** (F31, decisión
/// 70): las que vencen hasta la próxima hora del aviso, con los límites del
/// día de estudio en que cae esa hora, no solo las que vencen ahora. El aviso
/// suena horas después y dice lo último que se le contó.
///
/// Es la misma cola que muestra Repasar, con el reloj puesto en la próxima
/// ocurrencia de la hora elegida (`ReminderTime.nextOccurrence`): a las 20:00
/// de hoy cuenta lo de hoy; si ya pasó, lo de mañana a las 20:00, con los
/// límites de mañana intactos. Se actualiza solo ante cualquier cambio de
/// tarjetas, al empezar otro día de estudio y al cambiar la hora del aviso o
/// los límites.
final studyReminderCountProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(studyDayStartProvider);
  final time =
      ref.watch(
        studyReminderStateProvider.select((state) => state.valueOrNull?.time),
      ) ??
      ref.watch(studyReminderSettingsProvider).time;
  final limits = ref.watch(studyLimitsProvider);
  final now = ref.watch(clockProvider);
  final repository = StudyRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
    // Se lee cada vez que se cuenta: pasada la hora, la próxima ya es la del
    // día siguiente.
    clock: () => time.nextOccurrence(now()),
    resolver: ref.watch(studyScopeResolverProvider),
  );
  return repository
      .watchCounts(const StudyScope.all(), limits: limits)
      .map((counts) => counts.total);
});

/// Conecta el aviso diario para repasar con la app (F31, ola 2), por encima de
/// toda pantalla:
///
/// - al abrir la app, vuelve a programar el aviso si se había perdido
///   (`restore`);
/// - cada vez que cambia lo que hay para estudiar, le cuenta cuántas tarjetas
///   son ([studyReminderCountProvider]): sin la bóveda abierta no hay base que
///   contar, y en una plataforma sin aviso no se cuenta nada;
/// - al tocar la notificación, lleva a Repasar: con la app abierta, de una vez;
///   desde cero (`takePendingOpen`), apenas se abre la bóveda, porque antes la
///   pantalla de desbloqueo manda y el pedido no se pierde.
class StudyReminderBinding extends ConsumerStatefulWidget {
  const StudyReminderBinding({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<StudyReminderBinding> createState() =>
      _StudyReminderBindingState();
}

class _StudyReminderBindingState extends ConsumerState<StudyReminderBinding> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<void>? _openRequests;
  ProviderSubscription<AsyncValue<int>>? _countSubscription;

  /// Si la persona tocó la notificación y todavía no se la llevó a Repasar.
  var _openPending = false;

  @override
  void initState() {
    super.initState();
    final platform = ref.read(studyReminderProvider);
    // Al volver al frente, el aviso cuenta con el reloj de ahora: si pasó la
    // hora, la cuenta es la del día siguiente.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(studyReminderCountProvider),
    );
    // Desde el stream de la plataforma y no desde el proveedor: un proveedor
    // de `void` no avisa dos veces seguidas del mismo valor, y cada toque de
    // la notificación tiene que llevar a Repasar.
    _openRequests = platform.openRequests.listen((_) => _requestOpen());
    unawaited(ref.read(studyReminderControllerProvider).restore());
    unawaited(_takePendingOpen());
    _syncCount();
  }

  @override
  void dispose() {
    unawaited(_openRequests?.cancel());
    _countSubscription?.close();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _takePendingOpen() async {
    final pending = await ref.read(studyReminderProvider).takePendingOpen();
    if (pending && mounted) _requestOpen();
  }

  void _requestOpen() {
    _openPending = true;
    _openIfReady();
  }

  /// Lleva a Repasar si hay un pedido y la bóveda está abierta.
  void _openIfReady() {
    if (!_openPending || !mounted) return;
    if (ref.read(vaultSessionControllerProvider) is! VaultUnlocked) return;
    _openPending = false;
    // Un instante después: al abrirse la bóveda, el router también está
    // decidiendo a dónde ir, y el pedido de la persona va último. (Un
    // `addPostFrameCallback` no sirve: con la app quieta no hay cuadro que lo
    // dispare.)
    scheduleMicrotask(() {
      if (mounted) widget.router.go(RoutePaths.review);
    });
  }

  /// Cuenta las tarjetas mientras la bóveda está abierta y la plataforma tiene
  /// aviso; en cualquier otro caso, no escucha nada.
  void _syncCount() {
    final shouldCount =
        ref.read(vaultSessionControllerProvider) is VaultUnlocked &&
        ref.read(studyReminderProvider).isSupported;
    if (!shouldCount) {
      _countSubscription?.close();
      _countSubscription = null;
      return;
    }
    _countSubscription ??= ref.listenManual(studyReminderCountProvider, (
      previous,
      current,
    ) {
      final count = current.valueOrNull;
      if (count != null) {
        unawaited(
          ref.read(studyReminderControllerProvider).updateStudyCount(count),
        );
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vaultSessionControllerProvider, (previous, current) {
      _syncCount();
      _openIfReady();
    });
    return widget.child;
  }
}
