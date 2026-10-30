import 'package:sinapsis/core/audio/media_session.dart';

/// [MediaSessionPlatform] de las plataformas sin tarjeta de lo que suena
/// (la web, Windows): no está soportada y no hace nada. Lo que suena sigue
/// sonando con la app abierta, como siempre.
class NullMediaSession implements MediaSessionPlatform {
  const NullMediaSession();

  @override
  bool get isSupported => false;

  @override
  Future<void> update(MediaSessionState state) async {}

  @override
  Future<void> end() async {}

  @override
  Stream<MediaCommand> get commands => const Stream.empty();

  @override
  Stream<MediaInterruption> get interruptions => const Stream.empty();
}
