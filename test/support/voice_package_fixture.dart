import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';

/// Un paquete de voz de mentira, armado acá (F47, paso 3): un `.tar.bz2` de
/// verdad, chico, con los archivos que trae uno de sherpa-onnx —su carpeta,
/// el modelo, `tokens.txt` y `espeak-ng-data/`—, pero sin ningún modelo de
/// verdad adentro. Nada se baja ni suena.
class VoicePackageFixture {
  VoicePackageFixture._(this.package, this.bytes);

  /// Un paquete de Piper con su carpeta [folder] y [files] adentro —por
  /// defecto, los de una voz entera—. [id] es el del paquete.
  factory VoicePackageFixture.piper({
    String id = 'vits-piper-xx_XX-prueba-medium',
    String folder = 'vits-piper-xx_XX-prueba-medium',
    Map<String, String>? files,
    OfflineVoiceFamily family = OfflineVoiceFamily.piper,
  }) {
    final archive = Archive();
    for (final MapEntry(:key, :value)
        in (files ??
                {
                  'xx_XX-prueba-medium.onnx': 'modelo',
                  'tokens.txt': 'a 1',
                  'espeak-ng-data/phontab': 'fonemas',
                  if (family == OfflineVoiceFamily.kokoro)
                    'voices.bin': 'estilos',
                })
            .entries) {
      archive.addFile(ArchiveFile.string('$folder/$key', value));
    }
    final bytes = BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
    return VoicePackageFixture._(
      OfflineVoicePackage(
        id: id,
        family: family,
        bytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      ),
      bytes,
    );
  }

  /// El paquete, con el tamaño y la huella de [bytes].
  final OfflineVoicePackage package;

  /// El `.tar.bz2`.
  final List<int> bytes;
}
