/// Lo que se elige en la hoja del podcast (F47, punto 5 del plan): el formato,
/// la duración y las voces, guardado en `StudyCreation.options` con claves y
/// valores estables —nunca el texto traducido—.
library;

import 'package:flutter/foundation.dart';

/// Las claves de las opciones del podcast.
abstract final class PodcastOptionKeys {
  /// El formato ([PodcastFormat.storageKey]).
  static const format = 'format';

  /// La duración ([PodcastLength.storageKey]).
  static const length = 'length';

  /// Las voces: una lista de [PodcastVoiceChoice.toJson], una por persona que
  /// habla.
  static const voices = 'voices';
}

/// Cuántas palabras por minuto se dicen en un podcast: el ritmo de una
/// lectura en voz alta clara, ni apurada ni lenta. Con esto la duración
/// pedida se mide en palabras.
const kPodcastWordsPerMinute = 150;

/// Cómo se cuenta el podcast (punto 5 del plan).
enum PodcastFormat {
  /// «Breve»: lo esencial, directo, con una voz.
  brief('brief'),

  /// «Clase»: para aprender, con preguntas a quien escucha.
  lesson('lesson'),

  /// «Relato»: contado como una historia.
  story('story'),

  /// «Conversación»: dos voces que charlan y se repreguntan.
  conversation('conversation');

  const PodcastFormat(this.storageKey);

  final String storageKey;

  /// Cuántas personas hablan: dos en la conversación, una en los demás.
  int get speakerCount => this == conversation ? 2 : 1;

  /// Quiénes hablan, en orden.
  List<PodcastSpeaker> get speakers =>
      PodcastSpeaker.values.take(speakerCount).toList();

  /// El de [options]; si no hay o no se entiende, «Conversación», el de
  /// fábrica.
  static PodcastFormat of(Map<String, Object?> options) =>
      fromStorageKey(options[PodcastOptionKeys.format]) ?? conversation;

  static PodcastFormat? fromStorageKey(Object? key) {
    for (final format in values) {
      if (format.storageKey == key) return format;
    }
    return null;
  }
}

/// Cuánto dura: Corto ~3 min · Medio ~8 · Largo ~15.
enum PodcastLength {
  short('short', 3),
  medium('medium', 8),
  long('long', 15);

  const PodcastLength(this.storageKey, this.minutes);

  final String storageKey;

  /// Los minutos que se piden.
  final int minutes;

  /// Las palabras que dan esos minutos, a [kPodcastWordsPerMinute].
  int get targetWords => minutes * kPodcastWordsPerMinute;

  /// La de [options]; si no hay o no se entiende, «Medio», la de fábrica.
  static PodcastLength of(Map<String, Object?> options) =>
      fromStorageKey(options[PodcastOptionKeys.length]) ?? medium;

  static PodcastLength? fromStorageKey(Object? key) {
    for (final length in values) {
      if (length.storageKey == key) return length;
    }
    return null;
  }
}

/// Quién habla en un tramo: la primera voz ([a]) y, en la conversación, la
/// segunda ([b]). En la conversación, la A conduce y pregunta, y la B explica.
enum PodcastSpeaker {
  a('a'),
  b('b');

  const PodcastSpeaker(this.storageKey);

  final String storageKey;

  static PodcastSpeaker? fromStorageKey(Object? key) {
    for (final speaker in values) {
      if (speaker.storageKey == key) return speaker;
    }
    return null;
  }
}

/// La voz elegida para una persona que habla, como dato: [voiceId] es el id
/// estable de la voz, con el prefijo de dónde sale —`device:` para una voz del
/// teléfono ([PodcastVoiceId.device])—, y `null` es la voz del teléfono que
/// esté elegida por defecto.
///
/// Se guarda así, y no como una voz del motor, para que la biblioteca de voces
/// (F47, paso 3) sume las suyas con su propio prefijo sin migrar nada: el audio
/// (la segunda parte del paso 6) resuelve cada id con quien corresponda.
@immutable
class PodcastVoiceChoice {
  const PodcastVoiceChoice({required this.speaker, this.voiceId});

  final PodcastSpeaker speaker;
  final String? voiceId;

  Map<String, Object?> toJson() => {
    'speaker': speaker.storageKey,
    'voiceId': voiceId,
  };

