import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/transcript_timestamps.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/speech_segmentation.dart';
import 'package:sinapsis/features/narration/domain/services/text_to_speech_service.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_providers.dart';
import 'package:sinapsis/features/narration/presentation/providers/narration_settings_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

enum _PlaybackState { idle, playing, paused }

/// Lee [text] en voz alta, con controles de reproducir, pausar, retroceder
/// y adelantar un fragmento, volver al principio, y elegir voz y
/// velocidad.
///
/// Colapsado es solo el botón "Escuchar"; tocarlo abre la barra de
/// controles y arranca a leer de una. Pensado para colgarse al final de
/// cualquier bloque de texto —la transcripción de un audio o video, un
/// documento recién importado, la página actual del lector de libros—, ver
/// la decisión 28 en docs/arquitectura.md.
///
/// **Sin verdadero pausar a mitad de oración.** El texto se divide en
/// fragmentos cortos (`splitIntoSpeechSegments`, por oración) y "pausar" es
/// simplemente no pedir el próximo fragmento todavía — retomar vuelve a
/// leer el fragmento en el que se quedó, desde su principio. Es la misma
/// razón por la que "retroceder" y "adelantar" cambian de fragmento entero
/// y no de milisegundo: no existe un `seek` real sobre voz sintetizada que
/// nunca se decodificó a un buffer navegable, y las tres plataformas que
/// soporta esta app resuelven "pausar y seguir" de formas demasiado
/// distintas como para prometer que se retoma exactamente en la palabra
/// donde se cortó.
class NarrationPlayer extends ConsumerStatefulWidget {
  const NarrationPlayer({required this.text, super.key});

  final String text;

  @override
  ConsumerState<NarrationPlayer> createState() => _NarrationPlayerState();
}

class _NarrationPlayerState extends ConsumerState<NarrationPlayer> {
  var _expanded = false;
  var _state = _PlaybackState.idle;
  var _index = 0;
  List<String> _segments = const [];
  StreamSubscription<NarrationEvent>? _eventsSubscription;

