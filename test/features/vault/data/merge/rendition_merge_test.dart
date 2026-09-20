import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/entry_fields.dart';

import '../../../../support/test_vault.dart';

/// La fusión de las formas de texto (F11): qué pasa con el texto de un elemento
/// cuando las dos bóvedas lo tienen.
///
/// Lo que se protege: el texto de una FUENTE no se pisa nunca ni se pierde. Si
/// el de la copia es distinto, entra como otra forma del mismo elemento y queda
/// un conflicto que la señala. El texto de una NOTA es lo que el usuario
/// escribe y se fusiona como cualquier campo: lo que la copia editó partiendo
/// de lo de acá se toma; lo demás se guarda al lado.
void main() {
  late TestVault tel;
  late TestVault pc;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
  });

  tearDown(() async {
    await tel.dispose();
    await pc.dispose();
  });

  /// El texto de todas las formas de [itemId], ordenado.
  Future<List<String?>> textsOf(TestVault vault, String itemId) async =>
      [for (final r in await vault.renditionsOf(itemId)) r.content]
        ..sort((a, b) => (a ?? '').compareTo(b ?? ''));

  /// «a» nace en tel a las 12:01 y pc la recibe a las 12:02, con su texto.
  Future<void> shareSource({String text = 'Texto de la fuente.'}) async {
    tel.at(1);
    await tel.saveSource('a', text: text);
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  Future<void> shareNote({String text = 'Idea inicial.'}) async {
    tel.at(1);
    await tel.saveNote('n', text: text);
    pc.at(2);
    await pc.mergeFrom(tel);
  }

  group('las formas de un elemento nuevo', () {
    test('llegan enteras, con el texto exacto', () async {
      const text = 'Línea uno.\n\n  Con espacios y ñ, tildes: áéí — «citas».\n';
      pc.at(3);
      await pc.saveSource('a', text: text);

      final result = await tel.mergeFrom(pc);

      expect(result.itemsAdded, 1);
      expect(result.renditionsAdded, 1);
      final forms = await tel.renditionsOf('a');
      expect(forms, hasLength(1));
      expect(forms.single.id, 'rend-a');
      expect(forms.single.content, text);
      expect(forms.single.isPrimary, isTrue);
      expect(forms.single.kind, (await pc.renditionsOf('a')).single.kind);
    });

    test('llegan con las versiones de su texto', () async {
      pc.at(3);
      await pc.saveSource('a');

      await tel.mergeFrom(pc);

      final version = await tel.version('a', EntryField.rendition('rend-a'));
      expect(version, isNotNull);
      expect(version!.deviceId, 'pc');
    });

    test('un archivo como forma llega con su ruta', () async {
      pc.at(3);
      await pc.saveSource('a', originalName: 'doc.pdf');
      await pc.db.customStatement('''
        INSERT INTO renditions (id, item_id, kind, relative_path, is_primary,
                                created_at)
        VALUES ('rend-file', 'a', 'pdf', 'originales/a/doc.pdf', 0, 1)''');

      await tel.mergeFrom(pc);

      final file = (await tel.renditionsOf(
        'a',
      )).firstWhere((r) => r.id == 'rend-file');
      expect(file.relativePath, 'originales/a/doc.pdf');
      expect(file.content, isNull);
    });
  });

  group('una forma que falta en un elemento que las dos tienen', () {
    test('se agrega, y no es la principal', () async {
      await shareSource();
      pc.at(5);
      await pc.addRendition('a', 'rend-a-2', 'Una transcripción.');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.renditionsAdded, 1);
      expect(result.conflictsRecorded, 0);
      final forms = await tel.renditionsOf('a');
      expect(forms.map((r) => r.id), ['rend-a', 'rend-a-2']);
      expect(forms.last.content, 'Una transcripción.');
      expect(forms.last.isPrimary, isFalse);
      // La principal, intacta.
      expect(forms.first.content, 'Texto de la fuente.');
      expect(forms.first.isPrimary, isTrue);
    });

    test('nunca hay dos principales', () async {
      await shareSource();
      pc.at(5);
      await pc.addRendition('a', 'rend-a-2', 'Otra principal.', primary: true);

      tel.at(9);
      await tel.mergeFrom(pc);

      final primaries = (await tel.renditionsOf('a')).where((r) => r.isPrimary);
      expect(primaries.map((r) => r.id), ['rend-a']);
    });

    test('un elemento sin principal recibe la de la copia', () async {
      await shareSource();
      await tel.db.customStatement('UPDATE renditions SET is_primary = 0');
      pc.at(5);
      await pc.addRendition('a', 'rend-a-2', 'La que sirve.', primary: true);

      tel.at(9);
      await tel.mergeFrom(pc);

      final forms = await tel.renditionsOf('a');
      expect(forms.singleWhere((r) => r.isPrimary).id, 'rend-a-2');
    });

    test('con su versión, y no se agrega otra vez', () async {
      await shareSource();
      pc.at(5);
      await pc.addRendition('a', 'rend-a-2', 'Una transcripción.');
      tel.at(9);
      await tel.mergeFrom(pc);

      tel.at(12);
      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(await tel.renditionsOf('a'), hasLength(2));
    });

    test(
      'el mismo texto con otro identificador no se agrega dos veces',
      () async {
        await shareSource();
        // Cada bóveda procesó el mismo texto por su cuenta: mismo contenido y
        // otro id.
        tel.at(4);
        await tel.addRendition('a', 'r-tel', 'La transcripción.');
        pc.at(5);
        await pc.addRendition('a', 'r-pc', 'La transcripción.');

        tel.at(9);
        final result = await tel.mergeFrom(pc);

        expect(result.renditionsAdded, 0);
        expect(await tel.renditionsOf('a'), hasLength(2));
      },
    );
  });

  group('el texto de una fuente', () {
    test('distinto en la copia: NO se pisa, entra como otra forma con un '
        'conflicto', () async {
      await shareSource();
      final untouched = (await tel.renditionsOf('a')).single.content;
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto, editado en pc.');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.textsUpdated, 0);
      expect(result.renditionsAdded, 1);
      expect(result.conflictsRecorded, 1);
      final forms = await tel.renditionsOf('a');
      expect(forms, hasLength(2));
      // El de acá, byte a byte como estaba y principal.
      final live = forms.singleWhere((r) => r.id == 'rend-a');
      expect(live.content, untouched);
      expect(live.isPrimary, isTrue);
      // El de la copia, al lado.
      final extra = forms.singleWhere((r) => r.id != 'rend-a');
      expect(extra.content, 'Otro texto, editado en pc.');
      expect(extra.isPrimary, isFalse);

      final conflict = (await tel.conflicts()).single;
      expect(conflict.itemId, 'a');
      expect(conflict.fieldName, EntryField.rendition('rend-a'));
      expect(conflict.otherRenditionId, extra.id);
      expect(conflict.localDeviceId, 'tel');
      expect(conflict.incomingDeviceId, 'pc');
      expect(conflict.resolvedAt, isNull);
    });

    test('aunque la copia lo haya editado partiendo del de acá', () async {
      // En una nota sería una edición normal; en una fuente, el texto no se
      // reescribe: ni siquiera con el linaje a favor.
      await shareSource();
      pc.at(5);
      await pc.saveSource('a', text: 'Editado sobre lo de tel.');
      expect(
        (await pc.version('a', EntryField.rendition('rend-a')))!.baseDeviceId,
        'tel',
        reason: 'la premisa: la edición de pc parte de la de tel',
      );

      tel.at(9);
      await tel.mergeFrom(pc);

      expect(
        (await tel.renditionsOf(
          'a',
        )).singleWhere((r) => r.id == 'rend-a').content,
        'Texto de la fuente.',
      );
      expect(await tel.conflicts(), hasLength(1));
    });

    test('fusionar otra vez la misma copia no repite el conflicto ni la '
        'forma', () async {
      await shareSource();
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto.');
      tel.at(9);
      await tel.mergeFrom(pc);

      tel.at(12);
      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(await tel.renditionsOf('a'), hasLength(2));
      expect(await tel.conflicts(), hasLength(1));
    });

    test('un conflicto resuelto no vuelve, aunque se borre la forma', () async {
      await shareSource();
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto.');
      tel.at(9);
      await tel.mergeFrom(pc);
      final extra = (await tel.renditionsOf(
        'a',
      )).firstWhere((r) => r.id != 'rend-a');
      await tel.db.customStatement(
        "UPDATE merge_conflict SET resolved_at = 1, resolution = 'keepLocal'",
      );
      await tel.db.customStatement(
        "DELETE FROM renditions WHERE id = '${extra.id}'",
      );

      tel.at(12);
      final again = await tel.mergeFrom(pc);

      expect(again.changedNothing, isTrue);
      expect(await tel.renditionsOf('a'), hasLength(1));
    });

    test('los resaltados de la copia van a SU texto, no al de acá', () async {
      await shareSource();
      tel.at(4);
      await tel.addHighlight('hl-tel', 'a');
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto muy distinto.');
      await pc.addHighlight('hl-pc', 'a', start: 5, end: 10);

      tel.at(9);
      await tel.mergeFrom(pc);

      final extra = (await tel.renditionsOf(
        'a',
      )).firstWhere((r) => r.id != 'rend-a');
      final highlights = {
        for (final h in await tel.db.select(tel.db.highlights).get())
          h.id: h.renditionId,
      };
      // El de acá, donde estaba; el de la copia, sobre el texto de la copia.
      expect(highlights['hl-tel'], 'rend-a');
      expect(highlights['hl-pc'], extra.id);
    });

    test('si el conflicto ya se guardó, sus resaltados no caen en el texto '
        'de acá', () async {
      await shareSource();
      pc.at(5);
      await pc.saveSource('a', text: 'Otro texto muy distinto.');
      tel.at(9);
      await tel.mergeFrom(pc);
      // Después la copia suma un resaltado sobre ese mismo texto.
      await pc.addHighlight('hl-nuevo', 'a', start: 5, end: 10);

      tel.at(12);
      await tel.mergeFrom(pc);

      final highlights = {
        for (final h in await tel.db.select(tel.db.highlights).get())
          h.id: h.renditionId,
      };
      final extra = (await tel.renditionsOf(
        'a',
      )).firstWhere((r) => r.id != 'rend-a');
      // Se acomoda en la forma que tiene ese texto, no en la de acá.
      expect(highlights['hl-nuevo'], extra.id);
    });
  });

  group('el texto de una nota', () {
    test('editado en la copia partiendo del de acá: se toma', () async {
      await shareNote();
      final before = await tel.entry('n');
      pc.at(5);
      await pc.saveNote('n', text: 'Idea desarrollada en pc.');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.textsUpdated, 1);
      expect(result.conflictsRecorded, 0);
      expect(result.renditionsAdded, 0);
      final forms = await tel.renditionsOf('n');
      expect(forms.single.content, 'Idea desarrollada en pc.');
      // Es un cambio del elemento: sube el `rev`.
      expect((await tel.entry('n')).rev, before.rev + 1);
      final version = await tel.version('n', EntryField.rendition('rend-n'));
      expect(version!.deviceId, 'pc');
      expect(version.baseDeviceId, 'tel');
    });

    test('editada acá sobre la de la copia: se queda la de acá', () async {
      await shareNote();
      pc.at(5);
      await pc.saveNote('n', text: 'Editada en pc.');
      tel.at(7);
      await tel.mergeFrom(pc);
      tel.at(9);
      await tel.saveNote('n', text: 'Editada en tel sobre la de pc.');

      pc.at(12);
      final result = await pc.mergeFrom(tel);

      // La de tel partió de la de pc: pc la recibe, sin conflicto.
      expect(result.conflictsRecorded, 0);
      expect(
        (await pc.renditionsOf('n')).single.content,
        'Editada en tel sobre la de pc.',
      );
    });

    test('editada en las dos a la vez: el de acá queda y el de la copia entra '
        'al lado', () async {
      await shareNote();
      tel.at(5);
      await tel.saveNote('n', text: 'De tel.');
      pc.at(7);
      await pc.saveNote('n', text: 'De pc.');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.textsUpdated, 0);
      expect(result.conflictsRecorded, 1);
      final forms = await tel.renditionsOf('n');
      expect(forms.singleWhere((r) => r.id == 'rend-n').content, 'De tel.');
      expect(forms.singleWhere((r) => r.id != 'rend-n').content, 'De pc.');
      expect(
        (await tel.conflicts()).single.fieldName,
        EntryField.rendition('rend-n'),
      );
    });

    test(
      'y en el otro sentido cada bóveda termina con los DOS textos',
      () async {
        await shareNote();
        tel.at(5);
        await tel.saveNote('n', text: 'De tel.');
        pc.at(7);
        await pc.saveNote('n', text: 'De pc.');

        tel.at(9);
        await tel.mergeFrom(pc);
        pc.at(9);
        await pc.mergeFrom(tel);

        expect(await textsOf(tel, 'n'), ['De pc.', 'De tel.']);
        expect(await textsOf(pc, 'n'), ['De pc.', 'De tel.']);
      },
    );

    test('una nota que la copia no editó no cambia', () async {
      await shareNote();
      tel.at(5);
      await tel.saveNote('n', text: 'Solo editada en tel.');

      tel.at(9);
      final result = await tel.mergeFrom(pc);

      expect(result.changedNothing, isTrue);
      expect(
        (await tel.renditionsOf('n')).single.content,
        'Solo editada en tel.',
      );
    });
  });
}
