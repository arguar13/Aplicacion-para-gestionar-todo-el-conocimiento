import 'package:fpdart/fpdart.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/explorer/domain/entities/folder.dart';

/// El Explorador: la organización de lo ya procesado en carpetas, al estilo
/// de un explorador de archivos.
///
/// Solo se ocupa de la estructura —las carpetas y en cuáles está cada
/// elemento—, nunca del contenido de los elementos en sí: eso sigue siendo
/// responsabilidad de `LibraryRepository`. La pantalla del Explorador
/// combina las dos cosas: qué elementos están en la carpeta actual, según
/// este repositorio, con los datos completos de esos elementos, según la
/// biblioteca.
///
/// [watchAllFolders] trae el árbol entero de una sola vez, plano, en vez de
/// un método por nivel: una bóveda personal no va a tener miles de
/// carpetas, así que arma el árbol del lado de Dart —agrupando por
/// `parentId`— es más simple que streams por nivel, y le regala gratis la
/// migas de pan y el selector de destino al mover o copiar.
abstract interface class ExplorerRepository {
  /// Todas las carpetas que existen, sin importar su nivel.
  Stream<List<Folder>> watchAllFolders();

  /// Crea una carpeta nueva dentro de [parentId] (`null` para el nivel
  /// raíz). Devuelve un fallo si el nombre queda vacío o si ya existe otra
  /// carpeta con ese nombre en el mismo nivel (sin distinguir mayúsculas) —
  /// dos carpetas "Filosofía" una al lado de la otra confundirían más de lo
  /// que ordenan.
  Future<Either<Failure, Folder>> createFolder({
    required String name,
    required String? parentId,
  });

  /// Le cambia el nombre a una carpeta, sin moverla de nivel.
  Future<Either<Failure, Folder>> renameFolder({
    required String id,
    required String name,
  });

  /// Borra una carpeta y, en cascada, sus subcarpetas. Los elementos que
  /// vivían en cualquiera de ellas no se borran — ver el comentario de
  /// `Folders` sobre por qué.
  Future<Either<Failure, Unit>> deleteFolder(String id);

  /// Los `id` de los elementos guardados directamente en [folderId] —`null`
  /// para los que todavía no se llevaron a ninguna carpeta—, actualizándose
  /// solos.
  Stream<Set<String>> watchItemIdsInFolder(String? folderId);

  /// En qué carpetas está [itemId] ahora mismo, actualizándose solo. Para el
  /// selector de "mover/copiar a carpeta", que necesita saber cuáles marcar
  /// como ya elegidas.
  Stream<Set<String>> watchFolderIdsForItem(String itemId);

  /// Agrega [itemId] a [folderId] sin sacarlo de ninguna otra carpeta en la
  /// que ya esté — "copiar". No falla si ya estaba: el resultado es el
  /// mismo de todos modos.
  Future<Either<Failure, Unit>> addItemToFolder({
    required String itemId,
    required String folderId,
  });

  /// Saca [itemId] de [folderId], sin tocar el elemento en sí ni sus otras
  /// carpetas. "Mover" es sacar de una y agregar a otra.
  Future<Either<Failure, Unit>> removeItemFromFolder({
    required String itemId,
    required String folderId,
  });
}
