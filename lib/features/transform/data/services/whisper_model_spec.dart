/// Un archivo del modelo de transcripción, con su tamaño y su huella
/// SHA-256 exactos: lo que se baja tiene que ser byte por byte lo que se
/// verificó.
class WhisperModelFile {
  const WhisperModelFile(
    this.name, {
    required this.bytes,
    required this.sha256,
  });

  final String name;
  final int bytes;

  /// En hexadecimal, minúsculas.
  final String sha256;
}

/// De dónde se baja el modelo de transcripción y qué tiene que llegar.
class WhisperModelSpec {
  const WhisperModelSpec({
    required this.baseUrl,
    required this.folder,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.replaces = const [],
  });

  /// Whisper "small" multilingüe, int8, exportado **con la atención del
  /// decodificador** (F23): los mismos pesos y el mismo texto que el modelo
  /// anterior —comprobado tramo por tramo—, más lo que sherpa-onnx necesita
  /// para calcular cuándo se dice cada palabra (error mediano de 60 ms
  /// contra los tiempos reales; ver `docs/planes/F23-resaltado-
  /// sincronizado.md`). El modelo de quien mantiene sherpa-onnx
  /// (`csukuangfj/sherpa-onnx-whisper-small`) no trae esa salida.
  ///
  /// Es la publicación de un tercero, así que va **fijada a una versión**
  /// —el commit, no `main`: nadie puede cambiar lo que se baja— y cada
  /// archivo se comprueba por su huella antes de usarlo.
  static const smallWithAttention = WhisperModelSpec(
    baseUrl:
        'https://huggingface.co/clairemcw/sherpa-onnx-whisper-small-attention/'
        'resolve/9a896a02c311676d366ebfda3797753df4153fe2',
    folder: 'whisper-small-atencion',
    encoder: WhisperModelFile(
      'small-encoder.int8.onnx',
      bytes: 112445386,
      sha256:
          '570e2b92cce6a8be62dc37934057b82dd601298ecb3a2a25161542e2b59862aa',
    ),
    decoder: WhisperModelFile(
      'small-decoder.int8.onnx',
      bytes: 262482583,
      sha256:
          '63233cc33d6c11ae514467a69132de87cc61e6b28d3dab40cdf8b0e3060a3439',
    ),
    tokens: WhisperModelFile(
      'small-tokens.txt',
      bytes: 816730,
      sha256:
          'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
    ),
    // El modelo de antes de F23: se borra recién cuando este quedó entero
    // y verificado, así nunca hay dos ocupando lugar ni ninguno.
    replaces: ['whisper-small'],
  );

  /// Hasta el commit, sin barra final.
  final String baseUrl;

  /// Dentro de `modelos/`.
  final String folder;
  final WhisperModelFile encoder;
  final WhisperModelFile decoder;
  final WhisperModelFile tokens;

  /// Carpetas de modelos anteriores, dentro de `modelos/`, que este
  /// reemplaza.
  final List<String> replaces;

  List<WhisperModelFile> get files => [encoder, decoder, tokens];

  int get totalBytes => files.fold(0, (sum, f) => sum + f.bytes);

  String urlOf(WhisperModelFile file) => '$baseUrl/${file.name}';
}

/// Un archivo del modelo llegó distinto de lo verificado: cortado, o
/// cambiado en el servidor. No se usa.
class WhisperModelIntegrityException implements Exception {
  const WhisperModelIntegrityException(this.fileName);

  final String fileName;

  @override
  String toString() =>
      'El archivo $fileName del modelo no es el esperado: se descartó.';
}
