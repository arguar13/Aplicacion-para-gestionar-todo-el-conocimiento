import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/my_cards_route.dart';

void main() {
  test('las rutas son las pactadas', () {
    expect(kRouteCards, '/cards');
    expect(kRouteReviewStats, '/review/stats');
  });

  group('myCardsLocation', () {
    test('todo: la ruta sola', () {
      expect(myCardsLocation(), '/cards');
      expect(myCardsLocation(const StudyScope.item('x')), isNot('/cards'));
    });

    test('cada recorte, en su parámetro', () {
      expect(myCardsLocation(const StudyScope.item('a')), '/cards?item=a');
      expect(myCardsLocation(const StudyScope.space('s')), '/cards?space=s');
      expect(myCardsLocation(const StudyScope.value('v')), '/cards?value=v');
      expect(
        myCardsLocation(const StudyScope.notebook('n')),
        '/cards?notebook=n',
      );
    });

    test('un recorte de Procesado (F43), con su clave', () {
      expect(
        myCardsLocation(const StudyScope.processed('notebook:n')),
        '/cards?processed=notebook%3An',
      );
      expect(
        myCardsScopeFromQuery(const {'processed': 'notebook:n'}),
        const StudyScope.processed('notebook:n'),
      );
      // «Todo lo procesado» es todo, y una clave rara también.
      expect(
        myCardsScopeFromQuery(const {'processed': 'all'}),
        const StudyScope.all(),
      );
      expect(
        myCardsScopeFromQuery(const {'processed': 'raro'}),
        const StudyScope.all(),
      );
    });

    test('un identificador raro se escapa', () {
      expect(
        myCardsLocation(const StudyScope.item('a b&c=d')),
        '/cards?item=a+b%26c%3Dd',
      );
    });
  });

  group('myCardsScopeFromQuery', () {
    test('sin consulta, todo', () {
      expect(myCardsScopeFromQuery(const {}), const StudyScope.all());
      expect(
        myCardsScopeFromQuery(const {'otro': 'x'}),
        const StudyScope.all(),
      );
      expect(myCardsScopeFromQuery(const {'item': ''}), const StudyScope.all());
    });

    test('es lo inverso de myCardsLocation', () {
      for (final scope in const [
        StudyScope.item('a b&c=d'),
        StudyScope.space('s'),
        StudyScope.value('v'),
        StudyScope.notebook('n'),
        StudyScope.all(),
      ]) {
        final uri = Uri.parse(myCardsLocation(scope));
        expect(myCardsScopeFromQuery(uri.queryParameters), scope);
      }
    });
  });
}
