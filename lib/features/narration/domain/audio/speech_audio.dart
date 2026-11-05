/// El audio que la app genera en el teléfono (F47, pasos 5 y 6): de una lista
/// de tramos —cada uno con su texto, su voz y su pausa— a un solo archivo.
///
/// Es el contrato que comparten el podcast (paso 6b) y «Descargar audio» de
/// un documento (paso 5): quien pide arma los tramos y guarda el archivo
/// donde corresponde; quien genera (`SpeechAudioRenderer`) no sabe de
/// podcasts ni de documentos.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Un tramo de lo que se dice: [text] con la voz [voiceId], y [pauseAfter]
/// de silencio después.
///
/// [voiceId] es el id estable de la voz, con el prefijo de quien la hace
/// (`SpeechVoiceIds`): `offline:` una voz sin conexión del catálogo,
/// `device:` una del teléfono y, en el paso 4, las de la nube con el suyo.
@immutable
class SpeechAudioPiece {
  const SpeechAudioPiece({
    required this.text,
    required this.voiceId,
    this.pauseAfter = Duration.zero,
  });

  final String text;
  final String voiceId;
  final Duration pauseAfter;

  @override
  bool operator ==(Object other) =>
      other is SpeechAudioPiece &&
      other.text == text &&
      other.voiceId == voiceId &&
      other.pauseAfter == pauseAfter;

  @override
  int get hashCode => Object.hash(text, voiceId, pauseAfter);

  @override
  String toString() =>
      'SpeechAudioPiece($voiceId, ${pauseAfter.inMilliseconds} '
      'ms, «$text»)';
}

/// La huella de [pieces]: cambia si cambia un texto, una voz o una pausa.
/// Es lo que dice si un audio guardado es de estos tramos con estas voces
/// —el de un podcast (paso 6b), el de un documento (paso 5)—: un audio de
/// otra huella quedó viejo, y no se hace pasar por el de ahora.
String speechAudioFingerprint(List<SpeechAudioPiece> pieces) {
  final digest = sha256.convert(
    utf8.encode(
      jsonEncode([
        for (final piece in pieces)
          [piece.voiceId, piece.pauseAfter.inMilliseconds, piece.text],
      ]),
    ),
  );
  return digest.toString().substring(0, 32);
}

/// Lo que se pide generar.
@immutable
class SpeechAudioRequest {
  const SpeechAudioRequest({required this.workKey, required this.pieces});

  /// De quién es el trabajo, estable entre intentos —`podcast-<creación>`—:
  /// con la misma clave, lo que ya se generó de un intento anterior no se
  /// vuelve a generar. Un solo tramo de carpeta: letras, números, `-` y `_`.
  final String workKey;

  /// Los tramos, en orden. Ninguno vacío.
  final List<SpeechAudioPiece> pieces;
}

/// Lo que quedó: el archivo, cuánto dura y dónde empieza cada tramo.
@immutable
class SpeechAudioResult {
  const SpeechAudioResult({
    required this.path,
    required this.mimeType,
    required this.duration,
    required this.starts,
  });

  /// La ruta del archivo en el teléfono, dentro de la carpeta del trabajo:
  /// quien lo pidió lo copia a donde va (la bóveda) y después llama a
  /// `SpeechAudioRenderer.discard`.
  final String path;

  /// `audio/mp4` (M4A, AAC) en Android; `audio/wav` donde no hay con qué
  /// comprimir.
  final String mimeType;

  final Duration duration;

  /// Dónde empieza cada tramo, en el mismo orden que los pedidos: lo que usa
  /// el reproductor para resaltar el que suena.
  final List<Duration> starts;

  /// La extensión del archivo según [mimeType].
  String get extension => mimeType == 'audio/wav' ? 'wav' : 'm4a';
}

/// Cuánto cuesta generar con una voz de la nube (F47, decisión F): el precio
/// por cada mil caracteres dichos, en su moneda. Las voces del teléfono y las
/// sin conexión no tienen precio (`null`).
@immutable
class SpeechAudioPrice {
  const SpeechAudioPrice({
    required this.per1000Characters,
    required this.currency,
  });

  final double per1000Characters;

  /// El código de la moneda: `USD`.
  final String currency;

  /// Lo que cuesta decir [characters] caracteres.
  double costOf(int characters) => characters * per1000Characters / 1000;

  @override
  bool operator ==(Object other) =>
      other is SpeechAudioPrice &&
      other.per1000Characters == per1000Characters &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(per1000Characters, currency);
}

/// Lo que costaría generar algo con voces de la nube: el total y cuántos
/// caracteres lee cada una. Solo existe si alguna voz cobra.
@immutable
class SpeechAudioCost {
  const SpeechAudioCost({
    required this.amount,
    required this.currency,
    required this.characters,
    this.charactersByVoice = const {},
  });

  final double amount;
  final String currency;

  /// Cuántos caracteres van a la nube, en total.
  final int characters;

