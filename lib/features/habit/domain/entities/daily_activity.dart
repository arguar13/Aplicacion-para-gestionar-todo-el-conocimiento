/// Cuántos repasos hubo un día (F17, D8): la fila de una nota del
/// calendario de constancia, un día por celda, incluidos los días en cero.
class DailyActivity {
  const DailyActivity({required this.day, required this.count});

  final DateTime day;
  final int count;
}
