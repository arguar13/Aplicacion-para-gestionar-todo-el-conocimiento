import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';

/// La clave de ElevenLabs, en el almacén seguro del sistema (F47, paso 4),
/// como las de la IA en la nube (F32, decisión C): fuera de la base y de la
/// copia de la bóveda.
class ElevenLabsKeyStore {
  ElevenLabsKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'voice_cloud_elevenlabs_key_v1';

  final FlutterSecureStorage _storage;

  Future<String?> read() async {
    final key = await _storage.read(key: _key);
    return key == null || key.trim().isEmpty ? null : key.trim();
  }

  Future<void> write(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key', 'La clave está vacía');
    }
    return _storage.write(key: _key, value: trimmed);
  }

  Future<void> delete() => _storage.delete(key: _key);
}

/// [VoiceCloud] sobre la API de ElevenLabs, por HTTP directo (decisión 3: sin
/// el SDK de cada empresa). Lo que se manda y lo que cuesta, con sus fuentes,
/// está en [ElevenLabsFacts].
///
/// Cada pedido lleva la clave en `xi-api-key` y nada más de la persona: ni su
/// nombre ni su correo.
class ElevenLabsVoiceCloud implements VoiceCloud {
  ElevenLabsVoiceCloud({
    required Dio dio,
    required Future<String?> Function() key,
  }) : _dio = dio,
       _key = key;

  final Dio _dio;
  final Future<String?> Function() _key;