  /// Guardado en `initState`, no leído con `ref.read` en cada uso: `ref`
  /// ya no se puede usar en `dispose` una vez que el widget se
  /// desmontó, y ahí es justamente donde hace falta poder cortar la
  /// lectura en curso.
  late final TextToSpeechService _service = ref.read(
    textToSpeechServiceProvider,
  );

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    if (_state != _PlaybackState.idle) {
      unawaited(_service.stop());
    }
    super.dispose();
  }

  Future<void> _open() async {
    _segments = splitIntoSpeechSegments(
      hasTimestamps(widget.text) ? stripTimestamps(widget.text) : widget.text,
    );
    if (_segments.isEmpty) return;

    _eventsSubscription ??= _service.events.listen(_onEvent);
    setState(() {
      _expanded = true;
      _index = 0;
    });
    await _speakCurrent();
  }

  void _onEvent(NarrationEvent event) {
    if (!mounted || _state != _PlaybackState.playing) return;
    switch (event) {
      case NarrationEvent.completed:
        unawaited(_advance());
      case NarrationEvent.error:
        setState(() => _state = _PlaybackState.paused);
    }
  }

  Future<void> _advance() async {
    if (_index + 1 >= _segments.length) {
      setState(() {
        _state = _PlaybackState.idle;
        _expanded = false;
        _index = 0;
      });
      return;
    }
    setState(() => _index++);
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    final settings = ref.read(narrationSettingsNotifierProvider);
    await _service.setVoice(settings.voice);
    await _service.setSpeed(settings.speed);
    setState(() => _state = _PlaybackState.playing);
    await _service.speak(_segments[_index]);
  }

  Future<void> _togglePlayPause() async {
    if (_state == _PlaybackState.playing) {
      await _service.stop();
      setState(() => _state = _PlaybackState.paused);
    } else {
      await _speakCurrent();
    }
  }

  Future<void> _restart() async {
    setState(() => _index = 0);
    if (_state == _PlaybackState.playing) await _speakCurrent();
  }

  Future<void> _rewind() async {
    if (_index == 0) return;
    setState(() => _index--);
    if (_state == _PlaybackState.playing) await _speakCurrent();
  }

  Future<void> _forward() async {
    if (_index + 1 >= _segments.length) return;
    setState(() => _index++);
    if (_state == _PlaybackState.playing) await _speakCurrent();
  }

  Future<void> _close() async {
    await _service.stop();
    setState(() {
      _state = _PlaybackState.idle;
      _expanded = false;
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.text.trim().isEmpty) return const SizedBox.shrink();

    if (!_expanded) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.volume_up_outlined, size: 18),
          label: Text(l10n.narrationListenAction),
          onPressed: _open,
        ),
      );
    }

    return _PlayerBar(
      playing: _state == _PlaybackState.playing,
      current: _index + 1,
      total: _segments.length,
      onRestart: _restart,
      onRewind: _index > 0 ? _rewind : null,
      onTogglePlayPause: _togglePlayPause,
      onForward: _index + 1 < _segments.length ? _forward : null,
      onSettings: () => _openSettings(context),
      onClose: _close,
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _NarrationSettingsSheet(),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.playing,
    required this.current,
    required this.total,
    required this.onRestart,
    required this.onRewind,
    required this.onTogglePlayPause,
    required this.onForward,
    required this.onSettings,
    required this.onClose,
  });

  final bool playing;
  final int current;
  final int total;
  final VoidCallback onRestart;
  final VoidCallback? onRewind;
  final VoidCallback onTogglePlayPause;
  final VoidCallback? onForward;
  final VoidCallback onSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.replay),
            tooltip: l10n.narrationRestartTooltip,
            onPressed: onRestart,
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: l10n.narrationRewindTooltip,
            onPressed: onRewind,
          ),
          IconButton.filled(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            tooltip: playing
                ? l10n.narrationPauseTooltip
                : l10n.narrationPlayTooltip,
            onPressed: onTogglePlayPause,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: l10n.narrationForwardTooltip,
            onPressed: onForward,
          ),
          Expanded(
            child: Text(
              l10n.narrationProgress(current, total),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.narrationSettingsTooltip,
            onPressed: onSettings,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.narrationCloseTooltip,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _NarrationSettingsSheet extends ConsumerWidget {
  const _NarrationSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.watch(narrationSettingsNotifierProvider);
    final voicesAsync = ref.watch(narrationVoicesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.narrationSettingsTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.narrationSpeedSectionTitle,
              style: theme.textTheme.titleSmall,
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: settings.speed,
                    min: 0.5,
                    max: 2,
                    divisions: 6,
                    label: l10n.narrationSpeedValue(
                      settings.speed.toStringAsFixed(2),
                    ),
                    onChanged: (value) => ref
                        .read(narrationSettingsNotifierProvider.notifier)
                        .setSpeed(value),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    l10n.narrationSpeedValue(settings.speed.toStringAsFixed(2)),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.narrationVoiceSectionTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: voicesAsync.when(
                data: (voices) =>
                    _VoiceList(voices: voices, selected: settings.voice),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) =>
                    _VoiceList(voices: const [], selected: settings.voice),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceList extends ConsumerWidget {
  const _VoiceList({required this.voices, required this.selected});

  final List<NarrationVoice> voices;
  final NarrationVoice? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sorted = [...voices]
      ..sort((a, b) {
        final byLocale = a.locale.compareTo(b.locale);
        return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
      });

    return RadioGroup<NarrationVoice?>(
      groupValue: selected,
      onChanged: (voice) => ref
          .read(narrationSettingsNotifierProvider.notifier)
          .selectVoice(voice),
      child: ListView(
        shrinkWrap: true,
        children: [
          RadioListTile<NarrationVoice?>(
            dense: true,
            title: Text(l10n.narrationSystemDefaultVoice),
            value: null,
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.narrationNoVoicesAvailable,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final voice in sorted)
              RadioListTile<NarrationVoice?>(
                dense: true,
                title: Text(voice.name),
                subtitle: Text(voice.locale),
                value: voice,
              ),
        ],
      ),
    );
  }
}
