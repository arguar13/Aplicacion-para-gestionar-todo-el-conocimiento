import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/data/services/method_channel_dictation.dart';
import 'package:sinapsis/features/chat/data/services/null_dictation.dart';
import 'package:sinapsis/features/chat/domain/services/dictation.dart';

/// Habla a texto (F42): en Android, el reconocedor del sistema; en el resto,
/// uno que dice que no hay ([NullDictation]).
///
/// Se sobreescribe en las pruebas: escuchar el micrófono de verdad necesita
/// un teléfono.
final dictationProvider = Provider<Dictation>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? const MethodChannelDictation()
      : const NullDictation(),
);

/// Si hay reconocimiento de voz en este dispositivo: el 🎤 del campo del chat
/// se muestra solo si sí. Se vuelve a preguntar cada vez que se abre el chat
/// —por si se instaló el servicio de voz mientras tanto—, sin pedir permiso.
final dictationAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(dictationProvider).isAvailable(),
);
