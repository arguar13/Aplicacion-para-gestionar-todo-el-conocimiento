import 'package:sinapsis/core/domain/entities/property_definition.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si [name] es el de la categoría de sistema de las etiquetas: en la base se
/// sigue llamando «Tema» (`kTemaCategoryName`). Alcanza con el nombre: es
/// único sin distinguir mayúsculas, así que ninguna otra categoría puede
/// llamarse igual.
bool isTagsCategoryName(String name) =>
    name.toLowerCase() == kTemaCategoryName.toLowerCase();

/// Cómo se llama una categoría en la interfaz (F28): la de las etiquetas,
/// «Etiquetas» —como en el detalle, el Mapa y el Atlas—; las demás, por su
/// nombre. «Tema» quedó para lo que se elige al guardar.
///
/// El nombre de la base no cambia: lo usan las búsquedas por nombre, la IA y
/// las copias de seguridad, y renombrar una categoría de sistema rompería las
/// bóvedas que ya existen.
String categoryLabel(AppLocalizations l10n, String name) =>
    isTagsCategoryName(name) ? l10n.topicDimensionTags : name;

/// Cómo se nombra una categoría delante de uno de sus valores —«Etiqueta:
/// Roma», «Época: Siglo I»—: en singular, como se lee un par.
String categoryValueLabel(AppLocalizations l10n, String name) =>
    isTagsCategoryName(name) ? l10n.categoryTagSingular : name;
