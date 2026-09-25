/// Una insignia de las que premia F17, D7: destilar, consolidar y repasar
/// —nunca capturar—.
enum BadgeKind {
  /// La primera nota que llega a `NoteMaturity.mature`.
  firstMatureNote,

  /// Diez notas vivas, cualquier madurez.
  tenLivingNotes,

  /// Cien repasos —renglones de `review_log`, no tarjetas distintas—.
  hundredReviews,

  /// Una contradicción marcada como revisada (F9): `RelationKind.
  /// contradicts` con `reviewedAt` puesto.
  contradictionResolved,

  /// Una rama del Atlas —con sus descendientes— donde cada fuente tiene
  /// al menos una nota viva madura que la cita.
  completeTopicBranch,

  /// Un mes donde cada semana tuvo actividad que cuenta para la racha.
  monthOfWeeklyConsolidation,
}
