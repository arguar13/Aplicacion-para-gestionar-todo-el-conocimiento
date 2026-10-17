import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_text_budget.dart';

/// Cuánto texto lee por pedido el modelo elegido (F32).
void main() {
  test('con la ventana de Gemma, lo medido: 3000 caracteres y 4 tarjetas', () {
    expect(textBudgetFor(2048), kSmallWindowTextBudget);
    expect(
      kSmallWindowTextBudget,
      const ModelTextBudget(partChars: 3000, maxDraftsPerCall: 4),
    );
  });

  test('una ventana menor que la grande se reparte como Gemma', () {
    expect(textBudgetFor(kLargeWindowTokens - 1), kSmallWindowTextBudget);
  });

  test('desde la ventana grande, un cuarto de la ventana para la parte', () {
    expect(
      textBudgetFor(kLargeWindowTokens),
      const ModelTextBudget(
        partChars: 14000,
        maxDraftsPerCall: kLargeWindowDraftsPerCall,
      ),
    );
  });

  test('con la ventana de Gemini, un capítulo, no el libro entero', () {
    expect(
      textBudgetFor(1048576),
      const ModelTextBudget(
        partChars: kMaxPartChars,
        maxDraftsPerCall: kLargeWindowDraftsPerCall,
      ),
    );
  });
}
