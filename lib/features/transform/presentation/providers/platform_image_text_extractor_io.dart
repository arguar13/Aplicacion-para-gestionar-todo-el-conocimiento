import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/data/services/ml_kit_image_text_extractor.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// El que reconoce texto en imágenes fuera de la web: Google ML Kit.
ImageTextExtractor createImageTextExtractor({required FileStore files}) {
  return const MlKitImageTextExtractor();
}
