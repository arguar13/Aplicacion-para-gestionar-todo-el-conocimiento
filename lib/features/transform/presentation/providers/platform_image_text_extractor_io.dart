import 'dart:io';

import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/data/services/ml_kit_image_text_extractor.dart';
import 'package:sinapsis/features/transform/data/services/tesseract_cli_image_text_extractor.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// El que reconoce texto en imágenes fuera de la web: Google ML Kit en
/// Android e iOS, el Tesseract del sistema en escritorio —donde ML Kit no
/// tiene ninguna versión nativa—.
ImageTextExtractor createImageTextExtractor({required FileStore files}) {
  if (Platform.isAndroid || Platform.isIOS) {
    return const MlKitImageTextExtractor();
  }
  return const TesseractCliImageTextExtractor();
}
