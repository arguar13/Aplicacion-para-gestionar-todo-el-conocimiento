import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sinapsis/features/transform/domain/services/image_text_extractor.dart';

/// `ImageTextExtractor` sobre Google ML Kit, solo Android e iOS —no tiene
/// versión web ni de escritorio—.
///
/// Reconoce script latino únicamente: cubre español e inglés, los dos
/// idiomas de la interfaz, sin sumar los paquetes de otros alfabetos que
/// nadie en esta app va a necesitar.
///
/// Un `TextRecognizer` por llamada, y no uno guardado y reutilizado: esto
/// corre de a una imagen por vez, en el fondo, nunca en un bucle ajustado
/// donde importe el costo de crearlo — y así no hay ningún recurso nativo
/// que se pueda quedar abierto si algo falla a mitad de camino.
class MlKitImageTextExtractor implements ImageTextExtractor {
  const MlKitImageTextExtractor();

  @override
  Future<String> extractText(String absolutePath) async {
    final recognizer = TextRecognizer();
    try {
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(absolutePath),
      );
      return recognized.text;
    } finally {
      await recognizer.close();
    }
  }
}
