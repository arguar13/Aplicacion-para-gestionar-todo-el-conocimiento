import 'dart:convert';

import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_check.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';

/// Lo que escribió la IA para una vuelta del guion, antes de comprobarlo: su
/// título, si lo dio, y sus tramos.
typedef PodcastDraft = ({String title, List<PodcastDraftSegment> segments});

/// El podcast como JSON (F47, decisión G de F43): lo que contesta la IA
/// ([readDraft], con tolerancia) y lo que se guarda en
/// `StudyCreation.content` ([encode] y [decode], la versión
/// [contentVersion]).
abstract final class PodcastJson {
  /// La versión del esquema de lo guardado.
  static const contentVersion = 1;

  /// Lee con tolerancia lo que contestó la IA, como lee F43 sus creaciones:
  /// la lista de tramos sola o dentro de un objeto, las claves en español o
  /// en inglés, una cita como texto o como objeto, el que habla con cualquier
  /// nombre. Lo que no es un tramo con texto se ignora; no lanza nunca.
  static PodcastDraft readDraft(Object? json) {
    if (json is List) return (title: '', segments: _segments(json));
    if (json is! Map) return (title: '', segments: const []);
    final map = _normalize(json);
    final title = _text(map['title']);
    var raw = map['segments'];
    if (raw is Map) {
      // `{"script": {"segments": [...]}}`: un nivel de más.
      final inner = _normalize(raw);
      raw =
          inner['segments'] ??
          raw.values.whereType<List<Object?>>().firstOrNull;
    }
    return (title: title, segments: _segments(raw));
  }

