import 'package:sinapsis/core/domain/entities/ai_certainty.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/ai_organize/domain/services/ai_organize_step.dart';
import 'package:sinapsis/features/ai_organize/domain/services/space_chooser.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/organize/domain/repositories/organize_repository.dart';

/// Cuánto del elemento ve el modelo para elegir su tema: el título y el
/// comienzo bastan para decir de qué trata.
const kSpaceExcerptChars = 600;

/// El tema de la biblioteca (el espacio) de un elemento nuevo, elegido por la
/// IA (F27) entre los que la persona ya armó. Nunca crea uno.
///
/// Solo si el elemento todavía no tiene: lo que la persona eligió no se toca.
/// Y solo con certeza alta: un elemento en la carpeta equivocada se pierde de
/// vista, y no hay dónde dejar un tema «para revisar» —las sugerencias no
/// tienen esa forma—, así que lo dudoso no se aplica.
///
/// Lo que no hace: quedar en la pasada. `ai_runs` cuenta vínculos, tarjetas y
/// propiedades; el espacio es una columna del elemento, sin origen ni
/// pasada, y registrarlo pide cambiar el esquema (v35). Por eso deshacer la
/// pasada no lo saca; se cambia a mano, con un toque, como siempre.
class AutoSpaceStep implements AiOrganizeStep {
  const AutoSpaceStep({
    required SpaceChooser chooser,
    required OrganizeRepository organize,
    required LibraryRepository library,
  }) : _chooser = chooser,
       _organize = organize,
       _library = library;

  final SpaceChooser _chooser;
  final OrganizeRepository _organize;
  final LibraryRepository _library;

  @override
  AiOrganizeToggle get toggle => AiOrganizeToggle.space;

  @override
  Future<AiStepReport> organize(
    KnowledgeItem item, {
    required String runId,
  }) async {
    if (item.spaceId != null) return AiStepReport.nothing;
    final spaces = await _organize.watchAllSpaces().first;
    if (spaces.isEmpty) return AiStepReport.nothing;

    final text = item.searchableText.trim();
    final choice = await _chooser(
      itemTitle: item.title,
      excerpt: text.length > kSpaceExcerptChars
          ? '${text.substring(0, kSpaceExcerptChars)}…'
          : text,
      spaces: [for (final space in spaces) space.name],
    );
    if (choice == null || choice.certainty != AiCertainty.high) {
      return AiStepReport.nothing;
    }

    // El modelo tarda: la persona pudo elegirle un tema mientras tanto.
    final current = (await _library.findById(
      item.id,
    )).orThrowStep('releer el elemento');
    if (current == null || current.spaceId != null) {
      return AiStepReport.nothing;
    }
    (await _library.assignSpace(
      itemId: item.id,
      spaceId: spaces[choice.index].id,
    )).orThrowStep('ponerle el tema');
    return const AiStepReport(applied: 1);
  }
}
