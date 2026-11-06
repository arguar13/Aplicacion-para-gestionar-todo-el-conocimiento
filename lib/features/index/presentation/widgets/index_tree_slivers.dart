import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/index/domain/entities/index_tree.dart';
import 'package:sinapsis/features/index/domain/services/index_outline.dart';
import 'package:sinapsis/features/index/presentation/index_opening.dart';
import 'package:sinapsis/features/index/presentation/providers/index_arrivals.dart';
import 'package:sinapsis/features/index/presentation/providers/index_providers.dart';
import 'package:sinapsis/features/index/presentation/providers/index_view.dart';
import 'package:sinapsis/features/index/presentation/widgets/index_rows.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

// El árbol del Índice (F46), armado con slivers para que la pantalla nunca
// traiga ni dibuje todo:
//
// - cada tema es un grupo con su encabezado fijo arriba mientras se recorren
//   sus documentos (`SliverMainAxisGroup` + `PinnedHeaderSliver`), y sus
//   documentos se leen recién cuando el grupo llega cerca de la pantalla
//   ([IndexWhenNear]);
// - los documentos plegados son una lista perezosa, que dibuja de a lo que
//   entra;
// - un documento desplegado es otro grupo, con su encabezado fijo debajo del
//   del tema y sus entradas, que se leen recién al desplegarlo;
// - cada parte mira solo lo suyo: un documento que cambia vuelve a dibujar
//   su grupo, no el árbol.

/// El alto aproximado de la fila de un documento: lo que ocupa un tema
/// mientras sus documentos todavía no se leyeron. Sigue a la letra.
double indexDocumentRowEstimate(BuildContext context) =>
    24 + MediaQuery.textScalerOf(context).scale(40);

/// Un sliver que se arma recién cuando llega cerca de la pantalla: hasta
/// entonces ocupa [estimate] y no lee nada.
///
/// Un `SliverList` dibuja siempre al menos su primera fila, aunque esté a
/// mil pantallas de distancia, y la primera fila de los documentos de un
/// tema es leer los documentos de ese tema: con cien temas desplegados
/// serían cien lecturas, que se repiten con cada cambio de la base. Así son
/// solo las de los temas que se ven, o que se vieron.
///
/// Una vez armado se queda armado: volver a ocupar [estimate] al pasar de
/// largo movería lo que se está mirando.
class IndexWhenNear extends StatefulWidget {
  const IndexWhenNear({
    required this.estimate,
    required this.sliver,
    super.key,
  });

  final double estimate;
  final Widget sliver;

  @override
  State<IndexWhenNear> createState() => _IndexWhenNearState();
}

class _IndexWhenNearState extends State<IndexWhenNear> {
  var _near = false;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      // Cerca: dentro de lo que el visor prepara, o ya pasado.
      if (constraints.remainingCacheExtent > 0 ||
          constraints.scrollOffset > 0) {
        _near = true;
      }
      // El mismo sliver en cada cuadro, sin armarlo de nuevo: desplazar solo
      // mueve lo que ya está.
      return _near
          ? widget.sliver
          : SliverToBoxAdapter(child: SizedBox(height: widget.estimate));
    },
  );
}

/// La clave de la fila de cada documento, por lista: una por documento bajo
/// cada tema, y otra en «Por documento».
///
/// Al desplegarse, la fila pasa de la lista perezosa de los plegados a ser el
/// encabezado fijo de su grupo; con la misma clave es la misma fila, y no una
/// nueva: quien la desplegó con el teclado sigue parado en ella, y → ← la
/// pliegan y despliegan sin perder el lugar.
class IndexRowKeys {
  final _keys = <(String, String), GlobalKey>{};

  GlobalKey of(String list, String documentId) => _keys.putIfAbsent((
    list,
    documentId,
  ), () => GlobalKey(debugLabel: 'índice $list $documentId'));
}

/// Las claves de las filas de documentos del Índice.
final indexRowKeysProvider = Provider<IndexRowKeys>((ref) => IndexRowKeys());

/// El árbol «Por tema»: un grupo por tema, en el orden de [topics].
List<Widget> indexTopicSlivers(List<IndexTopic> topics) => [
  for (final topic in topics)
    IndexTopicSliver(key: ValueKey('topic:${topic.spaceId}'), topic: topic),
];

/// Un tema: su encabezado, fijo arriba mientras se recorren sus documentos,
/// y sus documentos si está desplegado.
class IndexTopicSliver extends ConsumerWidget {
  const IndexTopicSliver({required this.topic, super.key});

