import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_filter.dart';
import 'package:sinapsis/features/timeline/presentation/providers/timeline_providers.dart';

/// Abre la línea de tiempo recortada a [scope] (F40): una rama del Atlas, un
/// documento desde su detalle.
///
/// Primero fija el filtro —en `timelineFilterProvider`, el único dueño— y
/// después va a la rama de la línea de tiempo del shell. En ese orden y no por
/// la dirección ni por el constructor de la pantalla: vive en el `IndexedStack`
/// y, si ya se había visitado, no se construye de nuevo; lo que la hace mostrar
/// lo nuevo es el filtro, que ella mira.
///
/// Es `go` y no `push`: la línea de tiempo es un destino de la barra, no una
/// pantalla que se apila encima.
void showInTimeline(BuildContext context, WidgetRef ref, TimelineScope scope) {
  ref.read(timelineFilterProvider.notifier).focusOn(scope);
  context.go(RoutePaths.timeline);
}
