/// Lo único que la cola de la IA recuerda fuera de la base (F27): desde
/// cuándo la IA organiza sola en este dispositivo. La primera vez que se
/// pregunta, ahora. Lo creado antes es la biblioteca que ya existía —se
/// recorre solo con el teléfono cargando (decisión C)—; lo creado después es
/// nuevo y se organiza apenas está listo.
///
/// Lo pendiente NO está acá: se deduce de la base, de las pasadas
/// (`AiOrganizeBacklog`); tampoco cómo era una nota cuando se organizó, que
/// guarda su pasada (`ai_runs.content_simhash`).
typedef AiOrganizeEpoch = Future<DateTime> Function();