  final IndexTopic topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceId = topic.spaceId;
    final unfolded = !ref.watch(
      indexViewProvider.select((v) => v.foldedTopics.contains(spaceId)),
    );
    final estimate = topic.documentCount * indexDocumentRowEstimate(context);
    return SliverMainAxisGroup(
      slivers: [
        PinnedHeaderSliver(
          child: IndexTopicHeader(
            key: ValueKey('index-topic-$spaceId'),
            topic: topic,
            unfolded: unfolded,
            onToggle: () =>
                ref.read(indexViewProvider.notifier).toggleTopic(spaceId),
          ),
        ),
        if (unfolded)
          IndexWhenNear(
            estimate: estimate,
            sliver: IndexTopicDocuments(spaceId: spaceId, estimate: estimate),
          ),
      ],
    );
  }
}

/// Los documentos de un tema, que se leen al armarse.
class IndexTopicDocuments extends ConsumerWidget {
  const IndexTopicDocuments({
    required this.spaceId,
    required this.estimate,
    super.key,
  });

  final String? spaceId;

  /// Lo que ocupa mientras se leen: lo mismo que ocupaba antes, para que
  /// nada salte.
  final double estimate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(indexTopicDocumentsProvider(spaceId));
    return switch (documents) {
      AsyncValue(valueOrNull: final value?) => IndexDocumentRun(
        list: 'topic:$spaceId',
        documents: value,
        place: IndexDocumentPlace.underTopic(spaceId),
      ),
      AsyncValue(:final error?) => SliverToBoxAdapter(
        child: IndexEntriesNote(
          text: AppLocalizations.of(context)!.globalErrorUnexpected,
          key: ValueKey('index-topic-error-$spaceId-$error'),
        ),
      ),
      _ => SliverToBoxAdapter(child: SizedBox(height: estimate)),
    };
  }
}

/// «Por documento»: todos, en el orden pedido.
class IndexAllDocuments extends ConsumerWidget {
  const IndexAllDocuments({required this.order, super.key});

  final IndexDocumentOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(indexDocumentsProvider(order));
    return switch (documents) {
      AsyncValue(valueOrNull: final value?) => IndexDocumentRun(
        list: 'all:${order.name}',
        documents: value,
        place: const IndexDocumentPlace.listed(),
      ),
      AsyncValue(:final error?) => SliverToBoxAdapter(
        child: IndexEntriesNote(
          text: AppLocalizations.of(context)!.globalErrorUnexpected,
          key: ValueKey('index-all-error-$error'),
        ),
      ),
      _ => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    };
  }
}

/// Una lista de documentos: los plegados, de a tramos perezosos; cada uno
/// desplegado, su grupo con el encabezado fijo y sus entradas.
class IndexDocumentRun extends ConsumerWidget {
  const IndexDocumentRun({
    required this.list,
    required this.documents,
    required this.place,
    super.key,
  });

  /// Qué lista es, para saber qué llegó entre una lectura y otra.
  final String list;
  final List<IndexDocument> documents;
  final IndexDocumentPlace place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solo los desplegados de esta lista, como texto: desplegar uno de otro
    // tema no vuelve a armar esta.
    final open = ref
        .watch(
          indexViewProvider.select(
            (v) => [
              for (final d in documents)
                if (v.openDocuments.contains(d.id)) d.id,
            ].join('\u0000'),
          ),
        )
        .split('\u0000')
        .toSet();
    final arrivals = ref.read(indexArrivalsProvider)
      ..observe(list, documents.map(indexDocumentIdentity));

    final slivers = <Widget>[];
    var run = <IndexDocument>[];
    void flush() {
      if (run.isEmpty) return;
      slivers.add(
        _ClosedDocuments(
          key: ValueKey('$list:closed:${run.first.id}'),
          list: list,
          documents: run,
          place: place,
          arrivals: arrivals,
        ),
      );
      run = <IndexDocument>[];
    }

    for (final document in documents) {
      if (open.contains(document.id)) {
        flush();
        slivers.add(
          IndexOpenDocument(
            key: ValueKey('$list:open:${document.id}'),
            list: list,
            document: document,
            place: place,
            arrivedAt: arrivals.freshArrival(indexDocumentIdentity(document)),
          ),
        );
      } else {
        run.add(document);
      }
    }
    flush();
    return SliverMainAxisGroup(slivers: slivers);
  }
}

