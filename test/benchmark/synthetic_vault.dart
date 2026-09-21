import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/knowledge_mirror_mapping.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/entities/content_block.dart';
import 'package:sinapsis/core/domain/entities/date_precision.dart';
import 'package:sinapsis/core/domain/entities/historical_date.dart';
import 'package:sinapsis/core/domain/entities/item_property_origin.dart';
import 'package:sinapsis/core/domain/entities/item_state.dart';
import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/note_maturity.dart';
import 'package:sinapsis/core/domain/entities/processing_state.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/rendition_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/vocabulary_hierarchy.dart';
import 'package:sinapsis/core/domain/services/chunking_service.dart';

/// Cambia cuando cambia lo que el generador escribe: invalida la bóveda que el
/// benchmark dejó guardada en disco y obliga a armarla de nuevo.
///
/// v5 (F13): «Tema» pasa a ser un vocabulario JERÁRQUICO de 2.000 valores con
/// 10.000 elementos —una quinta parte, no un 6 %—, hasta cinco niveles y con
/// unas pocas ramas enormes: lo que piden las mediciones del filtro por un tema
/// y de sus subtemas y las del Atlas.
const kSyntheticVaultVersion = 5;

/// Cuánto hay en la bóveda sintética, con las proporciones de una bóveda de
/// verdad: la mayoría son fuentes largas (artículos, transcripciones,
/// documentos), una parte son notas propias y el resto, recortes cortos.
///
/// Con `items: 10000` salen unos 300.000 chunks, que es lo que pide la
/// medición previa de F10. Con un número chico sirve para las pruebas que
/// corren siempre.
class VaultProfile {
  const VaultProfile({this.items = 10000});

  final int items;

  int get notes => (items * 0.28).round();
  int get articles => (items * 0.38).round();
  int get transcripts => (items * 0.14).round();
  int get documents => (items * 0.07).round();
  int get posts => items - notes - articles - transcripts - documents;

  /// Cuántos párrafos —o ventanas de transcripción— tiene, de promedio, cada
  /// tipo de fuente. Son los que dan los ~300.000 chunks con 10.000 elementos.
  static const articleChunks = 42;
  static const transcriptChunks = 66;
  static const documentChunks = 66;
  static const postChunks = 2;

  int get relations => items * 5 ~/ 2;
  int get highlights => items * 6 ~/ 10;
  int get flashcards => items * 3 ~/ 10;
  int get inlineLinks => items ~/ 2;
  int get datedItems => items * 35 ~/ 100;
  int get spaces => max(3, items ~/ 800);
  int get tagValues => max(20, items ~/ 5);

  /// Cuántos valores de «Tema» son del primer nivel: el resto cuelga de otro.
  /// Pocos, para que unas cuantas ramas se lleven casi todo.
  int get temaRoots => max(4, tagValues ~/ 40);
  int get otherValuesPerCategory => max(8, items ~/ 100);

  /// Los chunks que se esperan, sin contar los que salgan de más o de menos
  /// según dónde caiga cada corte.
  int get expectedChunks =>
      articles * articleChunks +
      transcripts * transcriptChunks +
      documents * documentChunks +
      posts * postChunks;
}

/// Lo que el benchmark necesita saber de la bóveda que se armó: a quién
/// preguntarle y con qué palabras buscar.
class SyntheticVault {
  const SyntheticVault({
    required this.profile,
    required this.largestSourceId,
    required this.hubItemId,
    required this.typicalItemId,
    required this.noteWithLinksId,
    required this.temaDefinitionId,
    required this.bigRootValueId,
    required this.leafValueId,
    required this.rareTerm,
    required this.mediumTerm,
    required this.commonTerm,
    required this.now,
    required this.counts,
  });

  factory SyntheticVault.fromJson(Map<String, Object?> json) => SyntheticVault(
    profile: VaultProfile(items: json['items']! as int),
    largestSourceId: json['largestSourceId']! as String,
    hubItemId: json['hubItemId']! as String,
    typicalItemId: json['typicalItemId']! as String,
    noteWithLinksId: json['noteWithLinksId']! as String,
    temaDefinitionId: json['temaDefinitionId']! as String,
    bigRootValueId: json['bigRootValueId']! as String,
    leafValueId: json['leafValueId']! as String,
    rareTerm: json['rareTerm']! as String,
    mediumTerm: json['mediumTerm']! as String,
    commonTerm: json['commonTerm']! as String,
    now: DateTime.parse(json['now']! as String),
    counts: (json['counts']! as Map<String, Object?>).cast<String, int>(),
  );

  final VaultProfile profile;

  /// La fuente con más chunks: el peor caso para abrir un detalle.
  final String largestSourceId;

  /// El elemento con más vínculos: el peor caso para el grafo local.
  final String hubItemId;

  /// Un elemento con la cantidad de vínculos que tiene el común de los
  /// elementos conectados: el caso de todos los días para el grafo local.
  final String typicalItemId;

  final String noteWithLinksId;

