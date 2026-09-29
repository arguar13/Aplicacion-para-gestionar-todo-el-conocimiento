/// Lo que mantiene viva la app mientras hay trabajo largo en curso (F21,
/// decisión C): en Android, un servicio en primer plano con su notificación
/// —sin él, el sistema congela o mata la app a los pocos minutos de salir de
/// ella, a mitad de una transcripción de horas—. En el resto de las
/// plataformas no hace falta nada.
abstract interface class LongWorkKeeper {
  /// Hay trabajo largo en curso: [done] de [total] —páginas, tramos—, o los
  /// dos en cero si todavía no se sabe cuánto hay. Se puede llamar seguido:
  /// solo cuenta lo que cambia.
  void working({required int done, required int total});

  /// Ya no hay trabajo largo en curso.
  void idle();
}

/// Donde no hace falta mantener nada vivo: la web, el escritorio, las
/// pruebas.
class NoLongWorkKeeper implements LongWorkKeeper {
  const NoLongWorkKeeper();

  @override
  void working({required int done, required int total}) {}

  @override
  void idle() {}
}
