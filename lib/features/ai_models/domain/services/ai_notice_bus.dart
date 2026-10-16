import 'dart:async';

import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';

/// Por donde pasan los avisos de la IA en la nube (F32) desde el motor, que no
/// sabe de pantallas, hasta el aviso que se ve arriba de todo. Uno solo en
/// toda la app.
class AiNoticeBus {
  final _notices = StreamController<AiNotice>.broadcast();

  /// Los avisos a medida que pasan.
  Stream<AiNotice> get notices => _notices.stream;

  void notify(AiNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  Future<void> dispose() => _notices.close();
}