  Future<Options> _options({
    ResponseType type = ResponseType.json,
    String? contentType,
  }) async {
    final key = await _key();
    if (key == null) throw const VoiceCloudException(VoiceCloudFailure.noKey);
    return Options(
      headers: {ElevenLabsFacts.keyHeader: key},
      contentType: contentType,
      responseType: type,
      // Los errores los lee [_failureOf], con su cuerpo.
      validateStatus: (_) => true,
    );
  }

  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    final Response<T> response;
    try {
      response = await request();
    } on DioException catch (error) {
      throw VoiceCloudException(VoiceCloudFailure.network, error.type.name);
    } on SocketException catch (error) {
      throw VoiceCloudException(VoiceCloudFailure.network, error.message);
    }
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return response;
    throw _failureOf(status, response.data);
  }

  /// La falla de un estado que no es 2xx, con el código que dice ElevenLabs
  /// (`{"detail": {"code": …}}`) para distinguir lo que el estado no dice.
  static VoiceCloudException _failureOf(int status, Object? body) {
    final detail = _detailOf(body);
    final code = detail.$1;
    final failure = switch (status) {
      401 => VoiceCloudFailure.invalidKey,
      402 => VoiceCloudFailure.noCredits,
      403 => VoiceCloudFailure.planRequired,
      404 => VoiceCloudFailure.voiceNotFound,
      409 || 429 => VoiceCloudFailure.busy,
      400 || 422 => VoiceCloudFailure.rejected,
      >= 500 => VoiceCloudFailure.unavailable,
      _ => VoiceCloudFailure.unknown,
    };
    // Un 401 por la cuota (ElevenLabs lo contesta así desde 2025) no es la
    // clave.
    final adjusted =
        failure == VoiceCloudFailure.invalidKey &&
            (code == 'quota_exceeded' || code == 'insufficient_credits')
        ? VoiceCloudFailure.noCredits
        : failure;
    return VoiceCloudException(
      adjusted,
      '$status ${code ?? ''} ${detail.$2 ?? ''}'.trim(),
    );
  }

  static (String?, String?) _detailOf(Object? body) {
    var decoded = body;
    if (body is List<int>) {
      try {
        decoded = jsonDecode(utf8.decode(body));
      } on FormatException {
        return (null, null);
      }
    } else if (body is String) {
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        return (null, body);
      }
    }
    if (decoded is! Map) return (null, null);
    final detail = decoded['detail'];
    if (detail is Map) {
      final code = detail['code'] ?? detail['status'];
      return (code is String ? code : null, detail['message'] as String?);
    }
    return (null, detail is String ? detail : null);
  }

  Uri _url(String path, [Map<String, String>? query]) => Uri.parse(
    '${ElevenLabsFacts.baseUrl}$path',
  ).replace(queryParameters: query);

  @override
  Future<VoiceCloudAccount> account() async {
    final response = await _send(
      () async => _dio.getUri<Object?>(
        _url('/v1/user/subscription'),
        options: await _options(),
      ),
    );
    final json = response.data;
    if (json is! Map) {
      throw const VoiceCloudException(VoiceCloudFailure.unknown, 'sin plan');
    }
    final reset = json['next_character_count_reset_unix'];
    return VoiceCloudAccount(
      tier: '${json['tier'] ?? ''}',
      creditsUsed: (json['character_count'] as num?)?.toInt() ?? 0,
      creditLimit: (json['character_limit'] as num?)?.toInt() ?? 0,
      canClone: json['can_use_instant_voice_cloning'] == true,
      resetsAt: reset is num
          ? DateTime.fromMillisecondsSinceEpoch(
              reset.toInt() * 1000,
              isUtc: true,
            )
          : null,
      voiceSlotsUsed: (json['voice_slots_used'] as num?)?.toInt(),
      voiceLimit: (json['voice_limit'] as num?)?.toInt(),
    );
  }

  @override
  Future<String> cloneVoice({
    required String name,
    required String samplePath,
    required String description,
  }) async {
    final response = await _send(
      () async => _dio.postUri<Object?>(
        _url('/v1/voices/add'),
        data: FormData.fromMap({
          'name': name,
          'description': description,
          // El ruido se mide y se avisa antes, en el teléfono: limpiarlo
          // allá cambiaría la voz sin que se oiga antes.
          'remove_background_noise': 'false',
          'files': [await MultipartFile.fromFile(samplePath)],
        }),
        options: await _options(),
      ),
    );
    return _voiceIdOf(response.data, 'voice_id');
  }

  @override
  Future<List<DesignedVoicePreview>> designPreviews({
    required String description,
    required String text,
  }) async {
    final response = await _send(
      () async => _dio.postUri<Object?>(
        _url('/v1/text-to-voice/design', {'output_format': 'mp3_44100_128'}),
        data: {'voice_description': description, 'text': text},
        options: await _options(contentType: Headers.jsonContentType),
      ),
    );
    final json = response.data;
    final previews = json is Map ? json['previews'] : null;
    if (previews is! List || previews.isEmpty) {
      throw const VoiceCloudException(
        VoiceCloudFailure.unknown,
        'sin propuestas',
      );
    }
    return [
      for (final preview in previews)
        if (preview is Map &&
            preview['generated_voice_id'] is String &&
            preview['audio_base_64'] is String)
          DesignedVoicePreview(
            generatedVoiceId: preview['generated_voice_id'] as String,
            audio: base64Decode(preview['audio_base_64'] as String),
            mediaType: '${preview['media_type'] ?? 'audio/mpeg'}',
            duration: preview['duration_secs'] is num
                ? Duration(
                    milliseconds: ((preview['duration_secs'] as num) * 1000)
                        .round(),
                  )
                : null,
          ),
    ];
  }

  @override
  Future<String> saveDesignedVoice({
    required String name,
    required String description,
    required String generatedVoiceId,
  }) async {
    final response = await _send(
      () async => _dio.postUri<Object?>(
        _url('/v1/text-to-voice'),
        data: {
          'voice_name': name,
          'voice_description': description,
          'generated_voice_id': generatedVoiceId,
        },
        options: await _options(contentType: Headers.jsonContentType),
      ),
    );
    return _voiceIdOf(response.data, 'voice_id');
  }

  @override
  Future<Uint8List> speak({
    required String voiceId,
    required String text,
  }) async {
    if (text.length > ElevenLabsFacts.maxCharactersPerRequest) {
      throw const VoiceCloudException(
        VoiceCloudFailure.rejected,
        'texto más largo que un pedido',
      );
    }
    final response = await _send(
      () async => _dio.postUri<List<int>>(
        _url('/v1/text-to-speech/${Uri.encodeComponent(voiceId)}', {
          'output_format': 'mp3_44100_128',
        }),
        data: {'text': text, 'model_id': ElevenLabsFacts.readingModel},
        options: await _options(
          type: ResponseType.bytes,
          contentType: Headers.jsonContentType,
        ),
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const VoiceCloudException(VoiceCloudFailure.unknown, 'sin audio');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteVoice(String voiceId) async {
    try {
      await _send(
        () async => _dio.deleteUri<Object?>(
          _url('/v1/voices/${Uri.encodeComponent(voiceId)}'),
          options: await _options(),
        ),
      );
    } on VoiceCloudException catch (error) {
      // Ya no estaba: lo pedido ya está hecho.
      if (error.failure != VoiceCloudFailure.voiceNotFound) rethrow;
    }
  }

  static String _voiceIdOf(Object? json, String field) {
    final id = json is Map ? json[field] : null;
    if (id is! String || id.isEmpty) {
      throw const VoiceCloudException(
        VoiceCloudFailure.unknown,
        'sin voice_id',
      );
    }
    return id;
  }
}
