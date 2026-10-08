import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_limits.dart';

void main() {
  group('StudyLimits', () {
    test('de fábrica son 20 nuevas y 200 repasos', () {
      const limits = StudyLimits();

      expect(limits.newPerDay, 20);
      expect(limits.reviewsPerDay, 200);
    });

    test('lo que queda es el tope menos lo hecho, y nunca negativo', () {
      const limits = StudyLimits();

      expect(limits.newLeft(0), 20);
      expect(limits.newLeft(5), 15);
      expect(limits.newLeft(20), 0);
      expect(limits.newLeft(35), 0);
      expect(limits.reviewsLeft(199), 1);
      expect(limits.reviewsLeft(200), 0);
      expect(limits.reviewsLeft(999), 0);
    });

    test('un tope de 0 deja el día sin ese tipo de tarjeta', () {
      const limits = StudyLimits(newPerDay: 0);

      expect(limits.newLeft(0), 0);
    });

    test('ampliarlo por hoy no cambia el original', () {
      const limits = StudyLimits();

      final more = limits.extendedBy(newCards: 10, reviews: 50);

      expect(more.newPerDay, 30);
      expect(more.reviewsPerDay, 250);
      expect(limits.newPerDay, 20);
    });

    test('ampliarlo nunca pasa del máximo', () {
      final more = const StudyLimits(
        newPerDay: StudyLimits.maxPerDay,
      ).extendedBy(newCards: 10);

      expect(more.newPerDay, StudyLimits.maxPerDay);
    });

    test('se compara por valor', () {
      expect(const StudyLimits(), const StudyLimits());
      expect(const StudyLimits().hashCode, const StudyLimits().hashCode);
      expect(const StudyLimits(newPerDay: 5), isNot(const StudyLimits()));
    });
  });
}
