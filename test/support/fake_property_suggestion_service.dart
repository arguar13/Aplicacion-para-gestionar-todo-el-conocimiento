// El doble lanza lo que el test le dé, y el tipo tiene que ser `Object`
// porque `Exception` y `Error` no comparten más supertipo que ese.
// ignore_for_file: only_throw_errors

import 'package:sinapsis/features/suggestions/domain/services/property_suggestion_service.dart';

/// Un servicio de sugerencias de propiedades de mentira, para las pruebas
/// que no están probando `flutter_gemma` en sí.
class FakePropertySuggestionService implements PropertySuggestionService {
  FakePropertySuggestionService({this.drafts = const [], this.error});

  /// Lo que "sugiere" [suggestProperties]. Mutable a propósito.
  List<PropertyDraft> drafts;

  /// Si está, se lanza en vez de sugerir.
  Object? error;

  /// Cada pedido que se hizo, en orden — el título del elemento y cuántas
  /// categorías se le mandaron —, para comprobar en las pruebas qué se le
  /// pidió al modelo.
  final requests = <({String itemTitle, int categoryCount})>[];

  @override
  Future<List<PropertyDraft>> suggestProperties({
    required String itemTitle,
    required String itemContent,
    required List<PropertyVocabularyCategory> categories,
  }) async {
    requests.add((itemTitle: itemTitle, categoryCount: categories.length));
    final err = error;
    if (err != null) throw err;
    return drafts;
  }
}
