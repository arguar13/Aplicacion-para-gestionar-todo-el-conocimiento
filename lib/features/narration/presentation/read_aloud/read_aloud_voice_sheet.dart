import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/accent_names.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El panel de voz y acento del lector flotante (F25).
///
/// Primero el **acento** —el idioma y la región de la voz: "Español
/// (Argentina)", "English (United States)"—, uno por cada locale de las
/// voces instaladas, los del idioma de la app primero; después las **voces**
/// de ese acento. Elegir un acento ya pasa a leer con él —con su primera
/// voz—, y elegir una voz la usa en el acto, con la lectura en marcha. Arriba
/// de todo, la voz del sistema: la que el teléfono tenga elegida.
class ReadAloudVoiceSheet extends ConsumerStatefulWidget {
  const ReadAloudVoiceSheet({super.key});

  @override
  ConsumerState<ReadAloudVoiceSheet> createState() =>
      _ReadAloudVoiceSheetState();
}

class _ReadAloudVoiceSheetState extends ConsumerState<ReadAloudVoiceSheet> {
  /// El acento que se está mirando; `null` hasta que se elija uno —se ve el
  /// de la voz de ahora, o el primero—.
  String? _accent;

  /// El acento elegido, para traerlo a la vista al abrir: con decenas de
  /// acentos, el de la voz de ahora puede quedar lejos a la derecha.
  final _selectedAccentKey = GlobalKey();
  var _revealedSelected = false;

  void _revealSelectedAccent() {
    if (_revealedSelected) return;
    _revealedSelected = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _selectedAccentKey.currentContext;
      if (chip == null) return;
      unawaited(Scrollable.ensureVisible(chip, alignment: 0.5));
    });
  }

  void _select(NarrationVoice? voice) {
    if (voice == ref.read(readAloudControllerProvider).voice) return;
    unawaited(ref.read(readAloudControllerProvider.notifier).setVoice(voice));
  }

  void _selectAccent(
    String accent,
    List<NarrationVoice> voices,
    NarrationVoice? current,
  ) {
    setState(() => _accent = accent);
    if (current != null && normalizeAccent(current.locale) == accent) return;
    _select(voices.first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final current = ref.watch(
      readAloudControllerProvider.select((s) => s.voice),
    );
    final voices = ref.watch(narrationVoicesProvider);
    final appLanguage = Localizations.localeOf(context).languageCode;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.readAloudVoice,
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            _VoiceTile(
              key: const Key('read-aloud-system-voice'),
              title: l10n.readAloudSystemVoice,
              subtitle: l10n.readAloudSystemVoiceHint,
              selected: current == null,
              onTap: () => _select(null),
            ),
            ...voices.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: LinearProgressIndicator(),
                ),
              ],
              error: (_, _) => [_NoVoices(message: l10n.readAloudNoVoices)],
              data: (all) {
                if (all.isEmpty) {
                  return [_NoVoices(message: l10n.readAloudNoVoices)];
                }
                final byAccent = groupVoicesByAccent(all, appLanguage);
                final ofCurrent = current == null
                    ? null
                    : normalizeAccent(current.locale);
                final accent =
                    _accent ??
                    (byAccent.containsKey(ofCurrent)
                        ? ofCurrent!
                        : byAccent.keys.first);
                final inAccent = byAccent[accent]!;
                _revealSelectedAccent();
                return [
                  _SectionLabel(l10n.readAloudAccent),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (final entry in byAccent.entries)
                          Padding(
                            key: entry.key == accent
                                ? _selectedAccentKey
                                : null,
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: Key('read-aloud-accent-${entry.key}'),
                              label: Text(accentDisplayName(entry.key)),
                              selected: entry.key == accent,
                              onSelected: (_) => _selectAccent(
                                entry.key,
                                entry.value,
                                current,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _SectionLabel(l10n.readAloudVoiceSection),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final (index, voice) in inAccent.indexed)
                          _VoiceTile(
                            key: Key('read-aloud-voice-${voice.name}'),
                            title: _looksLikeCode(voice.name)
                                ? l10n.readAloudVoiceNumber(index + 1)
                                : voice.name,
                            subtitle: switch (_whereItRuns(voice)) {
                              _Runs.onDevice => l10n.readAloudVoiceOnDevice,
                              _Runs.online => l10n.readAloudVoiceNeedsInternet,
                              _Runs.unknown => null,
                            },
                            selected: voice == current,
                            onTap: () => _select(voice),
                          ),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Las voces por acento, en el orden del panel: primero los acentos del
/// idioma de la app —[appLanguage]—, después el resto, por nombre; y dentro
/// de cada uno, las que andan sin conexión primero.
Map<String, List<NarrationVoice>> groupVoicesByAccent(
  List<NarrationVoice> voices,
  String appLanguage,
) {
  final grouped = <String, List<NarrationVoice>>{};
  for (final voice in voices) {
    (grouped[normalizeAccent(voice.locale)] ??= []).add(voice);
  }
  int byPreference(String a, String b) {
    final aFirst = accentLanguage(a) == appLanguage;
    final bFirst = accentLanguage(b) == appLanguage;
    if (aFirst != bFirst) return aFirst ? -1 : 1;
    return accentDisplayName(
      a,
    ).toLowerCase().compareTo(accentDisplayName(b).toLowerCase());
  }

  return {
    for (final accent in grouped.keys.toList()..sort(byPreference))
      accent: grouped[accent]!
        ..sort((a, b) {
          final byRuns = _whereItRuns(a).index.compareTo(_whereItRuns(b).index);
          return byRuns != 0 ? byRuns : a.name.compareTo(b.name);
        }),
  };
}

enum _Runs { onDevice, online, unknown }

/// Android nombra sus voces con un código —`es-us-x-esd-local`,
/// `es-us-x-esd-network`—: lo de al final dice si anda sin conexión.
_Runs _whereItRuns(NarrationVoice voice) {
  final name = voice.name.toLowerCase();
  if (name.contains('network')) return _Runs.online;
  if (name.contains('local')) return _Runs.onDevice;
  return _Runs.unknown;
}

/// Un nombre que es un código y no un nombre —`es-us-x-esd-local`—: mejor
/// "Voz 1" que eso. Las voces con nombre de verdad —"Mónica" en iOS— se
/// muestran tal cual.
bool _looksLikeCode(String name) => RegExp(
  r'^[a-z]{2,3}[-_][a-z]{2,3}([-_]|$)',
  caseSensitive: false,
).hasMatch(name);

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Una opción del panel, con su marca de elegida como un botón de radio.
class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = this.subtitle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _NoVoices extends StatelessWidget {
  const _NoVoices({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
