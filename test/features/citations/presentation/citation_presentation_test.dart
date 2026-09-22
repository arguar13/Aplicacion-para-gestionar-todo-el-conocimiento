import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/citations/domain/entities/citation.dart';
import 'package:sinapsis/features/citations/domain/entities/citation_source.dart';
import 'package:sinapsis/features/citations/domain/services/reference_styles.dart';
import 'package:sinapsis/features/citations/presentation/citation_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se nombran los estilos, las formas y los datos que faltan (F15), y cómo
/// se lee la página o el minuto que alguien escribió.
void main() {
  final es = AppLocalizationsEs();
  final en = AppLocalizationsEn();

  group('la página o el minuto', () {
    test('un número o un rango es una página', () {
      expect(parseLocator('12'), const CitationLocator.page('12'));
      expect(parseLocator('12-14'), const CitationLocator.page('12-14'));
      expect(parseLocator('S12-S15'), const CitationLocator.page('S12-S15'));
    });

    test('con dos puntos es un instante', () {
      expect(parseLocator('0:14:35'), const CitationLocator.time('0:14:35'));
      expect(parseLocator('14:35'), const CitationLocator.time('14:35'));
    });

    test('los espacios de los bordes no cuentan', () {
      expect(parseLocator('  12  '), const CitationLocator.page('12'));
    });

    test('vacío no cita ningún pasaje', () {
      expect(parseLocator(''), isNull);
      expect(parseLocator('   '), isNull);
    });
  });

  group('los nombres', () {
    test('APA, MLA e IEEE se llaman como son', () {
      for (final id in ['apa7', 'mla9', 'ieee']) {
        final style = kReferenceStyles.byId(id)!;

        expect(style.label(es), style.name);
        expect(style.label(en), style.name);
      }
    });

    test('los dos Chicago llevan su explicación en el idioma de la app', () {
      final notes = kReferenceStyles.byId('chicago17nb')!;
      final authorDate = kReferenceStyles.byId('chicago17ad')!;

      expect(notes.label(es), 'Chicago 17 · notas y bibliografía');
      expect(notes.label(en), 'Chicago 17 · notes and bibliography');
      expect(authorDate.label(es), 'Chicago 17 · autor-fecha');
      expect(authorDate.label(en), 'Chicago 17 · author-date');
    });

    test('cada forma y cada idioma tienen su nombre', () {
      for (final form in CitationForm.values) {
        expect(form.label(es), isNotEmpty);
        expect(form.label(en), isNotEmpty);
      }
      expect(CitationLanguage.es.label(es), 'Español');
      expect(CitationLanguage.en.label(es), 'English');
    });

    test('cada dato que puede faltar tiene su nombre', () {
      for (final gap in CitationGap.values) {
        expect(gap.label(es), isNotEmpty, reason: '$gap');
        expect(gap.label(en), isNotEmpty, reason: '$gap');
      }
      expect(CitationGap.author.label(es), 'Autor');
      expect(CitationGap.year.label(es), 'Año');
      expect(CitationGap.link.label(en), 'Link');
    });

    test('solo la entrada de la lista cita la obra entera', () {
      expect(CitationForm.reference.takesLocator, isFalse);
      expect(CitationForm.inText.takesLocator, isTrue);
      expect(CitationForm.note.takesLocator, isTrue);
      expect(CitationForm.shortNote.takesLocator, isTrue);
    });
  });

  group('la cita en pantalla', () {
    final theme = ThemeData();

    test('lleva el mismo texto que la cita', () {
      final citation = Citation(const [
        PlainRun('Autor. '),
        ItalicRun('Título'),
        PlainRun('. '),
        GapRun(field: CitationGap.year, text: '[falta: año]'),
      ]);

      expect(
        citationTextSpan(citation, theme).toPlainText(),
        citation.toPlainText(),
      );
    });

    test('la cursiva en cursiva y lo que falta con fondo', () {
      final citation = Citation(const [
        PlainRun('Autor. '),
        ItalicRun('Título'),
        GapRun(field: CitationGap.year, text: '[falta: año]'),
      ]);
      final spans = <TextSpan>[];
      citationTextSpan(citation, theme).visitChildren((child) {
        if (child is TextSpan) spans.add(child);
        return true;
      });

      expect(spans[0].style, isNull);
      expect(spans[1].style?.fontStyle, FontStyle.italic);
      expect(spans[2].style?.backgroundColor, theme.colorScheme.errorContainer);
      expect(spans[2].style?.fontStyle, isNot(FontStyle.italic));
    });
  });
}
