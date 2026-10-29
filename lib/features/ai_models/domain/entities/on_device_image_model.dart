import 'package:meta/meta.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';

/// Los modelos de imágenes que corren en el teléfono (F43, «Exigente — en el
/// teléfono»): abiertos, chicos, a 512 px, con stable-diffusion.cpp en el
/// procesador.
///
/// Verificados el 2026-10-28 en sus fichas de Hugging Face y en la guía de
/// modelos destilados de stable-diffusion.cpp
/// (`docs/distilled_sd.md`, commit `77b72a2`): qué archivo entiende, con
/// cuántos pasos y qué guía.
enum OnDeviceImageModel {
  /// SDXS-512 DreamShaper: el más rápido. Un paso y sin guía, como pide su
  /// guía en stable-diffusion.cpp («--cfg-scale 1 --steps 1 are mandatory»).
  sdxs(
    OnDeviceModelSpec(
      id: 'sdxs-512',
      displayName: 'SDXS-512',
      officialRepo: 'IDKiro/sdxs-512-dreamshaper',
      // El mismo modelo en un solo archivo, el que nombra la guía de
      // stable-diffusion.cpp; de quien sumó SDXS a stable-diffusion.cpp.
      downloadRepo: 'akleine/sdxs-512',
      commit: '17ef024d73ebee1db9b0643f9c90454dae6c5772',
      fileName: 'sdxs.safetensors',
      bytes: 882587118,
      sha256:
          '6cca5bfd11b588cdfb4602018c7e623d24c95fdfdc5ab2d4b9e6978b3186980f',
      license: OpenModelLicense.openRailPlusPlus,
      steps: 1,
      cfg: 1,
      minRamGb: 6,
      recommendedRamGb: 8,
      estimatedSecondsPerImage: 20,
    ),
  ),

  /// SD-Turbo: el de mejor calidad. Cuantizado a 8 bits (los pesos grandes)
  /// por quien mantiene stable-diffusion.cpp: 2 GB en vez de los 5,2 del
  /// original.
  sdTurbo(
    OnDeviceModelSpec(
      id: 'sd-turbo',
      displayName: 'SD-Turbo',
      officialRepo: 'stabilityai/sd-turbo',
      downloadRepo: 'Green-Sky/SD-Turbo-GGUF',
      commit: '19a31586d02d64a73b4419bc193b3ecfaf38e1f0',
      fileName: 'sd_turbo-f16-q8_0.gguf',
      bytes: 2023745376,
      sha256:
          'd50be7655f0a554cf8041c145d88b210bd5f3c545423119dee62ae08cae51580',
      license: OpenModelLicense.stabilityCommunity,
      steps: 1,
      cfg: 1,
      minRamGb: 8,
      recommendedRamGb: 12,
      estimatedSecondsPerImage: 40,
    ),
  );

  const OnDeviceImageModel(this.spec);

  final OnDeviceModelSpec spec;

  /// El de [id] («sdxs-512»), o `null`.
  static OnDeviceImageModel? byId(String? id) {
    for (final model in values) {
      if (model.spec.id == id) return model;
    }
    return null;
  }
}

/// Lo que la app sabe de un modelo del teléfono: de dónde se baja, qué tiene
/// que llegar, cómo se dibuja y qué pide.
@immutable
class OnDeviceModelSpec {
  const OnDeviceModelSpec({
    required this.id,
    required this.displayName,
    required this.officialRepo,
    required this.downloadRepo,
    required this.commit,
    required this.fileName,
    required this.bytes,
    required this.sha256,
    required this.license,
    required this.steps,
    required this.cfg,
    required this.minRamGb,
    required this.recommendedRamGb,
    required this.estimatedSecondsPerImage,
  });

  /// El código que se guarda y se manda en `ImageWireRequest.model`.
  final String id;
  final String displayName;

  /// La ficha oficial del modelo en Hugging Face: el enlace que se muestra.
  final String officialRepo;

  /// El repositorio del archivo que entiende stable-diffusion.cpp.
  final String downloadRepo;

  /// El commit de [downloadRepo]: lo que se baja no puede cambiar.
  final String commit;
  final String fileName;

  /// Lo que pesa [fileName] según Hugging Face (`?blobs=true`).
  final int bytes;

  /// Su huella SHA-256 según Hugging Face, en hexadecimal minúscula.
  final String sha256;
  final OpenModelLicense license;

  /// Cuántos pasos y qué guía: los de su ficha para stable-diffusion.cpp.
  final int steps;
  final double cfg;

  /// La memoria del teléfono, en GB como la dice su ficha comercial («12
  /// GB»): por debajo de [minRamGb] no alcanza; hasta [recommendedRamGb],
  /// justo.
  final int minRamGb;
  final int recommendedRamGb;

  /// Lo que se estima hasta medirlo en el teléfono, a 512 px. En un Galaxy
  /// S24, SDXS tarda unos 6 s y SD-Turbo unos 12; en un Galaxy A53 (6 GB),
  /// SDXS 26 a 29 s y SD-Turbo se cierra por falta de memoria. Un teléfono
  /// de gama media alta, como el Dimensity 7200, cae entre los dos: se
  /// estima del lado prudente.
  final int estimatedSecondsPerImage;

  String get officialUrl => 'https://huggingface.co/$officialRepo';

  /// La dirección del archivo, fijada al commit.
  String get downloadUrl =>
      'https://huggingface.co/$downloadRepo/resolve/$commit/$fileName';
}
