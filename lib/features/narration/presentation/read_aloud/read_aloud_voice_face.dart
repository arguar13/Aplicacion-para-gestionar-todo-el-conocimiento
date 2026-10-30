import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/providers/voice_library_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Abre una hoja del lector —la velocidad, la cola— sobre la pantalla de
/// [context], sin deslizarse si se apagaron las animaciones.
Future<void> showReadAloudSheet(BuildContext context, Widget sheet) {
  final still = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => sheet,
  );
}

/// **La única entrada para elegir la voz** (F47, paso 2): la cara de la voz
/// del reproductor anclado y el reproductor de los visores de Repasar abren
/// por acá la biblioteca de voces (paso 3).
void openVoicePicker(BuildContext context) =>
    unawaited(showVoiceLibrary(context));

/// Cómo se nombra [voice] en una frase —«Leyendo con …»—: su nombre si es
/// un nombre de verdad («Daniela», «Mónica»), su acento si es un código del
/// motor («Español (Argentina)») y la voz del teléfono si no hay ninguna.
String readAloudVoiceName(NarrationVoice? voice, AppLocalizations l10n) {
  if (voice == null) return l10n.f47P2PhoneVoice;
  final name = voiceProfileOf(voice)?.name;
  if (name != null) return name;
  if (looksLikeVoiceCode(voice.name)) return accentDisplayName(voice.locale);
  return voice.name;
}

/// La cara de la voz de ahora en el reproductor (F47, pasos 2 y 3): el
/// retrato abstracto de la biblioteca —[VoiceFaceView], sin fotos de
/// personas reales (decisión D)—, de la voz que lee el pedazo que suena.
///
/// La voz del sistema no es una voz de la biblioteca —es la que el teléfono
/// tenga elegida—, pero el reproductor igual muestra una cara: la suya,
/// propia y siempre la misma, armada con su nombre.
class ReadAloudVoiceFace extends ConsumerWidget {
  const ReadAloudVoiceFace({this.size = 40, super.key});

  final double size;

  /// El id con que se arma la cara de la voz del sistema.
  static const systemFaceId = 'system';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(currentVoiceProfileProvider);
    if (voice != null) return VoiceFaceView.of(voice, size: size);
    final l10n = AppLocalizations.of(context)!;
    return VoiceFaceView(
      face: VoiceFace.of(systemFaceId, l10n.readAloudSystemVoice),
      size: size,
    );
  }
}
