import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/storage/file_store.dart' show sanitizeFileName;
import 'package:sinapsis/features/capture/domain/entities/captured_file.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/transform/data/services/audio_wav_converter.dart';

/// Lo que se hace con la muestra de una voz que se clona, antes de clonarla
/// (F47, paso 4): medirla, y traer al teléfono un audio que se sube.
class VoiceSampleTools {
  const VoiceSampleTools({
    required AudioWavConverter converter,
    required Future<Directory> Function() workDirectory,
  }) : _converter = converter,
       _workDirectory = workDirectory;

  final AudioWavConverter _converter;
  final Future<Directory> Function() _workDirectory;

  /// Mide [wav] —un WAV PCM de 16 bits— en un isolate: un minuto y medio a
  /// 44,1 kHz son cuatro millones de muestras.
  Future<RecordingReport> analyze(File wav) {
    final path = wav.path;
    return Isolate.run(() {
      final parsed = PcmWav.parse(File(path).readAsBytesSync());
      return analyzeRecording(parsed.samples, parsed.sampleRate);
    });
  }

  /// Un archivo nuevo, vacío, para grabar.
  Future<File> newRecording() async {
    final folder = await _clean('grabar');
    return File(p.join(folder.path, 'grabacion.wav'));
  }

  /// Trae [file] —el audio elegido— al teléfono y lo mide: se copia tal cual
  /// (es lo que se sube a ElevenLabs, con su calidad) y se convierte a un WAV
  /// aparte solo para medirlo. Falla con [AudioConversionException] si no es
  /// un audio que el teléfono sepa leer.
  Future<(File, RecordingReport)> importUpload(CapturedFile file) async {
    final folder = await _clean('subir');
    final name = sanitizeFileName(file.name);
    final original = File(p.join(folder.path, name.isEmpty ? 'audio' : name));
    final sink = original.openWrite();
    try {
      await sink.addStream(file.openRead());
    } finally {
      await sink.close();
    }
    final measured = File(p.join(folder.path, 'para-medir.wav'));
    try {
      await _converter.convert(original.path, measured.path);
      return (original, await analyze(measured));
    } finally {
      if (measured.existsSync()) measured.deleteSync();
    }
  }

  /// La carpeta de trabajo [name], vacía: lo de una vez anterior ya no sirve.
  Future<Directory> _clean(String name) async {
    final folder = Directory(p.join((await _workDirectory()).path, name));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    return folder;
  }
}