  /// La categoría «Tema» y dos de sus valores: el del primer nivel con más
  /// subtemas —el peor caso del filtro transitivo y de la cascada del Atlas— y
  /// una hoja, el mismo filtro sin descendientes.
  final String temaDefinitionId;
  final String bigRootValueId;
  final String leafValueId;

  /// Una palabra que casi no aparece, una que aparece en cientos de chunks y
  /// una que aparece en casi todos: los tres extremos de una búsqueda.
  final String rareTerm;
  final String mediumTerm;
  final String commonTerm;

  /// El "ahora" con el que se armó la bóveda.
  final DateTime now;

  /// Cuántas filas quedaron en cada tabla, para el informe.
  final Map<String, int> counts;

  Map<String, Object?> toJson() => {
    'items': profile.items,
    'largestSourceId': largestSourceId,
    'hubItemId': hubItemId,
    'typicalItemId': typicalItemId,
    'noteWithLinksId': noteWithLinksId,
    'temaDefinitionId': temaDefinitionId,
    'bigRootValueId': bigRootValueId,
    'leafValueId': leafValueId,
    'rareTerm': rareTerm,
    'mediumTerm': mediumTerm,
    'commonTerm': commonTerm,
    'now': now.toIso8601String(),
    'counts': counts,
  };
}

/// Arma la bóveda sintética en [db], que tiene que estar vacía.
///
/// Escribe directamente en las tablas —los dos modelos, tal como los deja
/// `LibraryRepositoryImpl.save`— y no por los repositorios: guardar diez mil
/// elementos de a uno tardaría minutos y lo que se mide es la lectura, no la
/// escritura. Todo lo que sale es determinista para la misma [seed].
Future<SyntheticVault> buildSyntheticVault(
  AppDatabase db, {
  VaultProfile profile = const VaultProfile(),
  int seed = 20260919,
  void Function(String message)? onProgress,
}) async {
  final builder = _VaultBuilder(db, profile, Random(seed), onProgress);
  return builder.build();
}

/// El "ahora" de la bóveda sintética: fijo, para que dos corridas armen lo
/// mismo.
final _kNow = DateTime.utc(2026, 9, 19, 12);

String _id(String prefix, int n) {
  // Del mismo largo que un UUID, que es lo que ocupan los ids reales en los
  // índices.
  final hex = n.toRadixString(16).padLeft(12, '0');
  final tag = prefix.codeUnits
      .map((c) => c.toRadixString(16).padLeft(2, '0'))
      .join()
      .padRight(4, '0')
      .substring(0, 4);
  return '00000000-$tag-7000-8000-$hex';
}