/// Documentos plegados seguidos, de a los que entran en la pantalla.
class _ClosedDocuments extends ConsumerWidget {
  const _ClosedDocuments({
    required this.list,
    required this.documents,
    required this.place,
    required this.arrivals,
    super.key,
  });

  final String list;
  final List<IndexDocument> documents;
  final IndexDocumentPlace place;
  final IndexArrivals arrivals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.read(indexRowKeysProvider);
    final at = {for (final (i, d) in documents.indexed) keys.of(list, d.id): i};
    return SliverList.builder(
      itemCount: documents.length,
      // Lo que llega o se va arriba no le cambia la fila a lo de abajo.
      findChildIndexCallback: (key) => at[key],
      itemBuilder: (context, index) {
        final document = documents[index];
        return IndexDocumentRow(
          key: keys.of(list, document.id),
          document: document,
          place: place,
          unfolded: false,
          arrivedAt: arrivals.freshArrival(indexDocumentIdentity(document)),
          onTap: () =>
              ref.read(indexViewProvider.notifier).toggleDocument(document.id),
        );
      },
    );
  }
}

/// Un documento desplegado: su fila, fija debajo de la del tema mientras se
/// recorren sus entradas, y sus entradas.
class IndexOpenDocument extends ConsumerWidget {
  const IndexOpenDocument({
    required this.list,
    required this.document,
    required this.place,
    this.arrivedAt,
    super.key,
  });

  /// La lista en la que está: la clave de su fila.
  final String list;
  final IndexDocument document;
  final IndexDocumentPlace place;
  final DateTime? arrivedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SliverMainAxisGroup(
    slivers: [
      PinnedHeaderSliver(
        child: IndexDocumentRow(
          key: ref.read(indexRowKeysProvider).of(list, document.id),
          document: document,
          place: place,
          unfolded: true,
          pinned: true,
          arrivedAt: arrivedAt,
          onTap: () =>
              ref.read(indexViewProvider.notifier).toggleDocument(document.id),
        ),
      ),
      IndexEntriesSliver(document: document),
    ],
  );
}

/// Las entradas de un documento desplegado, plegadas como dicen los niveles
/// y lo elegido a mano.
class IndexEntriesSliver extends ConsumerWidget {
  const IndexEntriesSliver({required this.document, super.key});

  final IndexDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final id = document.id;
    final entries = ref.watch(indexEntriesProvider(id));
    final depth = ref.watch(indexViewProvider.select((v) => v.depth.levels));
    final numbered = ref.watch(indexViewProvider.select((v) => v.numbered));
    final folds = ref.watch(
      indexViewProvider.select(
        (v) => v.chapterFolds[id] ?? const <int, bool>{},
      ),
    );
    final pending = document.hasText && !document.indexed;

    final value = entries.valueOrNull;
    if (value == null) {
      return SliverToBoxAdapter(
        child: entries.hasError
            ? IndexEntriesNote(text: l10n.globalErrorUnexpected)
            : IndexEntriesNote(text: l10n.f46P3EntriesLoading, loading: true),
      );
    }

    final identities = indexEntryIdentities(value);
    final arrivals = ref.read(indexArrivalsProvider)
      ..observe('entries:$id', identities);
    final identityOf = {
      for (final (i, entry) in value.indexed) entry.key: identities[i],
    };
    final rows = indexOutline(
      value,
      depth: depth,
      folds: folds,
      numbered: numbered,
    );
    final at = {for (final (i, row) in rows.indexed) row.entry.key: i};
    final controller = ref.read(indexViewProvider.notifier);

    return SliverMainAxisGroup(
      slivers: [
        if (pending)
          SliverToBoxAdapter(
            child: IndexEntriesNote(text: l10n.f46P3EntriesPending),
          )
        else if (rows.isEmpty)
          SliverToBoxAdapter(
            child: IndexEntriesNote(text: l10n.f46P3EntriesNone),
          ),
        SliverList.builder(
          itemCount: rows.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<int> ? at[key.value] : null,
          itemBuilder: (context, index) {
            final row = rows[index];
            final entry = row.entry;
            return IndexEntryRow(
              key: ValueKey(entry.key),
              row: row,
              arrivedAt: arrivals.freshArrival(identityOf[entry.key]!),
              onOpen: () =>
                  openIndexEntry(context, ref, IndexOpening.of(entry)),
              onToggle: () => controller.toggleChapter(
                id,
                entry.key,
                unfolded: row.unfolded,
              ),
            );
          },
        ),
        // Un respiro debajo del último capítulo, antes del documento que
        // sigue.
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}
