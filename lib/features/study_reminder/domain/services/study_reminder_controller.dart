import 'package:meta/meta.dart';
import 'package:sinapsis/core/logging/app_logger.dart';
import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder.dart';
import 'package:sinapsis/features/study_reminder/domain/services/study_reminder_settings.dart';

/// Cómo terminó de prender el aviso.
enum StudyReminderEnableResult {
  /// Quedó prendido y programado.
  enabled,

  /// La persona no concedió el permiso de notificaciones: no se prendió. La
  /// pantalla puede ofrecer [StudyReminder.openNotificationSettings].
  permissionDenied,

  /// Esta plataforma no tiene aviso.
  unsupported,
}

/// Lo que la pantalla de ajustes necesita saber del aviso.
@immutable
class StudyReminderState {
  const StudyReminderState({
    required this.supported,
    required this.enabled,
    required this.time,
    required this.permissionGranted,
    required this.scheduled,
  });

  /// Si la plataforma puede mostrarlo.
  final bool supported;

  /// Si la persona lo prendió.
  final bool enabled;

  /// La hora elegida.
  final ReminderTime time;

  /// Si el sistema deja mostrar notificaciones de la app.
  final bool permissionGranted;

  /// Si el sistema lo tiene programado.
  final bool scheduled;

  /// Si está prendido pero no va a sonar: sin permiso (lo quitaron en
  /// ajustes) o sin programación. La pantalla lo avisa.
  bool get needsAttention =>
      supported && enabled && (!permissionGranted || !scheduled);

  @override
  bool operator ==(Object other) =>
      other is StudyReminderState &&
      other.supported == supported &&
      other.enabled == enabled &&
      other.time == time &&
      other.permissionGranted == permissionGranted &&
      other.scheduled == scheduled;

  @override
  int get hashCode =>
      Object.hash(supported, enabled, time, permissionGranted, scheduled);
}

/// El aviso diario para repasar de punta a punta (F31): lo que la persona
/// eligió ([StudyReminderSettings]) puesto en práctica con lo que el sistema
/// sabe hacer ([StudyReminder]).
///
/// Es lo que usan las pantallas:
///
/// - Ajustes: [load], [enable], [changeTime], [disable].
/// - Cualquier pantalla que cambie cuántas tarjetas hay para repasar, o que
///   las lea: [updateStudyCount]. Pasá las que vencen **hasta la próxima hora
///   del aviso** (`ReminderTime.nextOccurrence`), no solo las vencidas ahora:
///   el aviso suena horas después y dice lo último que se le contó.
/// - Al abrir la app: [restore].
class StudyReminderController {
  StudyReminderController({
    required StudyReminder platform,
    required StudyReminderSettings settings,
    required AppLogger logger,
  }) : _platform = platform,
       _settings = settings,
       _logger = logger;

  final StudyReminder _platform;
  final StudyReminderSettings _settings;
  final AppLogger _logger;

  int? _lastCount;

  /// Cómo está el aviso ahora.
  Future<StudyReminderState> load() async {
    if (!_platform.isSupported) {
      return StudyReminderState(
        supported: false,
        enabled: false,
        time: _settings.time,
        permissionGranted: false,
        scheduled: false,
      );
    }
    return StudyReminderState(
      supported: true,
      enabled: _settings.enabled,
      time: _settings.time,
      permissionGranted: await _platform.hasNotificationPermission(),
      scheduled: await _platform.isScheduled(),
    );
  }

  /// Prende el aviso a [time] (o a la hora ya elegida). Pide el permiso de
  /// notificaciones **ahora**, que es cuando la persona lo pidió; si no lo
  /// concede, no queda prendido nada. [studyCount], si se sabe, se le pasa al
  /// aviso para que su primer texto ya tenga la cantidad.
  Future<StudyReminderEnableResult> enable({
    ReminderTime? time,
    int? studyCount,
  }) async {
    if (!_platform.isSupported) return StudyReminderEnableResult.unsupported;

    final granted =
        await _platform.hasNotificationPermission() ||
        await _platform.requestNotificationPermission();
    if (!granted) return StudyReminderEnableResult.permissionDenied;

    final chosen = time ?? _settings.time;
    await _platform.schedule(chosen);
    await _settings.save(enabled: true, time: chosen);
    if (studyCount != null) await updateStudyCount(studyCount);
    return StudyReminderEnableResult.enabled;
  }

  /// Cambia la hora. Si el aviso está prendido, lo reprograma; si no, solo
  /// queda elegida para cuando se prenda.
  Future<void> changeTime(ReminderTime time) async {
    final enabled = _settings.enabled && _platform.isSupported;
    if (enabled) await _platform.schedule(time);
    await _settings.save(enabled: _settings.enabled, time: time);
  }

  /// Apaga el aviso. La hora elegida se conserva.
  Future<void> disable() async {
    if (_platform.isSupported) await _platform.cancel();
    await _settings.save(enabled: false, time: _settings.time);
  }

  /// Vuelve a programar el aviso si está prendido. Se llama al abrir la app:
  /// el sistema operativo ya lo hace solo al reiniciar el teléfono y al
  /// abrirla, pero esto lo corrige si lo programado se perdió o quedó con otra
  /// hora (se borraron los datos del sistema, se restauró una copia).
  Future<void> restore() async {
    if (!_platform.isSupported || !_settings.enabled) return;
    final time = _settings.time;
    if (await _platform.isScheduled() &&
        await _platform.scheduledTime() == time) {
      return;
    }
    await _platform.schedule(time);
  }

  /// Le cuenta al aviso cuántas tarjetas hay para repasar. Se puede llamar
  /// cada vez que ese número cambia: si es el mismo que la vez anterior no
  /// hace nada. Un [count] de 0 apaga el aviso de ese día; negativo, lo deja
  /// sin cantidad.
  ///
  /// No lanza: lo llaman pantallas de estudio que no tienen nada que hacer
  /// con un fallo del aviso. Si el sistema lo rechaza queda en el registro y
  /// se vuelve a intentar con el siguiente cambio.
  Future<void> updateStudyCount(int count) async {
    if (!_platform.isSupported || _lastCount == count) return;
    try {
      await _platform.setStudyCount(count);
      _lastCount = count;
    } on Exception catch (e, stack) {
      // El canal del sistema responde con PlatformException (o con
      // MissingPluginException si no hay nadie del otro lado).
      _logger.warning('No se pudo guardar la cantidad del aviso.', e, stack);
    }
  }
}
