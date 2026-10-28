import 'package:flutter/foundation.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_original.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_part.dart';
import 'package:sinapsis/features/processed/domain/entities/section_edit.dart';

/// Cómo se elige una sección en la hoja «¿Qué va a Procesado?» (F41).
enum TriageSectionShape {
  /// Entera, de la fuente: se prende o se apaga —el texto extraído, el
  /// resumen, la síntesis, las palabras clave—. Lo que trae lo decide la
  /// fuente, no la persona.
  whole,

  /// Una lista que arma la persona, de a un pasaje: las notas y los
  /// fragmentos cortados.
  clips,
}

/// La forma de [section] en la hoja. Es el único lugar que lo decide: una
/// sección nueva entra con su caso y la hoja ya sabe mostrarla.
TriageSectionShape triageShapeOf(ProcessedSection section) => switch (section) {
  ProcessedSection.text ||
  ProcessedSection.summary ||
  ProcessedSection.synthesis ||
  ProcessedSection.keywords => TriageSectionShape.whole,
  ProcessedSection.notes ||
  ProcessedSection.fragments => TriageSectionShape.clips,
};

/// Un pasaje de la lista de una sección —una nota o un fragmento—: lo que se
/// va a guardar ([draft]) y lo que se muestra mientras tanto ([excerpt]).
@immutable
class TriageClip {
  const TriageClip({
    required this.id,
    required this.draft,
    required this.excerpt,
  });

  /// Solo de la hoja, para quitarlo y para su lugar en la lista; no se guarda.
  final String id;
  final ProcessedDraft draft;

  /// El texto que se ve en la lista: el pasaje cortado, o la nota escrita.
  final String excerpt;

  /// Dónde está en el original, si salió de él.
  ProcessedAnchor? get anchor => switch (draft) {
    ProcessedCut(:final anchor) => anchor,
    ProcessedWritten(:final anchor) => anchor,
  };

  @override
  bool operator ==(Object other) =>
      other is TriageClip &&
      other.id == id &&
      other.draft == draft &&
      other.excerpt == excerpt;

  @override
  int get hashCode => Object.hash(id, draft, excerpt);
}

/// Lo que se le pide a una sección en la hoja: un cambio y, si es una lista,
/// sus pasajes.
@immutable
class TriageChoice {
  const TriageChoice(this.change, {this.clips = const []});

  final ProcessedChange change;

  /// Los pasajes de una sección de lista (ver [TriageSectionShape.clips]).
  final List<TriageClip> clips;

  @override
  bool operator ==(Object other) =>
      other is TriageChoice &&
      other.change == change &&
      listEquals(other.clips, clips);

  @override
  int get hashCode => Object.hash(change, Object.hashAll(clips));
}

/// Lo que la persona va eligiendo en la hoja «¿Qué va a Procesado?» (F41),
/// antes de guardar nada: qué secciones van y con qué cambio, y los pasajes de
/// las notas y los fragmentos.
///
/// **El contrato con «Volver a triar» (paso 4).** La hoja nace de lo que el
/// documento ya tiene ([existing], cuántas partes por sección) y de un
/// `Map<ProcessedSection, SectionEdit>` inicial ([ProcessedTriage.from]), y
/// devuelve otro, [edits], que es lo que recibe `ProcessSourceUseCase`. Por
/// sección se elige un [ProcessedChange]; triar algo nuevo (paso 3) usa solo
/// [ProcessedChange.add] sobre un documento que no existe, pero el resto del
/// camino —actualizar, reemplazar, quitar— ya pasa por acá.
///
/// Es inmutable: cada cambio devuelve otra, y la hoja la guarda en un
/// `StateNotifier`.
@immutable
class ProcessedTriage {
  const ProcessedTriage({
    required this.sourceItemId,
    this.existing = const {},
    this.choices = const {},
    this.nextClip = 0,
    this.originalExists = false,
    this.original,
  });

