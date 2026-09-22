/// Un instante de un audio o un video escrito como se lee en un reproductor:
/// «2:07» o, pasada la hora, «1:02:07». Sin ceros de más adelante: «0:14»
/// —catorce segundos— y no «00:00:14».
String formatClock(int milliseconds) {
  final total = milliseconds ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$ss';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
}
