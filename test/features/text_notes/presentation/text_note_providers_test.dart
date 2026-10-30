import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/text_notes/domain/entities/text_note_target.dart';
import 'package:sinapsis/features/text_notes/presentation/providers/text_note_providers.dart';

import '../text_notes_harness.dart';

/// Lo que la interfaz de las notas en el texto (F45, mejora 19) usa: la cuenta
/// de «Notas (N)», la lista y las notas ubicadas en el texto que se muestra,
/// al día con cada acción.
void main() {
  late TextNotesHarness h;
  late ProviderContainer container;

  const text = 'Moisés sube al monte. Baja con las tablas de la ley.';

  setUp(() async {
    h = await TextNotesHarness.create();
    container = ProviderContainer(
      overrides: [textNoteRepositoryProvider.overrideWithValue(h.notes)],
    );
  });
  tearDown(() async {
    container.dispose();
    await h.close();
  });

  test('«Notas (N)» y la lista siguen a cada acción, con «Deshacer»', () async {
    final library = await h.source('fuente', text: text);
    final count = container.listen(textNoteCountProvider(library), (_, _) {});
    final list = container.listen(textNotesProvider(library), (_, _) {});
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    await settle();
    expect(count.read().value, 0);

    final note = await h.noteOn(library, text, 'monte', note: 'Sinaí');
    await h.highlightWithNote('r1', 'fuente', text, 'ley', note: 'Torá');
    await settle();
    expect(count.read().value, 2);
    expect([for (final n in list.read().value!) n.note], ['Sinaí', 'Torá']);

    final removed = (await h.notes.delete(note)).getRight().toNullable()!;
    await settle();
    expect(count.read().value, 1);

    await h.notes.restore(removed);
    await settle();
    expect(count.read().value, 2);
  });

  test('las notas ubicadas en el texto que se muestra: en su lugar, y la que '
      'ya no está, sin lugar y al final', () async {
    final library = await h.source('fuente', text: text);
    await h.noteOn(library, text, 'tablas', note: 'Las dos');
    await h.noteOn(library, text, 'Moisés', note: 'El que sube');
    const changed = 'Moisés sube al monte. Baja con la ley.';
    final key = (
      target: library as TextNoteTarget,
      textKey: 'rend-fuente',
      content: changed,
    );
    final placed = container.listen(placedTextNotesProvider(key), (_, _) {});

    await Future<void>.delayed(Duration.zero);
    final notes = placed.read().value!;
    expect(
      [for (final p in notes) (p.note.note, p.placed)],
      [('El que sube', true), ('Las dos', false)],
    );
    expect(changed.substring(notes.first.start!, notes.first.end), 'Moisés');
  });
}