  /// Cuántos lee cada voz que cobra, por su id: lo que necesita una puerta
  /// que aprueba voz por voz (`cloudReadingGateProvider.approve`, paso 4).
  final Map<String, int> charactersByVoice;
}

/// El costo de generar [pieces] con los precios de [priceOf] (`null` si la
/// voz es gratis), o `null` si ninguna voz cobra. Con monedas distintas no se
/// suman: se dice la primera y lo demás se cuenta en caracteres —el paso 4
/// tiene una sola nube—.
SpeechAudioCost? speechAudioCostOf(
  Iterable<SpeechAudioPiece> pieces,
  SpeechAudioPrice? Function(String voiceId) priceOf,
) {
  var amount = 0.0;
  var characters = 0;
  final byVoice = <String, int>{};
  String? currency;
  for (final piece in pieces) {
    final price = priceOf(piece.voiceId);
    if (price == null) continue;
    currency ??= price.currency;
    characters += piece.text.length;
    byVoice[piece.voiceId] = (byVoice[piece.voiceId] ?? 0) + piece.text.length;
    if (price.currency == currency) amount += price.costOf(piece.text.length);
  }
  if (currency == null) return null;
  return SpeechAudioCost(
    amount: amount,
    currency: currency,
    characters: characters,
    charactersByVoice: byVoice,
  );
}

/// Por qué no se pudo generar.
enum SpeechAudioFailure {
  /// Una voz no está en el teléfono —se borró, o nunca se bajó— o nadie sabe
  /// hacerla en este dispositivo.
  voiceMissing,

  /// El motor de una voz falló al decir un tramo.
  engine,

  /// No se pudo armar o comprimir el archivo: el disco, el codificador.
  file,
}

/// No se pudo generar el audio; [voiceId] es la voz que faltó o falló.
class SpeechAudioException implements Exception {
  const SpeechAudioException(this.failure, {this.voiceId, this.detail});

  final SpeechAudioFailure failure;
  final String? voiceId;

  /// Solo para el registro, nunca para mostrar.
  final String? detail;

  @override
  String toString() =>
      'No se pudo generar el audio (${failure.name}'
      '${voiceId == null ? '' : ', $voiceId'}): ${detail ?? ''}';
}

/// Quien sabe decir un tramo con ciertas voces y dejarlo en un WAV (F47): las
/// sin conexión, las del teléfono y, en el paso 4, las de la nube. El
/// `SpeechAudioRenderer` le pide a cada uno lo suyo.
abstract interface class SpeechVoiceRenderer {
  /// Si [voiceId] es de las suyas —por su prefijo—, esté o no lista.
  bool owns(String voiceId);

  /// Si [voiceId] puede decir algo ya, sin bajar nada.
  Future<bool> isReady(String voiceId);

  /// Lo que cobra [voiceId], o `null` si es gratis: el enganche de las voces
  /// de la nube (paso 4, decisión F). Con precio, antes de generar se dice el
  /// costo y se pide confirmación.
  SpeechAudioPrice? priceOf(String voiceId);

  /// Una marca de la versión de la voz y del motor: si cambia, lo que ya se
  /// había generado con ella no se reusa.
  String versionOf(String voiceId);

  /// Dice [text] con [voiceId] y deja el audio en [outputPath]: en WAV o en
  /// cualquier formato que el sistema sepa decodificar —el MP3 de una voz de
  /// la nube (paso 4)—, que la pieza común lleva a WAV antes de armar.
  /// Devuelve cuánto dura, o cero si no se sabe. Falla con
  /// [SpeechAudioException].
  Future<Duration> render({
    required String voiceId,
    required String text,
    required String outputPath,
  });
}

/// Los prefijos de los ids de las voces.
abstract final class SpeechVoiceIds {
  /// Una voz sin conexión del catálogo: `offline:<OfflineVoice.id>`.
  static const offlinePrefix = 'offline:';

  /// Una voz del teléfono: `device:<acento>:<nombre>`; sin nombre, la que el
  /// teléfono use para ese acento (`device:es:`).
  static const devicePrefix = 'device:';

  static String offline(String catalogId) => '$offlinePrefix$catalogId';

  static String device({required String locale, String name = ''}) =>
      '$devicePrefix$locale:$name';

  /// El id del catálogo de [id] si es una voz sin conexión.
  static String? offlineIdOf(String id) =>
      id.startsWith(offlinePrefix) ? id.substring(offlinePrefix.length) : null;

  /// El acento y el nombre de [id] si es una voz del teléfono; el nombre
  /// vacío es la del teléfono para ese acento.
  static ({String locale, String name})? deviceOf(String id) {
    if (!id.startsWith(devicePrefix)) return null;
    final rest = id.substring(devicePrefix.length);
    final colon = rest.indexOf(':');
    if (colon <= 0) return null;
    return (locale: rest.substring(0, colon), name: rest.substring(colon + 1));
  }
}