/// Muestrea posiciones con la distribución de una lengua: pocas palabras
/// aparecen en todas partes y la inmensa mayoría casi nunca.
class _Zipf {
  _Zipf(int n, this._random) : _cumulative = List<double>.filled(n, 0) {
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += 1 / (i + 1);
      _cumulative[i] = sum;
    }
  }

  final Random _random;
  final List<double> _cumulative;

  int next() {
    final target = _random.nextDouble() * _cumulative.last;
    var low = 0;
    var high = _cumulative.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_cumulative[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

class _Text {
  _Text(this._random) {
    final zipf = _Zipf(_wordCount, _random);
    _words = _makeWords();
    _sentences = List.generate(_sentenceCount, (_) {
      final length = 8 + _random.nextInt(9);
      final words = [for (var i = 0; i < length; i++) _words[zipf.next()]];
      final sentence = words.join(' ');
      return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
    });
    _titleZipf = zipf;
  }

  static const _wordCount = 4000;
  static const _sentenceCount = 40000;

  final Random _random;
  late final List<String> _words;
  late final List<String> _sentences;
  late final _Zipf _titleZipf;

  String word(int rank) => _words[rank];

  List<String> _makeWords() {
    const onsets = [
      'b', 'c', 'd', 'f', 'g', 'l', 'm', 'n', 'p', 'r', 's', 't', 'v', //
      'z', 'br', 'cr', 'tr', 'pl', 'gr', 'ch',
    ];
    const vowels = ['a', 'e', 'i', 'o', 'u', 'ia', 'io', 'ue'];
    const codas = ['', '', '', 'n', 's', 'r', 'l'];
    final seen = <String>{};
    final words = <String>[];
    while (words.length < _wordCount) {
      final syllables = 2 + _random.nextInt(3);
      final buffer = StringBuffer();
      for (var i = 0; i < syllables; i++) {
        buffer
          ..write(onsets[_random.nextInt(onsets.length)])
          ..write(vowels[_random.nextInt(vowels.length)]);
      }
      buffer.write(codas[_random.nextInt(codas.length)]);
      final word = buffer.toString();
      if (seen.add(word)) words.add(word);
    }
    return words;
  }

  String sentence() => _sentences[_random.nextInt(_sentences.length)];

  String paragraph() {
    final count = 1 + _random.nextInt(5);
    return List.generate(count, (_) => sentence()).join(' ');
  }

  String title(int words) {
    final parts = [for (var i = 0; i < words; i++) _words[_titleZipf.next()]];
    final text = parts.join(' ');
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  String article(int paragraphs) {
    final body = List.generate(paragraphs, (_) => paragraph()).join('\n\n');
    return '# ${title(4)}\n\n$body';
  }

  /// Líneas `[mm:ss] frase`, unas trece por ventana de 75 s, como las que
  /// deja la transcripción de un video.
  String transcript(int windows) {
    final lines = <String>[];
    var seconds = 0;
    final total = windows * 13;
    for (var i = 0; i < total; i++) {
      final minutes = seconds ~/ 60;
      final rest = (seconds % 60).toString().padLeft(2, '0');
      lines.add('[$minutes:$rest] ${sentence()}');
      seconds += 5 + _random.nextInt(2);
    }
    return lines.join('\n');
  }

  String document(int paragraphs) {
    final pages = <String>[];
    for (var i = 0; i < paragraphs; i += 3) {
      pages.add(
        List.generate(min(3, paragraphs - i), (_) => paragraph()).join('\n\n'),
      );
    }
    return pages.join('\n\n---\n\n');
  }
}

/// Junta filas y las escribe de a miles: una inserción por fila es lo que
/// haría lento armar diez mil elementos, y ninguna de las tablas necesita
/// que se escriba de otra manera.
class _Buffer<D> {
  _Buffer(this._db, this._table);

  final AppDatabase _db;
  final TableInfo<Table, D> _table;
  final List<Insertable<D>> _rows = [];

  int written = 0;

  void add(Insertable<D> row) => _rows.add(row);

  Future<void> flush() async {
    if (_rows.isEmpty) return;
    await _db.batch((b) => b.insertAll(_table, _rows));
    written += _rows.length;
    _rows.clear();
  }
}

class _VaultBuilder {
  _VaultBuilder(this.db, this.profile, this.random, this.onProgress)
    : text = _Text(random),
      _spaces = _Buffer(db, db.spaces),
      _renditions = _Buffer(db, db.renditions),
      _entries = _Buffer(db, db.knowledgeEntries),
      _knowledgeSources = _Buffer(db, db.knowledgeSources),
      _knowledgeNotes = _Buffer(db, db.knowledgeNotes),
      _chunks = _Buffer(db, db.chunks),
      _highlights = _Buffer(db, db.highlights),
      _flashcards = _Buffer(db, db.flashcards),
      _definitions = _Buffer(db, db.propertyDefinitions),
      _values = _Buffer(db, db.propertyValues),
      _assignments = _Buffer(db, db.itemPropertyValues),
      _relations = _Buffer(db, db.relations),
      _inlineLinks = _Buffer(db, db.inlineLinks);

  final AppDatabase db;
  final VaultProfile profile;
  final Random random;
  final void Function(String message)? onProgress;
  final _Text text;
  final _clock = Stopwatch()..start();
  final _flushTime = <String, Duration>{};

  final _Buffer<SpaceRow> _spaces;
  final _Buffer<RenditionRow> _renditions;
  final _Buffer<KnowledgeEntryRow> _entries;
  final _Buffer<KnowledgeSourceRow> _knowledgeSources;
  final _Buffer<KnowledgeNoteRow> _knowledgeNotes;
  final _Buffer<ChunkRow> _chunks;
  final _Buffer<HighlightRow> _highlights;
  final _Buffer<FlashcardRow> _flashcards;
  final _Buffer<PropertyDefinitionRow> _definitions;
  final _Buffer<PropertyValueRow> _values;
  final _Buffer<ItemPropertyValueRow> _assignments;
  final _Buffer<RelationRow> _relations;
  final _Buffer<InlineLinkRow> _inlineLinks;

  late final List<String> _spaceIds;
  late final List<String> _valueIds;
  late final List<String> _dateValueIds;
  late final _Zipf _valueZipf;

  final _itemIds = <String>[];
  final _itemTitles = <String>[];
  final _noteIndexes = <int>[];
  final _relationDegree = <String, int>{};
  String _largestSourceId = '';
  int _largestSourceChunks = 0;

  /// Las notas con enlaces `[[así]]`, en el orden en que se escriben: de ahí
  /// sale la del benchmark cuando ya se sabe cuántas relaciones tiene cada una.
  final _linkedNotes = <String>[];
  String _temaDefinitionId = '';
  String _bigRootValueId = '';
  String _leafValueId = '';

  static const _batchItems = 200;

  void _say(String message) =>
      onProgress?.call('[${_clock.elapsed.inSeconds} s] $message');

  Future<void> _phase(String name, Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    await body();
    _say('$name: ${watch.elapsed.inMilliseconds} ms');
  }

  Future<SyntheticVault> build() async {
    await db.transaction(() async {
      // Los triggers que mantienen el índice de texto se apartan durante la
      // carga: con ellos, cada forma que se inserta reescribe la fila
      // entera del índice, y armar la bóveda tardaba media hora. Se
      // restauran al final y el índice se puebla de una sola vez.
      final triggers = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
          )
          .get();
      for (final trigger in triggers) {
        await db.customStatement(
          'DROP TRIGGER "${trigger.read<String>('name')}"',
        );
      }

      await _phase('espacios', _seedSpaces);
      await _phase('vocabulario', _seedVocabulary);
      await _phase('elementos', _seedItems);
      await _phase('relaciones', _seedRelations);
      await _phase('enlaces', _seedInlineLinks);

      for (final trigger in triggers) {
        await db.customStatement(trigger.read<String>('sql'));
      }
      await _phase('índice de texto', _populateSearchIndex);
    });
    final written = _flushTime.entries.map(
      (e) => '${e.key} ${e.value.inSeconds} s',
    );
    _say('escritura por tabla: ${written.join(', ')}');

    final hub = _relationDegree.entries.fold<MapEntry<String, int>?>(
      null,
      (best, e) => best == null || e.value > best.value ? e : best,
    );

    final byDegree = _relationDegree.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final typical = byDegree.isEmpty
        ? _itemIds.first
        : byDegree[byDegree.length ~/ 2].key;
    final typicalDegree = byDegree.isEmpty
        ? 0
        : byDegree[byDegree.length ~/ 2].value;

    // «Una nota con enlaces» de las de todos los días: la que tiene tantas
    // relaciones como el elemento típico. Con la primera que se escribió
    // dependía de la suerte del sorteo —los primeros elementos son los que más
    // relaciones reciben, y salió una con 1.235—.
    final noteWithLinks = _linkedNotes.isEmpty
        ? ''
        : _linkedNotes.reduce((best, id) {
            int distance(String note) =>
                ((_relationDegree[note] ?? 0) - typicalDegree).abs();
            return distance(id) < distance(best) ? id : best;
          });

    return SyntheticVault(
      profile: profile,
      largestSourceId: _largestSourceId,
      hubItemId: hub?.key ?? _itemIds.first,
      typicalItemId: typical,
      noteWithLinksId: noteWithLinks,
      temaDefinitionId: _temaDefinitionId,
      bigRootValueId: _bigRootValueId,
      leafValueId: _leafValueId,
      rareTerm: text.word(3000),
      mediumTerm: text.word(250),
      commonTerm: text.word(12),
      now: _kNow,
      counts: await countVaultRows(db),
    );
  }

  /// Puebla los índices de texto como lo habrían hecho los triggers:
  /// `item_search` —título, subtítulo y el texto de las notas— y `chunk_search`
  /// reconstruido desde `chunks`.
  ///
  /// Cuando un índice de texto cambie de forma, esta función cambia con él, y
  /// con ella `kSyntheticVaultVersion`.
  Future<void> _populateSearchIndex() async {
    await db.customStatement(populateItemSearch);
    await db.customStatement(rebuildChunkSearch);
  }

  Future<void> _flushItemBlock() async {
    // En el orden de las claves foráneas: cada tabla después de aquello a lo
    // que apunta. Desde v18 las formas, las tarjetas y los vínculos cuelgan de
    // `item`, no de `items`.
    for (final (name, buffer) in [
      ('item', _entries),
      ('source', _knowledgeSources),
      ('note', _knowledgeNotes),
      ('renditions', _renditions),
      ('chunks', _chunks),
      ('highlights', _highlights),
      ('flashcards', _flashcards),
    ]) {
      final watch = Stopwatch()..start();
      await buffer.flush();
      _flushTime.update(
        name,
        (d) => d + watch.elapsed,
        ifAbsent: () => watch.elapsed,
      );
    }
  }

  Future<void> _seedSpaces() async {
    _spaceIds = [for (var i = 0; i < profile.spaces; i++) _id('space', i)];
    for (final (i, id) in _spaceIds.indexed) {
      _spaces.add(
        SpacesCompanion.insert(
          id: id,
          name: 'Espacio ${i + 1}',
          createdAt: _kNow.subtract(Duration(days: 900 - i)),
        ),
      );
    }
    await _spaces.flush();
  }

  Future<void> _seedVocabulary() async {
    // "Tema" y "Fecha del hecho" ya las sembró la propia base al crearse.
    final temaId = (await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals(kTemaCategoryName))).getSingle()).id;
    final dateDefinitionId = (await (db.select(
      db.propertyDefinitions,
    )..where((d) => d.name.equals(kFechaDelHechoCategoryName))).getSingle()).id;

    // «Autor» no está: desde F15 es una categoría de sistema, sembrada por la
    // propia base, y una de usuario con ese nombre chocaría con ella.
    const others = [
      'Región',
      'Época',
      'Colección',
      'Idioma',
      'Disciplina',
      'Proyecto',
      'Lugar',
      'Personaje',
      'Obra',
      'Estado',
    ];
    final definitionIds = <String>[temaId];
    for (final (i, name) in others.indexed) {
      final id = _id('defn', i);
      definitionIds.add(id);
      _definitions.add(
        PropertyDefinitionsCompanion.insert(
          id: id,
          name: name,
          createdAt: _kNow.subtract(const Duration(days: 800)),
        ),
      );
    }
    await _definitions.flush();

    final valueIds = <String>[];
    // Los valores de «Tema» en el orden en que se escriben, con su lugar en el
    // árbol: un padre siempre va ANTES que sus hijos.
    final temaTree = <({String id, String? parentId, int depth})>[];

    /// Dónde cuelga el próximo valor de «Tema»: los primeros son raíces; el
    /// resto, hijo de otro con lugar para un nivel más, elegido con sesgo hacia
    /// los primeros —los ricos se hacen más ricos—, así unas pocas ramas
    /// concentran casi todo y llegan a los cinco niveles.
    ({String? parentId, int depth}) placeInTema() {
      if (temaTree.length < profile.temaRoots) {
        return (parentId: null, depth: 0);
      }
      for (var attempt = 0; attempt < 8; attempt++) {
        final index = (pow(random.nextDouble(), 2) * temaTree.length).floor();
        final candidate = temaTree[index];
        if (candidate.depth < kVocabularyMaxDepth) {
          return (parentId: candidate.id, depth: candidate.depth + 1);
        }
      }
      return (parentId: null, depth: 0);
    }

    var n = 0;
    void addValue(
      String definitionId,
      String label, {
      String? parentId,
      int depth = 0,
    }) {
      final id = _id('valu', n++);
      valueIds.add(id);
      if (definitionId == temaId) {
        temaTree.add((id: id, parentId: parentId, depth: depth));
      }
      _values.add(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: definitionId,
          value: label,
          createdAt: _kNow.subtract(Duration(days: 700 - n % 600)),
          parentId: Value(parentId),
          depth: Value(depth),
        ),
      );
    }

    // Un vocabulario con los defectos de uno real: variantes con y sin
    // acento, con una letra de más, en plural. Son los candidatos a fusionar
    // que el cálculo tiene que encontrar entre miles de valores.
    String labelAt(int i) {
      final word = text.word(100 + i);
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }

    final seenLabels = <String, Set<String>>{};
    void addWithVariants(String definitionId, int i) {
      final label = labelAt(i);
      final seen = seenLabels.putIfAbsent(definitionId, () => <String>{});
      // Una variante cuelga del mismo padre que su original: son hermanas,
      // los candidatos a fusionar que el vocabulario de verdad tiene.
      final place = definitionId == temaId
          ? placeInTema()
          : (parentId: null, depth: 0);
      void add(String text) => addValue(
        definitionId,
        text,
        parentId: place.parentId,
        depth: place.depth,
      );
      if (seen.add(label.toLowerCase())) add(label);
      if (i % 17 == 0) {
        final variant = '${label}s';
        if (seen.add(variant.toLowerCase())) add(variant);
      } else if (i % 23 == 0 && label.length > 3) {
        final variant = label.replaceFirst('a', 'á');
        if (variant != label && seen.add(variant.toLowerCase())) add(variant);
      }
    }

    for (var i = 0; i < profile.tagValues; i++) {
      addWithVariants(temaId, i);
    }
    for (final definitionId in definitionIds.skip(1)) {
      for (var i = 0; i < profile.otherValuesPerCategory; i++) {
        addWithVariants(definitionId, i + 7);
      }
    }
    await _values.flush();
    _valueIds = valueIds;
    _valueZipf = _Zipf(valueIds.length, random);

    // Cuántos valores cuelgan de cada uno de «Tema», él incluido. Los padres
    // van antes que los hijos: recorrer al revés suma cada rama en su padre.
    final subtree = {for (final node in temaTree) node.id: 1};
    for (final node in temaTree.reversed) {
      final parent = node.parentId;
      if (parent != null) {
        subtree[parent] = subtree[parent]! + subtree[node.id]!;
      }
    }
    final roots = [
      for (final node in temaTree)
        if (node.parentId == null) node,
    ];
    final bigRoot = roots.reduce(
      (best, node) => subtree[node.id]! > subtree[best.id]! ? node : best,
    );
    final parents = {
      for (final node in temaTree)
        if (node.parentId != null) node.parentId!,
    };
    // La primera hoja que no es raíz: de las que más asignaciones recibe.
    final leaf = temaTree.firstWhere(
      (node) => node.parentId != null && !parents.contains(node.id),
      orElse: () => temaTree.first,
    );
    _temaDefinitionId = temaId;
    _bigRootValueId = bigRoot.id;
    _leafValueId = leaf.id;

    // Las fechas del hecho: un año entre el 800 a.C. y hoy, con toda la
    // gama de precisiones y algunas aproximadas.
    final dateIds = <String>[];
    final distinct = max(10, profile.datedItems ~/ 2);
    final seenDates = <String>{};
    for (var i = 0; i < distinct; i++) {
      final year = -800 + random.nextInt(2820);
      final precision = DatePrecision.values[random.nextInt(5)];
      final date = HistoricalDate.fromAstronomicalYear(
        year,
        precision: precision,
        month:
            precision == DatePrecision.day || precision == DatePrecision.month
            ? 1 + random.nextInt(12)
            : null,
        day: precision == DatePrecision.day ? 1 + random.nextInt(28) : null,
        isCirca: random.nextInt(10) == 0,
      );
      if (!seenDates.add(date.label.toLowerCase())) continue;
      final id = _id('date', i);
      dateIds.add(id);
      final start = date.rangeStart;
      final end = date.rangeEnd;
      _values.add(
        PropertyValuesCompanion.insert(
          id: id,
          definitionId: dateDefinitionId,
          value: date.label,
          createdAt: _kNow.subtract(const Duration(days: 600)),
          dateFromYear: Value(start.year),
          dateFromMonth: Value(start.month),
          dateFromDay: Value(start.day),
          dateToYear: Value(end.year),
          dateToMonth: Value(end.month),
          dateToDay: Value(end.day),
          datePrecision: Value(date.precision),
          dateIsCirca: Value(date.isCirca),
        ),
      );
    }
    await _values.flush();
    _dateValueIds = dateIds;
  }

  Future<void> _seedItems() async {
    final kinds = <SourceKind>[
      for (var i = 0; i < profile.notes; i++) SourceKind.manualNote,
      for (var i = 0; i < profile.articles; i++) SourceKind.webPage,
      for (var i = 0; i < profile.transcripts; i++) SourceKind.youtube,
      for (var i = 0; i < profile.documents; i++) SourceKind.document,
      for (var i = 0; i < profile.posts; i++) SourceKind.socialPost,
    ]..shuffle(random);

    final datedIndexes = <int>{};
    while (datedIndexes.length < min(profile.datedItems, kinds.length)) {
      datedIndexes.add(random.nextInt(kinds.length));
    }

    for (var index = 0; index < kinds.length; index++) {
      await _seedItem(index, kinds[index], dated: datedIndexes.contains(index));
      if ((index + 1) % _batchItems == 0) await _flushItemBlock();
      if ((index + 1) % 1000 == 0) _say('${index + 1} elementos');
    }
    await _flushItemBlock();
    await _assignments.flush();
  }

  Future<void> _seedItem(
    int index,
    SourceKind kind, {
    required bool dated,
  }) async {
    final id = _id('item', index);
    final renditionId = _id('rend', index);
    final createdAt = _kNow.subtract(
      Duration(minutes: 1 + index * 97 % 1500000),
    );
    final updatedAt = createdAt.add(Duration(minutes: random.nextInt(60000)));
    final spaceId = random.nextInt(10) < 7
        ? _spaceIds[random.nextInt(_spaceIds.length)]
        : null;

    final isNote = kind == SourceKind.manualNote;
    final String title;
    final String content;
    final RenditionKind renditionKind;
    var linkedTitles = const <String>[];

    if (isNote) {
      title = 'Nota ${text.title(3)} $index';
      renditionKind = RenditionKind.blocks;
      final blocks = _noteBlocks(index, createdAt);
      linkedTitles = blocks.linkedTitles;
      content = encodeContentBlocks(blocks.blocks);
      _noteIndexes.add(index);
      if (linkedTitles.isNotEmpty) _linkedNotes.add(id);
    } else {
      title = 'Fuente ${text.title(4)} $index';
      renditionKind = RenditionKind.markdown;
      content = switch (kind) {
        SourceKind.webPage => text.article(_around(VaultProfile.articleChunks)),
        SourceKind.youtube => text.transcript(
          _around(VaultProfile.transcriptChunks),
        ),
        SourceKind.document => text.document(
          _around(VaultProfile.documentChunks),
        ),
        _ => text.article(VaultProfile.postChunks),
      };
    }
    _itemIds.add(id);
    _itemTitles.add(title);

    final processing = random.nextInt(100) < 96
        ? ProcessingState.ready
        : ProcessingState.values[random.nextInt(4)];
    _renditions.add(
      RenditionsCompanion.insert(
        id: renditionId,
        itemId: id,
        kind: renditionKind,
        isPrimary: true,
        createdAt: createdAt,
        content: Value(content),
      ),
    );

    // El elemento, tal como lo deja `save()`.
    _entries.add(
      KnowledgeEntriesCompanion.insert(
        id: id,
        title: title,
        subtitle: index % 5 == 0 ? Value(text.title(5)) : const Value.absent(),
        kind: itemKindFor(kind),
        state: _stateFor(processing),
        createdAt: createdAt,
        updatedAt: updatedAt,
        deviceId: kMirrorDeviceIdPlaceholder,
        spaceId: Value(spaceId),
      ),
    );
    if (isNote) {
      _knowledgeNotes.add(
        KnowledgeNotesCompanion.insert(
          itemId: id,
          noteKind: NoteKind.values[random.nextInt(3)],
          maturity: NoteMaturity.values[random.nextInt(3)],
        ),
      );
    } else {
      final chunks = const ChunkingService().chunk(
        content,
        kind: renditionKind,
      );
      _knowledgeSources.add(
        KnowledgeSourcesCompanion.insert(
          itemId: id,
          sourceType: kind,
          capturedAt: createdAt,
          contentHash: sha256.convert(utf8.encode(content)).toString(),
          processingStatus: sourceProcessingStatusFor(processing),
          originUrl: Value('https://ejemplo.org/$index'),
          authorName: Value('Autor ${index % 400}'),
          publishedAt: Value(
            createdAt.subtract(Duration(days: random.nextInt(2000))),
          ),
        ),
      );
      for (final chunk in chunks) {
        _chunks.add(
          ChunksCompanion.insert(
            id: _id('chun', _chunks.written + _chunks._rows.length),
            itemId: id,
            seq: chunk.seq,
            content: chunk.text,
            charStart: chunk.charStart,
            charEnd: chunk.charEnd,
            startMs: Value(chunk.startMs),
            endMs: Value(chunk.endMs),
            pageNumber: Value(chunk.pageNumber),
            headingPath: Value(chunk.headingPath),
          ),
        );
      }
      if (chunks.length > _largestSourceChunks) {
        _largestSourceChunks = chunks.length;
        _largestSourceId = id;
      }
      _seedHighlights(index, renditionId, content, createdAt);
    }

    _seedProperties(id, dated: dated);
    if (random.nextInt(1000) < profile.flashcards * 1000 ~/ profile.items) {
      _flashcards.add(
        FlashcardsCompanion.insert(
          id: _id('flas', index),
          itemId: id,
          front: '¿${text.title(4)}?',
          back: text.sentence(),
          dueAt: _kNow.add(Duration(days: random.nextInt(30) - 5)),
          createdAt: createdAt,
        ),
      );
    }
  }

  int _around(int average) =>
      max(1, (average * (0.5 + random.nextDouble())).round());

  ItemState _stateFor(ProcessingState processing) {
    if (processing != ProcessingState.ready) return ItemState.captured;
    final roll = random.nextInt(100);
    if (roll < 8) return ItemState.captured;
    if (roll < 48) return ItemState.processed;
    if (roll < 78) return ItemState.triaged;
    if (roll < 90) return ItemState.distilled;
    return ItemState.discarded;
  }

  ({List<ContentBlock> blocks, List<String> linkedTitles}) _noteBlocks(
    int index,
    DateTime createdAt,
  ) {
    final count = 3 + random.nextInt(10);
    final recent = random.nextInt(100) < 12;
    final linked = <String>[];
    final blocks = <ContentBlock>[];
    for (var i = 0; i < count; i++) {
      final addedAt = recent
          ? _kNow.subtract(Duration(days: random.nextInt(6)))
          : createdAt;
      var body = text.paragraph();
      if (random.nextInt(4) == 0 && _itemTitles.isNotEmpty) {
        final target = _itemTitles[random.nextInt(_itemTitles.length)];
        body = '$body Ver [[$target]].';
        linked.add(target);
      }
      blocks.add(
        i == 0
            ? ContentBlock.heading(text: text.title(4), addedAt: addedAt)
            : ContentBlock.paragraph(text: body, addedAt: addedAt),
      );
    }
    return (blocks: blocks, linkedTitles: linked);
  }

  void _seedHighlights(
    int index,
    String renditionId,
    String content,
    DateTime createdAt,
  ) {
    final per = profile.highlights / profile.items;
    var count = per.floor();
    if (random.nextDouble() < per - count) count++;
    if (content.length < 80) return;
    for (var i = 0; i < count; i++) {
      final start = random.nextInt(content.length - 60);
      final end = start + 20 + random.nextInt(40);
      _highlights.add(
        HighlightsCompanion.insert(
          id: _id('high', index * 8 + i),
          renditionId: renditionId,
          startOffset: start,
          endOffset: end,
          excerpt: content.substring(start, end),
          createdAt: createdAt,
        ),
      );
    }
  }

  void _seedProperties(String itemId, {required bool dated}) {
    final chosen = <String>{};
    final count = 2 + random.nextInt(4);
    for (var i = 0; i < count; i++) {
      chosen.add(_valueIds[_valueZipf.next()]);
    }
    if (dated) {
      chosen.add(_dateValueIds[random.nextInt(_dateValueIds.length)]);
    }
    for (final valueId in chosen) {
      _assignments.add(
        ItemPropertyValuesCompanion.insert(
          itemId: itemId,
          propertyValueId: valueId,
          origin: Value(ItemPropertyOrigin.values[random.nextInt(3)]),
        ),
      );
    }
  }

  Future<void> _seedRelations() async {
    final n = _itemIds.length;
    if (n < 2) return;
    final hubs = _Zipf(n, random);
    final seen = <String>{};
    const kinds = [
      RelationKind.relatedTo,
      RelationKind.relatedTo,
      RelationKind.relatedTo,
      RelationKind.relatedTo,
      RelationKind.cites,
      RelationKind.cites,
      RelationKind.continues,
      RelationKind.summarizes,
      RelationKind.extractedFrom,
      RelationKind.contradicts,
    ];
    var attempts = 0;
    while (seen.length < profile.relations &&
        attempts < profile.relations * 4) {
      attempts++;
      final from = random.nextInt(n);
      final to = hubs.next();
      if (from == to) continue;
      final kind = kinds[random.nextInt(kinds.length)];
      if (!seen.add('$from|$to|${kind.name}')) continue;
      _relationDegree.update(_itemIds[from], (d) => d + 1, ifAbsent: () => 1);
      _relationDegree.update(_itemIds[to], (d) => d + 1, ifAbsent: () => 1);
      _relations.add(
        RelationsCompanion.insert(
          id: _id('rela', seen.length),
          fromItemId: _itemIds[from],
          toItemId: _itemIds[to],
          kind: kind,
          createdAt: _kNow.subtract(Duration(days: random.nextInt(500))),
          reviewedAt: kind == RelationKind.contradicts && random.nextBool()
              ? Value(_kNow.subtract(const Duration(days: 3)))
              : const Value.absent(),
        ),
      );
      if (seen.length % 4000 == 0) await _relations.flush();
    }
    await _relations.flush();
  }

  Future<void> _seedInlineLinks() async {
    var n = 0;
    for (final index in _noteIndexes) {
      if (n >= profile.inlineLinks) break;
      final links = 1 + random.nextInt(2);
      final used = <String>{};
      for (var i = 0; i < links; i++) {
        final broken = random.nextInt(100) < 5;
        final target = random.nextInt(_itemIds.length);
        final title = broken ? 'Nota que falta $n' : _itemTitles[target];
        if (!broken && _itemIds[target] == _itemIds[index]) continue;
        final normalized = title.trim().toLowerCase();
        if (!used.add(normalized)) continue;
        _inlineLinks.add(
          InlineLinksCompanion.insert(
            id: _id('link', n++),
            fromItemId: _itemIds[index],
            targetTitle: title,
            normalizedTitle: normalized,
            createdAt: _kNow.subtract(Duration(days: random.nextInt(300))),
            toItemId: broken ? const Value(null) : Value(_itemIds[target]),
          ),
        );
      }
      if (n % 4000 == 0) await _inlineLinks.flush();
    }
    await _inlineLinks.flush();
  }
}

