import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';

/// Los audios descargados de los documentos en la bóveda (F47, paso 5): cada
/// uno en su carpeta, `originales/audio-documentos/<clave>/`
/// ([kDocumentAudioFolder], [documentAudioKeyOf]), con
///
/// - **el archivo** (`audio-<huella>.m4a`), generado en el teléfono y nunca en
///   la nube (decisión F);
/// - **su ficha**, `audio.json` ([DocumentAudio]): de qué documento es, la
///   huella de lo que se dijo, dónde empieza cada pedazo y con qué voz.
///
/// **Sin tabla nueva**, como las voces propias (paso 4): un audio es de un
/// documento que el lector conoce por su id —un original, un procesado, lo
/// creado—, no de una fila, y cada uno es dueño de su carpeta. Borrarlo es
/// borrar su carpeta y nada más: el documento —y menos la fuente de la
/// Biblioteca— no se toca.
///
/// Al guardar uno nuevo, el archivo nuevo queda al lado del de antes y la
/// ficha pasa a nombrarlo; recién entonces se barre lo demás de la carpeta.
/// Una ficha que no se entiende, o que nombra un archivo que ya no está, es
/// como no tener audio: nunca suena algo que no se sabe qué es.
class DocumentAudioStore {
  DocumentAudioStore(this._files);

  final FileStore _files;

  /// El nombre de la ficha de cada audio.
  static const manifestName = 'audio.json';

  /// El audio de [documentId], o `null` si no tiene —o su ficha no se
  /// entiende, o el archivo ya no está—.
  Future<DocumentAudio?> read(String documentId) async {
    final listed = await _files.filesOf(
      kDocumentAudioFolder,
      folder: documentAudioKeyOf(documentId),
    );
    final manifest = listed
        .where((path) => p.posix.basename(path) == manifestName)
        .firstOrNull;
    if (manifest == null) return null;
    final bytes = await _files.read(manifest);
    if (bytes == null) return null;
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
    final audio = DocumentAudio.fromJson(json);
    // La clave es un resumen del id: la ficha dice de quién es de verdad.
    if (audio == null || audio.documentId != documentId) return null;
    if (!listed.contains(audio.reference)) return null;
    return audio;
  }

  /// Guarda el audio de [documentId] que la pieza común dejó en [result]
  /// —lo que va llegando por [bytes]—, generado con [plan], y devuelve su
  /// ficha. El de antes, si había, se borra recién después.
  Future<DocumentAudio> save({
    required String documentId,
    required String title,
    required DocumentAudioPlan plan,
    required SpeechAudioResult result,
    required Stream<List<int>> bytes,
    required DateTime now,
  }) async {
    final key = documentAudioKeyOf(documentId);
    final reference = await _files.saveStream(
      bytes: bytes,
      suggestedName:
          'audio-${plan.fingerprint.substring(0, 8)}.${result.extension}',
      id: kDocumentAudioFolder,
      folder: key,
      unique: true,
    );
    final audio = DocumentAudio(
      documentId: documentId,
      title: title,
      fingerprint: plan.fingerprint,
      reference: reference,
      mimeType: result.mimeType,
      duration: result.duration,
      starts: plan.segmentStarts(result.starts, result.duration),
      voices: plan.voices,
      createdAt: now,
    );
    final String manifest;
    try {
      manifest = await _files.saveStream(
        bytes: Stream.value(utf8.encode(jsonEncode(audio.toJson()))),
        suggestedName: manifestName,
        id: kDocumentAudioFolder,
        folder: key,
      );
    } on Object {
      // Sin ficha, el archivo nuevo no es de nadie: no queda.
      await _files.delete(reference);
      rethrow;
    }
    final listed = await _files.filesOf(kDocumentAudioFolder, folder: key);
    for (final path in listed) {
      if (path != reference && path != manifest) await _files.delete(path);
    }
    return audio;
  }

  /// Borra el audio de [documentId]: su archivo y su ficha. No falla si no
  /// tenía.
  Future<void> delete(String documentId) async {
    final listed = await _files.filesOf(
      kDocumentAudioFolder,
      folder: documentAudioKeyOf(documentId),
    );
    for (final path in listed) {
      await _files.delete(path);
    }
  }

  /// Cuánto pesa el archivo de [audio], en bytes, o `null` si ya no está.
  Future<int?> sizeOf(DocumentAudio audio) => _files.sizeOf(audio.reference);

  /// La ruta en el teléfono del archivo de [audio], o `null` si no tiene una
  /// —en la web—.
  Future<String?> localPathOf(DocumentAudio audio) =>
      _files.localPathOf(audio.reference);
}
