/// En qué quedó cada archivo que ofrece una página (F30).
enum AttachmentDownloadStatus {
  /// Todavía no se intentó bajar.
  pending,

  /// Ya está en el «Contenido» del elemento.
  done,

  /// No entró en el tope por elemento: se ofrece «Bajar el resto».
  leftOut,

  /// No había lugar en el teléfono cuando le tocó.
  noSpace,

  /// No era un archivo —una página, algo que el servidor no dio— o no se
  /// pudo bajar ni reintentando. No se vuelve a intentar solo.
  failed,
}
