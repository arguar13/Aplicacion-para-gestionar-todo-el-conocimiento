import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_library_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Biblioteca de voces», el botón que abre la biblioteca desde una hoja de
/// Ajustes que manda ahí —«Voces por idioma» para elegir otra, «Voces
/// descargadas» vacía para bajar una (F46, paso 5f)—: la misma salida en las
/// dos, alineada al comienzo y debajo de lo que dice la hoja, así con la
/// letra al doble no aprieta nada.
class VoiceLibraryButton extends StatelessWidget {
  const VoiceLibraryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.record_voice_over_outlined),
          label: Text(l10n.f47P3LibraryTitle),
          onPressed: () => unawaited(showVoiceLibrary(context)),
        ),
      ),
    );
  }
}
