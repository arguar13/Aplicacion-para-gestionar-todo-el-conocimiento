import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';

/// Las voces de la pestaña Mías en la bóveda (F47, paso 4): cada una en su
/// carpeta, `originales/voces-mias/<id>/`, con
///
/// - su ficha, `voz.json` —el nombre, los rasgos, la mezcla o su id en
///   ElevenLabs y, en las clonadas, **el consentimiento**, junto a la voz—;
/// - en las clonadas, **la grabación** o el audio subido (`muestra.wav`…);
/// - en las de la nube, la muestra ya generada, para oírla sin gastar.
///
/// Dentro de `originales/`, la carpeta de los archivos de la bóveda: la copia
/// de seguridad la lleva entera. Sin tabla nueva: son pocas, se leen todas
/// juntas y cada una es dueña de su carpeta; borrar una voz es borrar su
/// carpeta, y nada más.
///
/// La ficha se escribe en un archivo aparte que recién al final toma su
/// nombre: un corte a mitad no deja una ficha rota. Una ficha que no se
/// entiende no se muestra, pero su carpeta queda —nunca se borra lo que no
/// se pidió borrar—.
class MyVoicesStore {
  MyVoicesStore({required Future<Directory> Function() rootDirectory})
    : _rootDirectory = rootDirectory;

  static const folderName = 'voces-mias';

  /// El nombre de la ficha de cada voz.
  static const manifestName = 'voz.json';

  final Future<Directory> Function() _rootDirectory;
  final _changes = StreamController<void>.broadcast();

  /// Avisa cada vez que una voz se guarda o se borra.
  Stream<void> changes() => _changes.stream;

  Future<Directory> _folder() async => Directory(
    p.join((await _rootDirectory()).path, 'originales', folderName),
  );

  /// La carpeta de la voz [id]; falla si [id] no es un solo tramo.
  Future<Directory> folderOf(String id) async {
    if (id.isEmpty ||
        id == '.' ||
        id == '..' ||
        id.contains('/') ||
        id.contains(r'\')) {
      throw ArgumentError.value(id, 'id', 'no es el id de una voz');
    }
    return Directory(p.join((await _folder()).path, id));
  }

  /// Todas las voces, de la más vieja a la más nueva.
  Future<List<MyVoice>> list() async {
    final folder = await _folder();
    if (!folder.existsSync()) return const [];
    final voices = <MyVoice>[];
    for (final entry in folder.listSync()) {
      if (entry is! Directory) continue;
      final manifest = File(p.join(entry.path, manifestName));
      if (!manifest.existsSync()) continue;
      try {
        final voice = MyVoice.fromJson(jsonDecode(manifest.readAsStringSync()));
        if (voice != null && voice.id == p.basename(entry.path)) {
          voices.add(voice);
        }
      } on FormatException {
        // Una ficha ilegible no se muestra; su carpeta queda como está.
      }
    }
    voices.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(voices);
  }

  /// Guarda la ficha de [voice] —nueva o cambiada—.
  Future<void> save(MyVoice voice) async {
    final folder = (await folderOf(voice.id))..createSync(recursive: true);
    File(p.join(folder.path, '$manifestName.escribiendo'))
      ..writeAsStringSync(jsonEncode(voice.toJson()), flush: true)
      ..renameSync(p.join(folder.path, manifestName));
    _changes.add(null);
  }

  /// Copia [source] a la carpeta de la voz [id] como [name] y devuelve el
  /// archivo: la grabación, o la muestra ya generada.
  Future<File> keep(String id, File source, String name) async {
    final folder = (await folderOf(id))..createSync(recursive: true);
    return source.copySync(p.join(folder.path, _safeName(name)));
  }

  /// Escribe [bytes] en la carpeta de la voz [id] como [name].
  Future<File> write(String id, List<int> bytes, String name) async {
    final folder = (await folderOf(id))..createSync(recursive: true);
    return File(p.join(folder.path, _safeName(name)))
      ..writeAsBytesSync(bytes, flush: true);
  }

  /// El archivo [name] de la voz [id], o `null` si no está.
  Future<File?> fileOf(String id, String? name) async {
    if (name == null) return null;
    final file = File(p.join((await folderOf(id)).path, _safeName(name)));
    return file.existsSync() ? file : null;
  }

  /// Borra la voz [id]: su ficha, su grabación y su muestra, y la anota en
  /// [deletedFile]. Nada más.
  ///
  /// La anotación es lo que impide que unir una copia de la bóveda hecha
  /// antes de borrarla la traiga de vuelta (ver `MyVoicesMergePlan`): una voz
  /// borrada no tiene una fila que la recuerde, como un elemento en la
  /// papelera.
  Future<void> delete(String id) async {
    final folder = await folderOf(id);
    final deleted = await deletedIds();
    if (!deleted.contains(id)) {
      final list = File(p.join((await _folder()).path, deletedFile));
      list.parent.createSync(recursive: true);
      File('${list.path}.escribiendo')
        ..writeAsStringSync(encodeDeletedVoices({...deleted, id}), flush: true)
        ..renameSync(list.path);
    }
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    _changes.add(null);
  }

  /// La lista de las voces borradas, en la carpeta de Mías.
  static const deletedFile = 'borradas.json';

  /// Los ids de las voces que se borraron en esta bóveda.
  Future<Set<String>> deletedIds() async {
    final list = File(p.join((await _folder()).path, deletedFile));
    return list.existsSync()
        ? decodeDeletedVoices(list.readAsStringSync())
        : const {};
  }

  static String _safeName(String name) {
    final base = p.basename(name);
    if (base.isEmpty || base == '.' || base == '..') {
      throw ArgumentError.value(name, 'name', 'no es un nombre de archivo');
    }
    return base;
  }

  Future<void> dispose() => _changes.close();
}

/// [ids] como se guardan en `borradas.json`: una lista ordenada.
String encodeDeletedVoices(Set<String> ids) =>
    jsonEncode({'borradas': ids.toList()..sort()});

/// Los ids de `borradas.json`; vacío si no se entiende —una lista rota no
/// impide nada, y no borra nada—.
Set<String> decodeDeletedVoices(String json) {
  try {
    final decoded = jsonDecode(json);
    final ids = decoded is Map ? decoded['borradas'] : null;
    return {
      if (ids is List)
        for (final id in ids)
          if (id is String && id.isNotEmpty) id,
    };
  } on FormatException {
    return const {};
  }
}