  /// La hoja a partir de un pedido ya armado: lo que trae «Volver a triar»
  /// sobre un documento que existe. De cada pasaje cortado se sabe su ancla
  /// pero no su texto: [excerptOf] lo da si se tiene; si no, se ve vacío
  /// hasta que quien muestra la hoja lo lee de la fuente
  /// ([withExcerpts]).
  factory ProcessedTriage.from(
    String sourceItemId, {
    Map<ProcessedSection, int> existing = const {},
    Map<ProcessedSection, SectionEdit> edits = const {},
    String Function(ProcessedAnchor anchor)? excerptOf,
    bool originalExists = false,
    OriginalEdit? original,
  }) {
    var next = 0;
    final choices = <ProcessedSection, TriageChoice>{};
    for (final MapEntry(key: section, value: edit) in edits.entries) {
      final drafts = switch (edit.input) {
        FromDrafts(:final drafts) => drafts,
        _ => const <ProcessedDraft>[],
      };
      choices[section] = TriageChoice(
        edit.change,
        clips: [
          for (final draft in drafts)
            TriageClip(
              id: 'clip-${next++}',
              draft: draft,
              excerpt: switch (draft) {
                ProcessedWritten(:final content) => content,
                ProcessedCut(:final anchor) => excerptOf?.call(anchor) ?? '',
              },
            ),
        ],
      );
    }
    return ProcessedTriage(
      sourceItemId: sourceItemId,
      existing: existing,
      choices: choices,
      nextClip: next,
      originalExists: originalExists,
      original: original?.change,
    );
  }

  final String sourceItemId;

  /// Cuántas partes tiene ya cada sección del documento procesado; vacío si
  /// todavía no existe.
  final Map<ProcessedSection, int> existing;

  /// Lo pedido por sección. Una sección que no está queda como está.
  final Map<ProcessedSection, TriageChoice> choices;

  /// El número del próximo pasaje, para su [TriageClip.id].
  final int nextClip;

  /// Si el documento ya tiene la copia del original (decisión H): con ella se
  /// ofrece actualizarla, reemplazarla o quitarla.
  final bool originalExists;

  /// Lo pedido para la copia del original, o `null` si no se toca: va aparte
  /// de las secciones porque no es una lista de partes sino un archivo.
  final ProcessedChange? original;

  /// Lo que recibe `ProcessSourceUseCase` para la copia del original.
  OriginalEdit? get originalEdit {
    final change = original;
    return change == null ? null : OriginalEdit(change);
  }

  /// Si el documento ya existe: con él se ofrece más que agregar.
  bool get documentExists => existing.values.any((count) => count > 0);

  /// Si [section] va: prendida, si es entera; con algún pasaje —o pedida
  /// quitar—, si es una lista.
  bool includes(ProcessedSection section) => choices.containsKey(section);

  /// Los pasajes de [section], en el orden en que se eligieron.
  List<TriageClip> clipsOf(ProcessedSection section) =>
      choices[section]?.clips ?? const [];

  /// Las anclas de los fragmentos cortados del texto [renditionId]: lo que se
  /// marca en el original mientras se corta.
  List<ProcessedAnchor> cutsIn(String renditionId) => [
    for (final clip in clipsOf(ProcessedSection.fragments))
      if (clip.anchor case final anchor? when anchor.renditionId == renditionId)
        anchor,
  ];

  /// Lo que recibe `ProcessSourceUseCase`: una entrada por sección pedida.
  /// Una sección de lista sin pasajes no va —salvo que se pida quitarla—.
  Map<ProcessedSection, SectionEdit> get edits => {
    for (final MapEntry(key: section, value: choice) in choices.entries)
      if (_editOf(section, choice) case final edit?) section: edit,
  };

  /// Si no se pidió nada: ni una sección ni la copia del original.
  bool get isEmpty => edits.isEmpty && original == null;

  static SectionEdit? _editOf(ProcessedSection section, TriageChoice choice) {
    switch (triageShapeOf(section)) {
      case TriageSectionShape.whole:
        return switch (choice.change) {
          ProcessedChange.add => SectionEdit.add(
            const SectionInput.fromSource(),
          ),
          ProcessedChange.update => SectionEdit.update(),
          ProcessedChange.replace => SectionEdit.replace(
            const SectionInput.fromSource(),
          ),
          ProcessedChange.remove => SectionEdit.remove(),
        };
      case TriageSectionShape.clips:
        final drafts = [for (final clip in choice.clips) clip.draft];
        return switch (choice.change) {
          ProcessedChange.remove => SectionEdit.remove(),
          // Una lista no tiene una versión en la fuente que traer.
          ProcessedChange.update => null,
          _ when drafts.isEmpty => null,
          ProcessedChange.add => SectionEdit.add(SectionInput.drafts(drafts)),
          ProcessedChange.replace => SectionEdit.replace(
            SectionInput.drafts(drafts),
          ),
        };
    }
  }

  // --- Cambiar -------------------------------------------------------------