  static List<PodcastDraftSegment> _segments(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          ?_segment(_normalize(item))
        else if (item is String && item.trim().isNotEmpty)
          PodcastDraftSegment(speaker: '', text: item.trim()),
    ];
  }

  static PodcastDraftSegment? _segment(Map<String, Object?> map) {
    final text = _text(map['text']);
    if (text.isEmpty) return null;
    final quotes = <PodcastDraftQuote>[];
    void addQuote(Object? raw, {String? source}) {
      if (raw is String && raw.trim().isNotEmpty) {
        quotes.add(PodcastDraftQuote(raw.trim(), source: source));
      } else if (raw is Map) {
        final inner = _normalize(raw);
        final quote = inner['quote'];
        final from = _text(inner['source']);
        if (quote is String && quote.trim().isNotEmpty) {
          quotes.add(
            PodcastDraftQuote(
              quote.trim(),
              source: from.isEmpty ? source : from,
            ),
          );
        }
      } else if (raw is List) {
        for (final each in raw) {
          addQuote(each, source: source);
        }
      }
    }

    final source = _text(map['source']);
    addQuote(map['quotes'], source: source.isEmpty ? null : source);
    addQuote(map['quote'], source: source.isEmpty ? null : source);
    final pause = _text(map['pause']).toLowerCase();
    return PodcastDraftSegment(
      speaker: _text(map['speaker']),
      text: text,
      kind: _kind(_text(map['kind'])),
      quotes: quotes,
      longPause: const {'long', 'larga', 'largo', 'true'}.contains(pause),
    );
  }

  static PodcastSegmentKind? _kind(String raw) => switch (raw.toLowerCase()) {
    'link' ||
    'enlace' ||
    'transicion' ||
    'transición' ||
    'transition' => PodcastSegmentKind.link,
    'data' ||
    'dato' ||
    'datos' ||
    'fact' ||
    'content' => PodcastSegmentKind.data,
    _ => null,
  };

  /// Lo que se guarda de [podcast].
  static Map<String, Object?> encode(Podcast podcast) => {
    'title': podcast.title,
    'format': podcast.format.storageKey,
    'length': podcast.length.storageKey,
    'requestedWords': podcast.requestedWords,
    'targetWords': podcast.targetWords,
    'segments': [
      for (final segment in podcast.segments)
        {
          'speaker': segment.speaker.storageKey,
          'kind': segment.kind.storageKey,
          'text': segment.text,
          'pauseMs': segment.pauseAfter.inMilliseconds,
          'citations': [
            for (final citation in segment.citations)
              {
                'quote': citation.quote,
                'documentId': ?citation.documentId,
                'documentTitle': ?citation.documentTitle,
              },
          ],
        },
    ],
    'discarded': [
      for (final discard in podcast.discarded)
        {'reason': discard.reason.storageKey, 'text': discard.text},
    ],
  };

  static String encodeString(Podcast podcast) => jsonEncode(encode(podcast));

  /// Lo guardado de [json] (un `Map` o su texto), o `null` si no es un
  /// podcast con al menos un tramo. Lo que no se entiende de un tramo —una
  /// cita sin texto— se ignora; un tramo sin texto no cuenta.
  static Podcast? decode(Object? json) {
    final raw = json is String ? _tryJson(json) : json;
    if (raw is! Map) return null;
    final segments = <PodcastSegment>[];
    for (final item
        in raw['segments'] is List ? raw['segments']! as List : []) {
      if (item is! Map) continue;
      final text = item['text'];
      if (text is! String || text.trim().isEmpty) continue;
      final pause = item['pauseMs'];
      segments.add(
        PodcastSegment(
          speaker:
              PodcastSpeaker.fromStorageKey(item['speaker']) ??
              PodcastSpeaker.a,
          text: text,
          kind:
              PodcastSegmentKind.fromStorageKey(item['kind']) ??
              PodcastSegmentKind.data,
          pauseAfter: Duration(
            milliseconds: pause is num ? pause.round().clamp(0, 10000) : 0,
          ),
          citations: [
            for (final c
                in item['citations'] is List
                    ? item['citations']! as List
                    : const [])
              if (c is Map && c['quote'] is String)
                PodcastCitation(
                  quote: c['quote']! as String,
                  documentId: c['documentId'] is String
                      ? c['documentId']! as String
                      : null,
                  documentTitle: c['documentTitle'] is String
                      ? c['documentTitle']! as String
                      : null,
                ),
          ],
        ),
      );
    }
    if (segments.isEmpty) return null;
    final length =
        PodcastLength.fromStorageKey(raw['length']) ?? PodcastLength.medium;
    int words(Object? value) =>
        value is num ? value.round() : length.targetWords;
    return Podcast(
      title: raw['title'] is String ? raw['title']! as String : '',
      format:
          PodcastFormat.fromStorageKey(raw['format']) ??
          PodcastFormat.conversation,
      length: length,
      segments: segments,
      requestedWords: words(raw['requestedWords']),
      targetWords: words(raw['targetWords']),
      discarded: [
        for (final d
            in raw['discarded'] is List ? raw['discarded']! as List : const [])
          if (d is Map && d['text'] is String)
            if (PodcastDiscardReason.fromStorageKey(d['reason'])
                case final reason?)
              PodcastDiscard(reason: reason, text: d['text']! as String),
      ],
    );
  }

  static Object? _tryJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// Las claves con su nombre canónico.
  static Map<String, Object?> _normalize(Map<Object?, Object?> raw) {
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final folded = _foldKey(entry.key.toString());
      out.putIfAbsent(_aliases[folded] ?? folded, () => entry.value);
    }
    return out;
  }

  static const _aliases = <String, String>{
    // El título.
    'titulo': 'title',
    'episodetitle': 'title',
    // Los tramos.
    'tramos': 'segments',
    'script': 'segments',
    'guion': 'segments',
    'lines': 'segments',
    'lineas': 'segments',
    'dialogue': 'segments',
    'dialogo': 'segments',
    'turns': 'segments',
    'turnos': 'segments',
    'parts': 'segments',
    'partes': 'segments',
    // Quién habla.
    'voz': 'speaker',
    'voice': 'speaker',
    'hablante': 'speaker',
    'who': 'speaker',
    'quien': 'speaker',
    'role': 'speaker',
    'rol': 'speaker',
    'persona': 'speaker',
    // Lo que dice.
    'texto': 'text',
    'line': 'text',
    'linea': 'text',
    'says': 'text',
    'dice': 'text',
    'content': 'text',
    'contenido': 'text',
    'speech': 'text',
    // Qué clase de tramo.
    'tipo': 'kind',
    'type': 'kind',
    'clase': 'kind',
    // Las citas.
    'citas': 'quotes',
    'citations': 'quotes',
    'citaciones': 'quotes',
    'evidence': 'quotes',
    'evidencias': 'quotes',
    'pasajes': 'quotes',
    'passages': 'quotes',
    'cita': 'quote',
    'citation': 'quote',
    'pasaje': 'quote',
    'passage': 'quote',
    'excerpt': 'quote',
    'fragmento': 'quote',
    'extracto': 'quote',
    // De qué documento.
    'fuente': 'source',
    'document': 'source',
    'documento': 'source',
    'doc': 'source',
    'from': 'source',
    'origen': 'source',
    // La pausa.
    'pausa': 'pause',
  };

  static String _foldKey(String key) => key
      .toLowerCase()
      .replaceAll(RegExp('[áàâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp('[^a-z0-9]'), '');

  static String _text(Object? raw) {
    if (raw is! String && raw is! num) return '';
    return raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
