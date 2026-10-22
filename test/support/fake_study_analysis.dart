import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';

/// El análisis para estudiar, sin modelo (F36): registra lo que se le pide
/// y deja mostrar cualquier estado.
class FakeStudyAnalysis extends StudyAnalysisNotifier {
  FakeStudyAnalysis({super.renditionId = 'r1'})
    : super(analyze: () => throw UnimplementedError('sin modelo en la prueba'));

  final starts = <({String content, bool markdown})>[];
  int stops = 0;

  @override
  Future<void> start({required String content, required bool markdown}) async {
    starts.add((content: content, markdown: markdown));
  }

  @override
  void stop() => stops++;

  StudyAnalysisState get shown => state;

  set shown(StudyAnalysisState value) => state = value;
}
