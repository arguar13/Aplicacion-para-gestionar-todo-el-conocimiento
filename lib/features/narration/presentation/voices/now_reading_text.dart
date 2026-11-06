import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/presentation/providers/my_voices_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_voice_face.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Lee ahora: …» (F47, paso 3): la voz que lee [voice], nombrada como la
/// nombra el reproductor ([readAloudVoiceName]) —su nombre, su acento si es
/// un código del motor, la voz del teléfono si no hay ninguna—, y no con el
/// «Voz 2» de la lista, que solo tiene sentido al lado de las otras.
///
/// Con [unchosen] —no hay una elegida para lo que se lee y la biblioteca
/// marca «Voz del sistema»— lo dice, porque la que suena la tomó sola el
/// lector: «Lee ahora: Español (Estados Unidos), porque no elegiste
/// ninguna» (F46, paso 5f).
String nowReadingText(
  AppLocalizations l10n,
  NarrationVoice? voice, {
  required bool unchosen,
  Iterable<MyVoice> mine = const [],
}) {
  if (voice == null) return l10n.f47P3NowReadingSystem;
  final name = readAloudVoiceName(voice, l10n, mine: mine);
  return unchosen
      ? l10n.f46P5fNowReadingUnchosen(name)
      : l10n.f47P3NowReading(name);
}

/// [nowReadingText] de la voz que lee ahora, siguiéndola: lo que dicen
/// arriba de la biblioteca de voces y Ajustes, con el mismo nombre que el
/// reproductor.
String watchNowReadingText(WidgetRef ref, AppLocalizations l10n) =>
    nowReadingText(
      l10n,
      ref.watch(readAloudControllerProvider.select((s) => s.voice)),
      unchosen: ref.watch(noVoiceChosenProvider),
      mine: ref.watch(myVoicesProvider).valueOrNull ?? const [],
    );