  @override
  bool operator ==(Object other) =>
      other is PodcastVoiceChoice &&
      other.speaker == speaker &&
      other.voiceId == voiceId;

  @override
  int get hashCode => Object.hash(speaker, voiceId);

  @override
  String toString() => 'PodcastVoiceChoice(${speaker.storageKey}, $voiceId)';
}

/// Las voces de un podcast: exactamente una por persona que habla en su
/// formato —dos en la conversación—, en orden.
abstract final class PodcastCast {
  /// Las de [options] para [format]: la elegida para cada persona, o la del
  /// teléfono por defecto si no se eligió. Lo que no se entiende se ignora, y
  /// lo que sobra —la segunda voz de una conversación que pasó a «Breve»— no
  /// cuenta.
  static List<PodcastVoiceChoice> of(
    Map<String, Object?> options,
    PodcastFormat format,
  ) {
    final chosen = <PodcastSpeaker, String?>{};
    final raw = options[PodcastOptionKeys.voices];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final speaker = PodcastSpeaker.fromStorageKey(item['speaker']);
        if (speaker == null || chosen.containsKey(speaker)) continue;
        final id = item['voiceId'];
        chosen[speaker] = id is String && id.trim().isNotEmpty
            ? id.trim()
            : null;
      }
    }
    return [
      for (final speaker in format.speakers)
        PodcastVoiceChoice(speaker: speaker, voiceId: chosen[speaker]),
    ];
  }

  /// [cast] ajustado a las voces que hay ([available], los ids en el orden en
  /// que conviene ofrecerlas, todas del idioma del podcast; decisión L de
  /// F47: la voz sigue al idioma):
  ///
  /// - una voz del teléfono que ya no está en [available] —de otro idioma, o
  ///   desinstalada— se suelta;
  /// - quien no tiene voz recibe la primera de [available] que no use otra
  ///   persona: en la conversación, **dos voces distintas** si hay al menos
  ///   dos; con una sola, las dos personas la comparten;
  /// - una voz de otro lado —la biblioteca de voces— se deja como está: la
  ///   resuelve quien la conoce.
  ///
  /// Sin ninguna en [available], todas quedan en la del teléfono (`null`).
  static List<PodcastVoiceChoice> fit(
    List<PodcastVoiceChoice> cast, {
    required List<String> available,
  }) {
    bool stays(String? id) =>
        id != null &&
        (!id.startsWith(PodcastVoiceId.devicePrefix) || available.contains(id));
    final kept = [
      for (final choice in cast)
        if (stays(choice.voiceId))
          choice
        else
          PodcastVoiceChoice(speaker: choice.speaker),
    ];
    if (available.isEmpty) return kept;
    final used = {for (final c in kept) ?c.voiceId};
    return [
      for (final choice in kept)
        if (choice.voiceId != null)
          choice
        else
          PodcastVoiceChoice(
            speaker: choice.speaker,
            voiceId: _take(available, used),
          ),
    ];
  }

  /// La primera de [available] que no está en [used] —o, si ya se usaron
  /// todas, la primera—, y la anota como usada.
  static String _take(List<String> available, Set<String> used) {
    final free = available.where((id) => !used.contains(id)).firstOrNull;
    final id = free ?? available.first;
    used.add(id);
    return id;
  }

  /// [voices] como se guardan en las opciones.
  static List<Map<String, Object?>> toOptions(
    List<PodcastVoiceChoice> voices,
  ) => [for (final voice in voices) voice.toJson()];
}

/// Los ids de las voces: de dónde sale cada una y cómo se vuelve a encontrar.
abstract final class PodcastVoiceId {
  /// El prefijo de las voces del teléfono.
  static const devicePrefix = 'device:';

  /// El id de la voz del teléfono [name], de acento [locale]:
  /// `device:es-AR:es-ar-x-esd-local`.
  static String device({required String locale, required String name}) =>
      '$devicePrefix$locale:$name';

  /// El acento y el nombre de [id] si es una voz del teléfono; `null` si es
  /// de otro lado o no se entiende.
  static ({String locale, String name})? parseDevice(String id) {
    if (!id.startsWith(devicePrefix)) return null;
    final rest = id.substring(devicePrefix.length);
    final colon = rest.indexOf(':');
    if (colon <= 0 || colon == rest.length - 1) return null;
    return (locale: rest.substring(0, colon), name: rest.substring(colon + 1));
  }
}
