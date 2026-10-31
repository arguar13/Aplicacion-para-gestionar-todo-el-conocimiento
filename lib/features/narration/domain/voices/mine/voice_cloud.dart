import 'package:flutter/foundation.dart';

/// La nube para voces (F47, paso 4, decisiones C y F): ElevenLabs, **solo si
/// la persona la elige**, con su cuenta y su clave, y solo para clonar y crear
/// voces —y leer con ellas—.
///
/// **Lo que se sabe de ElevenLabs, y de dónde sale** (relevado el
/// 31/10/2026; los precios cambian, y por eso se citan):
///
/// - La API, `https://api.elevenlabs.io`, con la clave en la cabecera
///   `xi-api-key` (docs: `api-reference/authentication`).
/// - **Clonar** (clonación instantánea): `POST /v1/voices/add`, multipart con
///   `name`, `files`, `remove_background_noise`, `description` y `labels`;
///   devuelve `voice_id` y `requires_verification`
///   (`api-reference/voices/ivc/create`). Necesita el plan **Starter**, desde
///   **USD 6 por mes** (USD 1 el primer mes); el plan gratis no clona
///   (`elevenlabs.io/pricing`). ElevenLabs no publica un costo en créditos
///   por clonar: ocupa uno de los lugares de voz del plan.
/// - **Crear** (diseño de voces): `POST /v1/text-to-voice/design` con
///   `voice_description` y un `text` de 100 a 1.000 caracteres —o
///   `auto_generate_text`—; devuelve tres propuestas, cada una con su audio
///   y su `generated_voice_id` (`api-reference/text-to-voice/design`). Se
///   guarda la elegida con `POST /v1/text-to-voice`
///   (`voice_name`, `voice_description`, `generated_voice_id`). **Cobra por
///   los caracteres del texto de muestra en cada generación** (centro de
///   ayuda, «How much does Voice Design cost?»); está en todos los planes.
/// - **Leer**: `POST /v1/text-to-speech/{voice_id}` con `text` y `model_id`
///   —de fábrica `eleven_multilingual_v2`, que habla español y acepta hasta
///   10.000 caracteres por pedido— y devuelve el audio, MP3 de fábrica
///   (`api-reference/text-to-speech/convert`, `overview/models`). Con ese
///   modelo, **1 crédito por carácter** (`elevenlabs.io/pricing`: «Text to
///   Speech 1 credit per character»). Los planes traen 10.000 (gratis),
///   30.000 (Starter), 121.000 (Creator) y 600.000 (Pro) créditos por mes.
/// - **Borrar**: `DELETE /v1/voices/{voice_id}`, que contesta
///   `{"status": "ok"}` (`api-reference/voices/delete`).
/// - **Lo gastado**: `GET /v1/user/subscription`, con `tier`,
///   `character_count`, `character_limit`,
///   `next_character_count_reset_unix`, `can_use_instant_voice_cloning`,
///   `voice_limit` y `voice_slots_used`
///   (`api-reference/user/subscription/get`).
/// - **Los errores** llegan como `{"detail": {"code", "message", …}}`: 401
///   clave, 402 sin créditos (`insufficient_credits`), 403 sin permiso o sin
///   plan (`subscription_required`, `feature_not_available`), 404 voz que ya
///   no está, 409 una propuesta que se está generando, 429 demasiados
///   pedidos (`eleven-api/resources/errors`).
/// - **Lo que no se puede evitar**: el modo sin registro (`enable_logging` en
///   `false`) es solo para empresas; ElevenLabs guarda el historial de lo que
///   lee. La app lo dice antes.
abstract final class ElevenLabsFacts {
  static const baseUrl = 'https://api.elevenlabs.io';
  static const keyHeader = 'xi-api-key';

  /// El modelo con que se lee: habla español y es el de fábrica.
  static const readingModel = 'eleven_multilingual_v2';

  /// Créditos por carácter leído con [readingModel].
  static const creditsPerCharacter = 1;

  /// Lo más que se manda en un pedido de lectura con [readingModel].
  static const maxCharactersPerRequest = 10000;

  /// El plan más barato que clona, y lo que cuesta por mes, en dólares.
  static const cloningPlan = 'Starter';
  static const cloningPlanUsdPerMonth = 6;

  /// El largo que pide el diseño de voces para el texto de muestra.
  static const designTextMin = 100;
  static const designTextMax = 1000;

  /// Cuántas propuestas trae cada generación del diseño.
  static const designPreviews = 3;
}

