import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/features/index/data/repositories/index_repository_impl.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/repositories/index_repository.dart';

/// Lo que la pantalla del Índice (F46) lee y escribe.
final indexRepositoryProvider = Provider<IndexRepository>(
  (ref) => IndexRepositoryImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

// Lo que lee la pantalla, de a lo que se ve (F46, paso 3). Todos se sueltan
// solos cuando nadie los mira: un tema que se plegó, un documento que salió
// de la pantalla o una búsqueda vieja dejan de leer la base.
//
// Y ninguno avisa si lo que trae es lo mismo que ya tenía: la base vuelve a
// leer cada consulta con cada escritura en sus tablas —el relleno escribe un
// documento por vez—, y sin esto cada documento indexado volvería a dibujar
// cada tema y cada documento desplegado, aunque no les haya cambiado nada.

/// [stream] sin las vueltas que traen lo mismo que la anterior.
Stream<List<T>> _changesOf<T>(Stream<List<T>> stream) =>
    stream.distinct(listEquals);

/// Los temas con cuántos documentos tiene cada uno, y «Sin tema» al final.
final indexTopicsProvider = StreamProvider.autoDispose<List<IndexTopic>>(
  (ref) => _changesOf(ref.watch(indexRepositoryProvider).watchTopics()),
);

/// El nombre de cada tema del Índice por su clave: lo que dice «también
/// en…». Sale de [indexTopicsProvider], que ya está leído: un documento solo
/// puede estar en temas que tienen documentos.
final indexTopicNamesProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final topics = ref.watch(indexTopicsProvider).valueOrNull ?? const [];
  return {
    for (final topic in topics)
      if (topic.spaceId case final id?) id: topic.name,
  };
});

/// Los documentos de un tema —`null` es «Sin tema»—, de la A a la Z.
final indexTopicDocumentsProvider = StreamProvider.autoDispose
    .family<List<IndexDocument>, String?>(
      (ref, spaceId) => _changesOf(
        ref.watch(indexRepositoryProvider).watchDocumentsOf(spaceId),
      ),
    );

/// Todos los documentos, en el orden pedido: «Por documento» y los títulos que
/// filtra la búsqueda.
final indexDocumentsProvider = StreamProvider.autoDispose
    .family<List<IndexDocument>, IndexDocumentOrder>(
      (ref, order) =>
          _changesOf(ref.watch(indexRepositoryProvider).watchDocuments(order)),
    );

/// Las entradas de un documento: solo mientras está desplegado.
final indexEntriesProvider = StreamProvider.autoDispose
    .family<List<IndexEntry>, String>(
      (ref, documentId) => _changesOf(
        ref.watch(indexRepositoryProvider).watchEntries(documentId),
      ),
    );

/// Cuántas coincidencias trae como mucho una búsqueda —las mejores, que se
/// muestran en el orden del Índice—: el corte de
/// [IndexRepository.watchSearch], que la pantalla dice cuando se alcanza.
const kIndexSearchLimit = 200;

/// Los capítulos y las imágenes que coinciden con lo buscado, con sus padres:
/// como mucho [kIndexSearchLimit].
final indexSearchProvider = StreamProvider.autoDispose
    .family<List<IndexSearchHit>, String>(
      (ref, query) =>
          _changesOf(ref.watch(indexRepositoryProvider).watchSearch(query)),
    );

/// Cómo va el relleno: la línea de avance.
final indexProgressProvider = StreamProvider.autoDispose<IndexProgress>(
  (ref) => ref.watch(indexRepositoryProvider).watchProgress().distinct(),
);
