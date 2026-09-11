import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/transform/data/services/tesseract_image_text_extractor.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// El que reconoce texto en imágenes en la web: Tesseract en WebAssembly,
/// ML Kit no tiene ninguna versión ahí.
ImageTextExtractor createImageTextExtractor({required FileStore files}) {
  return TesseractImageTextExtractor(files: files);
}
