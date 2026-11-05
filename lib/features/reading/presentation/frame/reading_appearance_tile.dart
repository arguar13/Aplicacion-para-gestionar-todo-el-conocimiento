import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_appearance_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Tipografía y resaltado», en Ajustes › Voz y lectura (F47, paso 7b): la
/// letra, su tamaño y el color de lo que suena que se eligieron, y tocarla
/// abre la misma «Apariencia» del marco de lectura (Aa, paso 1) —no otra
/// copia—, con todo lo que se guarda para los lectores.
class ReadingAppearanceSettingsTile extends ConsumerWidget {
  const ReadingAppearanceSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final appearance = ref.watch(readingAppearanceProvider);
    return ListTile(
      key: const Key('settings-reading-appearance'),
      leading: const Icon(Icons.text_fields_rounded),
      title: Text(l10n.f47P7bAppearanceTile),
      subtitle: Text(
        [
          readingFontNames(l10n, appearance.font).$1,
          l10n.f47P1AppearanceSizeValue((appearance.scale * 100).round()),
          readingHighlightName(l10n, appearance.highlight),
        ].join(' · '),
        key: const Key('settings-reading-appearance-summary'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showReadingAppearanceSettings(context)),
    );
  }
}