  /// Prende [section] con [change] —agregar, por defecto— o la apaga.
  ProcessedTriage withSection(
    ProcessedSection section, {
    required bool on,
    ProcessedChange change = ProcessedChange.add,
  }) {
    final choices = {...this.choices};
    if (on) {
      choices[section] = TriageChoice(change, clips: clipsOf(section));
    } else {
      choices.remove(section);
    }
    return _copy(choices: choices);
  }

  /// Prende la copia del original con [change] —agregar, por defecto— o la
  /// apaga: entonces no se toca.
  ProcessedTriage withOriginal({
    required bool on,
    ProcessedChange change = ProcessedChange.add,
  }) => ProcessedTriage(
    sourceItemId: sourceItemId,
    existing: existing,
    choices: choices,
    nextClip: nextClip,
    originalExists: originalExists,
    original: on ? change : null,
  );

  /// Cambia lo que se le pide a [section], conservando sus pasajes.
  ProcessedTriage withChange(
    ProcessedSection section,
    ProcessedChange change,
  ) => withSection(section, on: true, change: change);

  /// Suma un pasaje a [section]. Un corte que ya está —el mismo tramo del
  /// mismo texto— no entra dos veces: devuelve la misma hoja.
  ProcessedTriage withClip(
    ProcessedSection section,
    ProcessedDraft draft, {
    required String excerpt,
  }) {
    assert(
      triageShapeOf(section) == TriageSectionShape.clips,
      'Solo una lista lleva pasajes.',
    );
    final current = choices[section];
    final clips = current?.clips ?? const <TriageClip>[];
    if (draft is ProcessedCut &&
        clips.any(
          (clip) => clip.draft is ProcessedCut && clip.draft == draft,
        )) {
      return this;
    }
    final clip = TriageClip(
      id: 'clip-$nextClip',
      draft: draft,
      excerpt: excerpt,
    );
    return _copy(
      choices: {
        ...choices,
        section: TriageChoice(
          // Quitar una sección y sumarle algo es reemplazarla.
          current == null
              ? ProcessedChange.add
              : current.change == ProcessedChange.remove
              ? ProcessedChange.replace
              : current.change,
          clips: [...clips, clip],
        ),
      },
      nextClip: nextClip + 1,
    );
  }

  /// Saca el pasaje [clipId] de donde esté. Una lista que queda vacía deja de
  /// ir, salvo que se haya pedido quitarla entera.
  ProcessedTriage withoutClip(String clipId) {
    final choices = <ProcessedSection, TriageChoice>{};
    for (final MapEntry(key: section, value: choice) in this.choices.entries) {
      final clips = [
        for (final clip in choice.clips)
          if (clip.id != clipId) clip,
      ];
      final emptied = clips.isEmpty && choice.clips.isNotEmpty;
      if (emptied && triageShapeOf(section) == TriageSectionShape.clips) {
        continue;
      }
      choices[section] = TriageChoice(choice.change, clips: clips);
    }
    return _copy(choices: choices);
  }

  /// Con los textos de los pasajes que no se sabían, por su ancla.
  ProcessedTriage withExcerpts(Map<ProcessedAnchor, String> excerpts) => _copy(
    choices: {
      for (final MapEntry(key: section, value: choice) in choices.entries)
        section: TriageChoice(
          choice.change,
          clips: [
            for (final clip in choice.clips)
              if (clip.excerpt.isEmpty && excerpts[clip.anchor] != null)
                TriageClip(
                  id: clip.id,
                  draft: clip.draft,
                  excerpt: excerpts[clip.anchor]!,
                )
              else
                clip,
          ],
        ),
    },
  );

  ProcessedTriage _copy({
    Map<ProcessedSection, TriageChoice>? choices,
    int? nextClip,
  }) => ProcessedTriage(
    sourceItemId: sourceItemId,
    existing: existing,
    choices: choices ?? this.choices,
    nextClip: nextClip ?? this.nextClip,
    originalExists: originalExists,
    original: original,
  );

  @override
  bool operator ==(Object other) =>
      other is ProcessedTriage &&
      other.sourceItemId == sourceItemId &&
      mapEquals(other.existing, existing) &&
      mapEquals(other.choices, choices) &&
      other.nextClip == nextClip &&
      other.originalExists == originalExists &&
      other.original == original;

  @override
  int get hashCode => Object.hash(
    sourceItemId,
    Object.hashAllUnordered(existing.entries.map((e) => (e.key, e.value))),
    Object.hashAllUnordered(choices.entries.map((e) => (e.key, e.value))),
    nextClip,
    originalExists,
    original,
  );
}
