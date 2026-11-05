import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';

/// Lo hecho de un podcast que se está generando, guardado para retomarlo si
/// la app se cierra a mitad (F47, paso 6b; `CreationJob.checkpoint`):
///
/// - mientras se escribe el guion, las vueltas ya escritas
///   ([PodcastScriptProgress]): un Largo con Gemma que se corta en la vuelta
///   6 de 8 sigue en la 7, no vuelve a empezar;
/// - con el guion terminado, el guion entero, listo para la voz
///   ([PodcastVoiceProgress]): retomar no vuelve a llamar a la IA.
@immutable
sealed class PodcastProgress {
  const PodcastProgress();

  /// Lo guardado en [json], o `null` si no hay, no se entiende o es de otra
  /// versión: se empieza de cero.
  static PodcastProgress? decode(String? json) {
    if (json == null) return null;
    final Object? raw;
    try {
      raw = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['v'] != _version) return null;
    switch (raw['stage']) {
      case 'script':
        final key = raw['key'];
        final rounds = raw['rounds'];
        if (key is! String || rounds is! List) return null;
        final done = <PodcastRoundDone>[];
        for (final round in rounds) {
          if (round is! Map) return null;
          final segments = PodcastJson.decodeSegments(round['segments']);
          // Una vuelta guardada siempre tiene tramos: sin ellos, no es de
          // fiar lo que sigue.
          if (segments.isEmpty) return null;
          done.add(
            PodcastRoundDone(
              segments: segments,
              discarded: PodcastJson.decodeDiscarded(round['discarded']),
            ),
          );
        }
        final title = raw['title'];
        return PodcastScriptProgress(
          key: key,
          title: title is String ? title : '',
          rounds: done,
        );
      case 'voice':
        final podcast = PodcastJson.decode(raw['podcast']);
        return podcast == null
            ? null
            : PodcastVoiceProgress(
                podcast,
                keepTitle: raw['keepTitle'] == true,
              );
    }
    return null;
  }

  static const _version = 1;

  String encode();
}

/// Una vuelta del guion ya escrita y comprobada.
@immutable
class PodcastRoundDone {
  const PodcastRoundDone({required this.segments, this.discarded = const []});

  final List<PodcastSegment> segments;
  final List<PodcastDiscard> discarded;
}

/// Las vueltas ya escritas de un guion, del pedido [key]
/// ([podcastScriptKey]): solo valen para el mismo pedido sobre el mismo
/// material y con el mismo reparto en vueltas.
@immutable
class PodcastScriptProgress extends PodcastProgress {
  const PodcastScriptProgress({
    required this.key,
    required this.title,
    required this.rounds,
  });

  final String key;

  /// El título que puso la primera vuelta.
  final String title;

  final List<PodcastRoundDone> rounds;

  @override
  String encode() => jsonEncode({
    'v': PodcastProgress._version,
    'stage': 'script',
    'key': key,
    'title': title,
    'rounds': [
      for (final round in rounds)
        {
          'segments': PodcastJson.encodeSegments(round.segments),
          'discarded': PodcastJson.encodeDiscarded(round.discarded),
        },
    ],
  });
}

/// El guion terminado, esperando su voz.
@immutable
class PodcastVoiceProgress extends PodcastProgress {
  const PodcastVoiceProgress(this.podcast, {this.keepTitle = false});

  final Podcast podcast;

  /// Si se conserva el título que tiene la creación: el audio lo pidió la
  /// persona sobre un podcast ya listo, que quizá renombró. Al retomar una
  /// generación a mitad, va el título nuevo.
  final bool keepTitle;

  @override
  String encode() => jsonEncode({
    'v': PodcastProgress._version,
    'stage': 'voice',
    'podcast': PodcastJson.encode(podcast),
    if (keepTitle) 'keepTitle': true,
  });
}

/// La clave de un guion: todo lo que, si cambia, hace que las vueltas ya
/// escritas no sirvan —el pedido, el material leído y en cuántas vueltas se
/// reparte, que depende de la ventana del modelo—.
String podcastScriptKey({
  required String format,
  required String length,
  required String? focus,
  required String languageCode,
  required int targetWords,
  required int rounds,
  required int perRound,
  required Iterable<String> material,
}) {
  final digest = sha256.convert(
    utf8.encode(
      jsonEncode([
        format,
        length,
        focus ?? '',
        languageCode,
        targetWords,
        rounds,
        perRound,
        ...material,
      ]),
    ),
  );
  return digest.toString().substring(0, 32);
}
