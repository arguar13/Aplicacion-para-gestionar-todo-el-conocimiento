import 'package:sinapsis/features/study_reminder/domain/entities/reminder_time.dart';

/// Lo que la persona eligió para el aviso de repaso: si lo quiere y a qué
/// hora (F31). Apagado por defecto: un aviso que nadie pidió es ruido.
///
/// Es la verdad de lo elegido; el sistema operativo guarda por su lado una
/// copia de lo necesario para que el aviso suene con la app cerrada, y
/// `StudyReminderController.restore` la corrige si se desparejan.
abstract interface class StudyReminderSettings {
  /// Si el aviso está prendido. `false` hasta que se prenda.
  bool get enabled;

  /// La hora elegida; [ReminderTime.standard] si nunca se eligió una.
  ReminderTime get time;

  Future<void> save({required bool enabled, required ReminderTime time});
}