/// Lo que cuesta leer [characters] caracteres con una voz de ElevenLabs, en
/// créditos.
int readingCredits(int characters) =>
    characters * ElevenLabsFacts.creditsPerCharacter;

/// Desde cuántos caracteres leer con una voz de la nube se avisa antes, con
/// su costo (F47, paso 4: «lo largo avisa su costo antes»): unos 1.500
/// caracteres, un minuto y medio de lectura, el 5 % de los créditos del plan
/// Starter.
const cloudLongReadCharacters = 1500;

/// La cuenta de ElevenLabs: el plan y lo gastado este mes.
@immutable
class VoiceCloudAccount {
  const VoiceCloudAccount({
    required this.tier,
    required this.creditsUsed,
    required this.creditLimit,
    required this.canClone,
    this.resetsAt,
    this.voiceSlotsUsed,
    this.voiceLimit,
  });

  /// El plan, como lo nombra ElevenLabs: `free`, `starter`, `creator`…
  final String tier;
  final int creditsUsed;
  final int creditLimit;
  final bool canClone;
  final DateTime? resetsAt;
  final int? voiceSlotsUsed;
  final int? voiceLimit;

  int get creditsLeft =>
      creditLimit - creditsUsed < 0 ? 0 : creditLimit - creditsUsed;

  /// Si queda lugar para otra voz; `null` si no se sabe.
  bool? get hasVoiceSlot {
    final used = voiceSlotsUsed;
    final limit = voiceLimit;
    if (used == null || limit == null) return null;
    return used < limit;
  }
}

/// Una propuesta del diseño de voces: su audio, para oírla, y su id, para
/// guardarla.
@immutable
class DesignedVoicePreview {
  const DesignedVoicePreview({
    required this.generatedVoiceId,
    required this.audio,
    required this.mediaType,
    this.duration,
  });

  final String generatedVoiceId;
  final Uint8List audio;

  /// `audio/mpeg`…
  final String mediaType;
  final Duration? duration;

  /// La extensión del archivo de su audio.
  String get extension => switch (mediaType) {
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/ogg' || 'audio/opus' => 'ogg',
    _ => 'mp3',
  };
}

/// Por qué ElevenLabs no hizo lo pedido.
enum VoiceCloudFailure {
  /// No hay clave cargada.
  noKey,

  /// La clave no sirve (401).
  invalidKey,

  /// Sin créditos este mes (402).
  noCredits,

  /// El plan no lo permite —clonar en el plan gratis— (403).
  planRequired,

  /// La voz ya no está en ElevenLabs (404).
  voiceNotFound,

  /// Demasiados pedidos, o una propuesta que se está generando (409, 429).
  busy,

  /// ElevenLabs falló de su lado (5xx).
  unavailable,

  /// El pedido no le gustó: un audio que no acepta, un texto fuera de largo
  /// (400, 422).
  rejected,

  /// Sin conexión, o no contestó a tiempo.
  network,

  /// Lo que no se esperaba.
  unknown,
}

class VoiceCloudException implements Exception {
  const VoiceCloudException(this.failure, [this.detail]);

  final VoiceCloudFailure failure;

  /// Lo que dijo ElevenLabs, solo para el registro.
  final String? detail;

  @override
  String toString() =>
      'ElevenLabs: ${failure.name}${detail == null ? '' : ' ($detail)'}';
}

/// Lo que la app le pide a la nube de voces. Las pruebas usan un doble:
/// nunca se llama a ElevenLabs de verdad.
abstract interface class VoiceCloud {
  /// El plan y lo gastado; prueba también la clave.
  Future<VoiceCloudAccount> account();

  /// Clona la voz de [samplePath] (el archivo, en el teléfono) y devuelve su
  /// id.
  Future<String> cloneVoice({
    required String name,
    required String samplePath,
    required String description,
  });

  /// Tres propuestas para [description], diciendo [text].
  Future<List<DesignedVoicePreview>> designPreviews({
    required String description,
    required String text,
  });

  /// Guarda la propuesta [generatedVoiceId] y devuelve el id de la voz.
  Future<String> saveDesignedVoice({
    required String name,
    required String description,
    required String generatedVoiceId,
  });

  /// Lee [text] con [voiceId] y devuelve el audio (MP3).
  Future<Uint8List> speak({required String voiceId, required String text});

  /// Borra [voiceId] de ElevenLabs. Una voz que ya no estaba no es un error.
  Future<void> deleteVoice(String voiceId);
}
