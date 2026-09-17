import 'package:freezed_annotation/freezed_annotation.dart';

part 'folder.freezed.dart';

/// Una carpeta del Explorador: como un espacio, pero puede tener otras
/// carpetas adentro.
///
/// [parentId] es `null` para una carpeta de nivel raíz, o el `id` de la
/// carpeta que la contiene. Con eso alcanza para armar el árbol entero del
/// lado de Dart a partir de la lista plana que devuelve
/// `ExplorerRepository.watchAllFolders` — no hace falta que la base ya
/// entregue el árbol armado.
@freezed
sealed class Folder with _$Folder {
  const factory Folder({
    required String id,
    required String name,
    required String? parentId,
    required DateTime createdAt,
  }) = _Folder;
}