/// Cuántas filas tiene cada tabla que la bóveda sintética llena.
Future<Map<String, int>> countVaultRows(AppDatabase db) async {
  const tables = [
    'renditions',
    'item',
    'source',
    'note',
    'chunks',
    'relations',
    'item_property_values',
    'property_values',
    'highlights',
    'flashcards',
    'inline_link',
  ];
  final counts = <String, int>{};
  for (final table in tables) {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    counts[table] = row.read<int>('n');
  }
  return counts;
}

/// Los archivos con los que la bóveda sintética de [profile] queda en
/// [directory]: la base, su resumen y la marca de que está completa.
({File file, File summary, File ready}) _benchmarkVaultFiles(
  VaultProfile profile,
  Directory? directory,
) {
  final dir = (directory ?? Directory('.dart_tool/sinapsis_benchmark'))
    ..createSync(recursive: true);
  final name =
      'vault_s${AppDatabase.currentSchemaVersion}_g$kSyntheticVaultVersion'
      '_${profile.items}';
  return (
    file: File('${dir.path}/$name.sqlite'),
    summary: File('${dir.path}/$name.json'),
    ready: File('${dir.path}/$name.ok'),
  );
}

/// El archivo de la base de la bóveda sintética de [profile]. Existe una
/// vez que [openBenchmarkVault] la armó; se copia —no se abre en su lugar—
/// cuando una medición la tiene que modificar.
File benchmarkVaultFile({
  VaultProfile profile = const VaultProfile(),
  Directory? directory,
}) => _benchmarkVaultFiles(profile, directory).file;

