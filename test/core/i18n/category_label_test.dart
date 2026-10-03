import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/core/i18n/category_label.dart';
import 'package:sinapsis/l10n/generated/app_localizations_en.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se llama una categoría en la interfaz (F28): la de las etiquetas
/// —«Tema» en la base— se llama «Etiquetas», porque «Tema» quedó para lo que
/// se elige al guardar.
void main() {
  final es = AppLocalizationsEs();

  test('la de las etiquetas se llama «Etiquetas», con cualquier mayúscula', () {
    expect(categoryLabel(es, kTemaCategoryName), 'Etiquetas');
    expect(categoryLabel(es, 'tema'), 'Etiquetas');
    expect(categoryLabel(AppLocalizationsEn(), kTemaCategoryName), 'Tags');
  });

  test('delante de un valor, en singular', () {
    expect(categoryValueLabel(es, kTemaCategoryName), 'Etiqueta');
  });

  test('las demás, por su nombre', () {
    expect(categoryLabel(es, 'Época'), 'Época');
    expect(
      categoryValueLabel(es, kFechaDelHechoCategoryName),
      'Fecha del hecho',
    );
  });
}
