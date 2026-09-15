/// En qué modo se dio una conversación del chat: citando la bóveda, o
/// charlando libre con el modelo.
///
/// Vive en el dominio y no en la pantalla del chat —donde antes era un enum
/// privado— porque ahora también lo necesita la persistencia: el historial
/// separa las conversaciones de un modo de las del otro, y guardarlas en la
/// misma tabla sin saber a cuál pertenecen mezclaría dos historiales que
/// tienen reglas distintas.
enum ChatConversationMode {
  /// Busca en la bóveda y, si hay modelo, redacta citando sus fuentes.
  vault,

  /// El mismo modelo, sin restringirlo al contenido de la bóveda.
  free,
}