/// Abre —o arma, la primera vez— la bóveda sintética en disco.
///
/// Armar la de 10.000 elementos tarda; por eso se guarda en `.dart_tool` y las
/// corridas siguientes la reutilizan. Cambia sola cuando cambia el esquema o
/// el generador: el nombre del archivo lleva las dos versiones.
Future<({AppDatabase db, SyntheticVault vault})> openBenchmarkVault({
  VaultProfile profile = const VaultProfile(),

  /// Dónde guardarla. Por defecto `.dart_tool` del proyecto; en un teléfono no
  /// existe ese directorio y hay que pasar uno de los del sistema.
  Directory? directory,
}) async {
  final files = _benchmarkVaultFiles(profile, directory);
  final (file, summary, ready) = (files.file, files.summary, files.ready);

  QueryExecutor open() => NativeDatabase(
    file,
    setup: (raw) {
      raw
        ..execute('PRAGMA journal_mode = WAL')
        ..execute('PRAGMA synchronous = NORMAL');
    },
  );

  if (ready.existsSync()) {
    final vault = SyntheticVault.fromJson(
      jsonDecode(summary.readAsStringSync()) as Map<String, Object?>,
    );
    return (db: AppDatabase(open()), vault: vault);
  }

  for (final leftover in [file, summary, ready]) {
    if (leftover.existsSync()) leftover.deleteSync();
  }
  final db = AppDatabase(open());
  final vault = await buildSyntheticVault(
    db,
    profile: profile,
    onProgress: stdout.writeln,
  );
  summary.writeAsStringSync(jsonEncode(vault.toJson()));
  ready.writeAsStringSync('ok');
  return (db: db, vault: vault);
}
