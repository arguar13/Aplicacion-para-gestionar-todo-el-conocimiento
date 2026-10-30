import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/features/map/domain/entities/map_search.dart';

/// La ventana corta de lo nuevo: «Lo nuevo · esta semana».
const kRecentWeekDays = 7;

/// La ventana larga de lo nuevo, y la de los cambios de las cifras («+3»).
const kRecentMonthDays = 30;

/// Cuántos documentos y cuántos vínculos nombra cada ventana, como mucho: los
/// más nuevos. Los demás se cuentan.
const kRecentListLength = 8;

/// Una cifra del Resumen y cuánto valía al empezar la ventana.
class FigureChange {
  const FigureChange({required this.now, required this.before});

  const FigureChange.none() : now = 0, before = 0;

  final int now;
  final int before;

  /// Cuánto cambió: positivo si creció. Puede ser negativo —dos comunidades
  /// que un vínculo nuevo juntó en una—.
  int get delta => now - before;
}

/// Las cuatro cifras grandes del Resumen con su cambio de los últimos
/// [kRecentMonthDays] días (F44).
///
/// «Antes» se cuenta con lo que la base todavía tiene, por sus fechas: lo que
/// se borró después ya no está y no se cuenta. Es lo que había hace un mes de
/// lo que sigue vivo.
class MapFigures {
  const MapFigures({
    required this.documents,
    required this.topics,
    required this.communities,
    required this.links,
  });

  const MapFigures.none()
    : documents = const FigureChange.none(),
      topics = const FigureChange.none(),
      communities = const FigureChange.none(),
      links = const FigureChange.none();

  /// Los documentos que pasan el filtro, con tema o sin él.
  final FigureChange documents;

  /// Los temas —o los valores de lo que se mira—, tengan o no documentos.
  final FigureChange topics;

  /// Las comunidades con uniones: los temas aislados no cuentan.
  final FigureChange communities;

  /// Los vínculos entre dos documentos del mapa.
  final FigureChange links;
}

/// Un vínculo nuevo, con sus dos documentos en su lugar del mapa.
class RecentLink {
  const RecentLink({
    required this.from,
    required this.to,
    required this.kind,
    required this.at,
  });

  final MapSearchEntry from;
  final MapSearchEntry to;
  final RelationKind kind;
  final DateTime at;
}

/// Lo nuevo de los últimos [days] días: lo procesado y lo vinculado.
class RecentWindow {
  const RecentWindow({
    required this.days,
    required this.processedCount,
    required this.processed,
    required this.linkedCount,
    required this.linked,
  });

  const RecentWindow.none(this.days)
    : processedCount = 0,
      processed = const [],
      linkedCount = 0,
      linked = const [];

  final int days;

  /// Cuántos documentos se procesaron en la ventana.
  final int processedCount;

  /// Los más nuevos de ellos, como mucho [kRecentListLength], con su lugar en
  /// el mapa para verlos con un toque.
  final List<MapSearchEntry> processed;

  /// Cuántos vínculos se hicieron en la ventana.
  final int linkedCount;

  /// Los más nuevos de ellos, como mucho [kRecentListLength].
  final List<RecentLink> linked;

  bool get isEmpty => processedCount == 0 && linkedCount == 0;
}

/// Lo nuevo del mapa (F44): la semana, el mes y cuánto cambiaron las cifras.
class MapRecent {
  const MapRecent({
    required this.at,
    required this.week,
    required this.month,
    required this.figures,
  });

  const MapRecent.none()
    : at = null,
      week = const RecentWindow.none(kRecentWeekDays),
      month = const RecentWindow.none(kRecentMonthDays),
      figures = const MapFigures.none();

  /// El «ahora» contra el que se midió, o `null` si no se supo: entonces nada
  /// es nuevo.
  final DateTime? at;

  /// Los últimos [kRecentWeekDays] días.
  final RecentWindow week;

  /// Los últimos [kRecentMonthDays] días.
  final RecentWindow month;

  /// Las cifras y su cambio en los últimos [kRecentMonthDays] días.
  final MapFigures figures;
}
