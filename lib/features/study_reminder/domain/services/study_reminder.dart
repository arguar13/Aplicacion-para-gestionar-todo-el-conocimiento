import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';

/// El aviso diario para repasar, del lado de la plataforma (F31): programar a
/// una hora, cancelar, saber si está programado, y cuántas tarjetas hay para
/// el texto de la notificación.
///
/// No sabe si la persona lo quiere prendido ni a qué hora: eso lo guarda
/// `StudyReminderSettings` y lo orquesta `StudyReminderController`. Acá solo
/// hay lo que el sistema operativo hace.
///
/// En Android es `MethodChannelStudyReminder` (una alarma del sistema y una
/// notificación, sin dependencias nuevas); en escritorio y la web,
/// `NullStudyReminder`, que no hace nada y dice que no está soportado.
abstract interface class StudyReminder {
  /// Si esta plataforma puede mostrar el aviso. Si es `false`, la pantalla no
  /// ofrece prenderlo.
  bool get isSupported;

  /// Programa el aviso diario a [time]. Reemplaza a cualquier programación
  /// anterior, así que llamarlo otra vez con otra hora la cambia. Sobrevive
  /// a que se cierre la app y a que se reinicie el teléfono.
  Future<void> schedule(ReminderTime time);

  /// Cancela el aviso. Sin programación, no hace nada.
  Future<void> cancel();

  /// Si el sistema tiene el aviso programado ahora.
  Future<bool> isScheduled();

  /// La hora con la que está programado, o `null` si no lo está.
  Future<ReminderTime?> scheduledTime();

  /// Si el sistema deja mostrar notificaciones de la app. Antes de Android 13
  /// siempre (salvo que se las silencie en ajustes); desde ahí, si se aceptó
  /// el permiso.
  Future<bool> hasNotificationPermission();

  /// Pide el permiso de notificaciones y espera la respuesta. Hay que
  /// llamarlo solo cuando la persona prende el aviso, no antes. Devuelve si
  /// quedó concedido. Si ya se rechazó dos veces el sistema no vuelve a
  /// preguntar y devuelve `false` al instante: ahí hay que mandarla a
  /// [openNotificationSettings].
  Future<bool> requestNotificationPermission();

  /// Abre los ajustes de notificaciones de la app. Devuelve si se pudo.
  Future<bool> openNotificationSettings();

  /// Cuántas tarjetas hay para repasar, para el texto «Tenés N tarjetas para
  /// repasar». Con 0 el aviso de ese día no se muestra; con un número
  /// negativo se borra lo que se sabía y el aviso sale con un texto sin
  /// cantidad. El aviso sale a su hora con el sistema dormido y la app
  /// cerrada, sin poder consultar la base: dice lo último que se guardó acá.
  Future<void> setStudyCount(int count);

  /// La persona tocó la notificación con la app abierta: hay que mostrar la
  /// pestaña Repasar.
  Stream<void> get openRequests;

  /// Si la app se abrió desde la notificación y todavía no se atendió ese
  /// pedido (el arranque en frío: el motor ya existe pero nadie escuchaba
  /// [openRequests]). Devuelve `true` una sola vez por toque.
  Future<bool> takePendingOpen();
}
