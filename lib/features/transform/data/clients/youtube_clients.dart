import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_api;

/// La vía por la que se le piden a YouTube las pistas de un video: se hace
/// pasar por la app de YouTube para los anteojos de Apple (visionOS).
///
/// Desde 2025 YouTube exige una "credencial" (PO token) para bajar las
/// pistas por casi todas las vías que no son su propia web, y la que usaba
/// el paquete —la de Android— entrega solo el comienzo de cada pista: el
/// resto responde 403 (medido el 2026-10-02: cuatro de seis videos). La de
/// visionOS no la pide: con ella bajaron enteros los seis, en la mejor
/// calidad. Es la vía por defecto de yt-dlp y de NewPipe desde julio y
/// agosto de 2026 (yt-dlp PR #17184 y #17261; NewPipeExtractor PR #1529).
///
/// Definida acá y no en el paquete —que no la trae y no se actualiza desde
/// mayo de 2026—: si YouTube la cambia, se cambia en un solo lugar. Los
/// videos "hechos para chicos" no están por esta vía: para esos se usan las
/// del paquete.
const youTubeVisionOsClient = yt_api.YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': _visionOsVersion,
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent': _visionOsUserAgent,
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  headers: {
    // El número de la vía, no su nombre: es lo que espera YouTube.
    'X-Youtube-Client-Name': '101',
    'X-Youtube-Client-Version': _visionOsVersion,
    'User-Agent': _visionOsUserAgent,
  },
);

const _visionOsVersion = '1.02';
const _visionOsUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';
