import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/vault/data/merge/incoming_vault.dart';
import 'package:sinapsis/features/vault/data/services/backup_layout.dart';

/// Las voces propias en la unión de bóvedas (F47, paso 4).
///
/// Las clonadas y las creadas no tienen filas: viven en la carpeta de Mías,
/// `originales/voces-mias/<id>/`, con su ficha (`voz.json`, que lleva la
/// mezcla de Kokoro o su id en ElevenLabs y, en las clonadas, el
/// consentimiento), su grabación y su muestra. La copia de la bóveda las lleva
/// —lleva todo `originales/`—, pero la unión solo copiaba los archivos que
/// nombra alguna fila. Este plan dice cuáles traer:
///
/// - **todo archivo de una voz que acá no está**, con la misma ruta: una voz
///   que llega entera, o lo que le falte a una que ya estaba. **Nunca se pisa
///   un archivo que ya está** —una ficha renombrada acá se queda como está— y
///   nunca se borra nada: unir no achica;
/// - **salvo las voces que se borraron acá** (`borradas.json`): una copia
///   hecha antes de borrarla no la trae de vuelta;
/// - y la lista de borradas de la copia se suma a la de acá, para que una
///   unión futura tampoco traiga las que se borraron allá. Sumarla no borra
///   ninguna voz de acá.
///
/// El `voices.bin` de las creadas no viaja: no está en la bóveda, sino junto
/// a los modelos, y se arma de nuevo solo, con todas las fichas, la próxima
/// vez que lee una creada —su firma cambió—. El lugar de cada creada en él se
/// asigna al armarlo, así que las de las dos bóvedas no chocan.
class MyVoicesMergePlan {
  const MyVoicesMergePlan._({
    required this.files,
    required this.bytes,
    required this.newVoices,
    required this.deleted,
    required this.deletedChanged,
  });

  /// La carpeta de Mías dentro de la copia, con `/` al final.
  static const prefix = '$kBackupOriginalsFolder/${MyVoicesStore.folderName}/';

  /// Los archivos a traer, como rutas de la copia.
  final List<String> files;

  /// Cuánto pesan, sin descomprimir.
  final int bytes;

  /// Las voces que acá no están y entran, por su id.
  final Set<String> newVoices;

  /// La lista de borradas de acá sumada a la de la copia.
  final Set<String> deleted;

  /// Si la lista de borradas cambia: hay que escribirla.
  final bool deletedChanged;

  bool get isEmpty => files.isEmpty && !deletedChanged;

  /// El plan para traer las voces de [incoming] a la carpeta de documentos
  /// [documents]. Lee la copia y el disco; no escribe nada.
  static Future<MyVoicesMergePlan> of(
    IncomingVault incoming,
    Directory documents,
  ) async {
    final local = Directory(
      p.join(documents.path, kBackupOriginalsFolder, MyVoicesStore.folderName),
    );
    final localList = File(p.join(local.path, MyVoicesStore.deletedFile));
    final deletedHere = localList.existsSync()
        ? decodeDeletedVoices(localList.readAsStringSync())
        : const <String>{};
    final theirList = await incoming.readOriginalText(
      '$prefix${MyVoicesStore.deletedFile}',
    );
    final deletedThere = theirList == null
        ? const <String>{}
        : decodeDeletedVoices(theirList);

    final files = <String>[];
    final newVoices = <String>{};
    var bytes = 0;
    for (final path in incoming.originalPaths) {
      if (!path.startsWith(prefix)) continue;
      final parts = path.substring(prefix.length).split('/');
      // Solo `<id>/<archivo>`: la lista de borradas va aparte, y lo que una
      // escritura cortada dejó a medias no se trae.
      if (parts.length != 2 || parts.last.endsWith('.escribiendo')) continue;
      final id = parts.first;
      if (deletedHere.contains(id)) continue;
      final target = File(p.join(local.path, id, parts.last));
      if (target.existsSync()) continue;
      files.add(path);
      bytes += incoming.sizeOfOriginal(path) ?? 0;
      if (parts.last == MyVoicesStore.manifestName) newVoices.add(id);
    }

    final deleted = {...deletedHere, ...deletedThere};
    return MyVoicesMergePlan._(
      files: files,
      bytes: bytes,
      newVoices: newVoices,
      deleted: deleted,
      deletedChanged: deleted.length != deletedHere.length,
    );
  }

  /// La lista de borradas de acá, en la carpeta de documentos [documents].
  static File deletedListIn(Directory documents) => File(
    p.join(
      documents.path,
      kBackupOriginalsFolder,
      MyVoicesStore.folderName,
      MyVoicesStore.deletedFile,
    ),
  );
}
