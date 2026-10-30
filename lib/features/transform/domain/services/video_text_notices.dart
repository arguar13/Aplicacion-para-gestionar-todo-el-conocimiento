import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lo que hizo la red de seguridad del idioma con un video (F45, paso 4): sus
/// subtítulos no estaban en el idioma que se habla, no se guardaron, y su
/// texto sale del audio, transcrito en el teléfono con el idioma fijado.
@immutable
class ForeignCaptionsNotice {
  const ForeignCaptionsNotice({
    required this.itemId,
    required this.title,
    required this.audioLanguage,
    this.foundLanguage,
    this.transcribing = true,
  });

  final String itemId;

  /// El nombre del video.
  final String title;

  /// En qué idioma estaban los subtítulos, si se reconoce; `null` si no.
  final String? foundLanguage;

  /// En qué idioma se transcribe el audio.
  final String audioLanguage;

  /// Si se transcribe el audio: no donde no hay con qué —en la web—, y ahí
  /// el texto es la descripción del video.
  final bool transcribing;

  @override
  bool operator ==(Object other) =>
      other is ForeignCaptionsNotice &&
      other.itemId == itemId &&
      other.title == title &&
      other.foundLanguage == foundLanguage &&
      other.audioLanguage == audioLanguage &&
      other.transcribing == transcribing;

  @override
  int get hashCode =>
      Object.hash(itemId, title, foundLanguage, audioLanguage, transcribing);
}

/// Por donde pasa el aviso de [ForeignCaptionsNotice] desde la cola, que no
/// sabe de pantallas, hasta el aviso de abajo (`VideoTextNoticeListener`). Uno
/// solo en toda la app, como `AiNoticeBus`.
class VideoTextNoticeBus {
  final _notices = StreamController<ForeignCaptionsNotice>.broadcast();

  /// Los avisos a medida que pasan.
  Stream<ForeignCaptionsNotice> get notices => _notices.stream;

  void notify(ForeignCaptionsNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  Future<void> dispose() => _notices.close();
}
