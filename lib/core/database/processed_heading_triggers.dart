/// Lo que la base hace sola para que el Índice (F46, v51) nunca muestre algo
/// viejo: los triggers que mantienen `processed_headings` al día con lo que
/// la produce, y el índice de las imágenes que todavía no tienen título.
///
/// Están en la base y no solo en quien escribe Procesado por lo mismo que los
/// de las referencias (`reference_triggers.dart`): no todo lo que escribe esas
/// tablas pasa por el repositorio —la unión de bóvedas copia filas con SQL
/// crudo; la papelera del contenido devuelve una copia del original; el
/// texto de una fuente que se vuelve a extraer reubica las anclas—, y una
/// regla que solo cumple una parte de los caminos no es una regla.
///
/// Van por `customStatement`, como los de la búsqueda, porque drift no modela
/// triggers ni índices parciales. Los crea `onCreate` y la migración a v51.
library;

/// Que las entradas de texto de un documento —sus capítulos o «Texto
/// completo»— queden **sin indexar** apenas cambia lo que las produce, en la
/// misma sentencia que lo cambia.
///
/// Lo que las produce (ver `ProcessedHeadingsIndexer`): las páginas de su
/// sección «Texto» —su texto, su orden, su lugar en el texto propio y su ancla
/// en la fuente— y la copia de su original, de donde salen los marcadores de
/// un PDF. Que un documento con texto se quede sin
/// entradas de texto es justo lo que dice «sin indexar»: quien escribió lo
/// rehace en la misma transacción (`ProcessedHeadingsIndexer.refresh`) o, si
/// no puede —la unión de bóvedas, la papelera del contenido—, lo rehace el
/// relleno enseguida (`ProcessedHeadingsBackfill`). Lo que nunca pasa es ver
/// capítulos de un texto que ya no es ese, en lugares que ya no son esos.
///
/// Las imágenes no se tocan: las mantienen [processedImageHeadingTriggers].
const processedHeadingStaleTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS processed_parts_headings_stale_ai
AFTER INSERT ON processed_parts WHEN NEW.section = 'text' BEGIN
  $_forgetNewText
END''',

  '''
CREATE TRIGGER IF NOT EXISTS processed_parts_headings_stale_ad
AFTER DELETE ON processed_parts WHEN OLD.section = 'text' BEGIN
  $_forgetOldText
END''',

  '''
CREATE TRIGGER IF NOT EXISTS processed_parts_headings_stale_au
AFTER UPDATE OF content, position, section, document_id, text_start, text_end,
  source_rendition_id, source_start, source_end ON processed_parts
WHEN OLD.section = 'text' OR NEW.section = 'text' BEGIN
  $_forgetOldText
  $_forgetNewText
END''',

  '''
CREATE TRIGGER IF NOT EXISTS processed_originals_headings_stale_ai
AFTER INSERT ON processed_originals BEGIN
  $_forgetNewText
END''',

  '''
CREATE TRIGGER IF NOT EXISTS processed_originals_headings_stale_ad
AFTER DELETE ON processed_originals BEGIN
  $_forgetOldText
END''',

  '''
CREATE TRIGGER IF NOT EXISTS processed_originals_headings_stale_au
AFTER UPDATE ON processed_originals BEGIN
  $_forgetOldText
  $_forgetNewText
END''',
];

/// Los nombres de [processedHeadingStaleTriggers].
const processedHeadingStaleTriggerNames = [
  'processed_parts_headings_stale_ai',
  'processed_parts_headings_stale_ad',
  'processed_parts_headings_stale_au',
  'processed_originals_headings_stale_ai',
  'processed_originals_headings_stale_ad',
  'processed_originals_headings_stale_au',
];

/// Suelta las entradas de texto del documento de la fila nueva o de la vieja.
/// Va por `idx_processed_headings_document`: una búsqueda por clave que, si
/// ya no hay nada —lo normal cuando se escriben de una vez las cien páginas
/// de un libro—, no cuesta nada.
const _forgetNewText =
    'DELETE FROM processed_headings '
    "WHERE document_id = NEW.document_id AND origin <> 'image';";
const _forgetOldText =
    'DELETE FROM processed_headings '
    "WHERE document_id = OLD.document_id AND origin <> 'image';";

/// Que cada imagen ya titulada —también la que la fuente no nombra, con el
/// título vacío— tenga su entrada en el Índice: al entrar, al titularla o
/// renombrarla y al cambiar de lugar en la galería. Se va con la
/// imagen por su clave foránea (`processed_headings.image_id`).
///
/// La entrada copia el título y el lugar de la imagen —para que el árbol, las
/// cuentas y la búsqueda vayan por una sola tabla—, pero el dato es el de
/// `processed_images`: estos triggers son lo único que lo copia.
const processedImageHeadingTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS processed_images_heading_ai
AFTER INSERT ON processed_images WHEN NEW.title IS NOT NULL BEGIN
  INSERT INTO processed_headings
    (document_id, origin, level, position, title, image_id)
  VALUES (NEW.document_id, 'image', 1, NEW.position, NEW.title,
          NEW.rendition_id);
END''',

  '''
CREATE TRIGGER IF NOT EXISTS processed_images_heading_au
AFTER UPDATE OF title, position ON processed_images BEGIN
  DELETE FROM processed_headings
   WHERE image_id = OLD.rendition_id AND NEW.title IS NULL;
  UPDATE processed_headings SET title = NEW.title, position = NEW.position
   WHERE image_id = NEW.rendition_id AND NEW.title IS NOT NULL
     AND (title IS NOT NEW.title OR position IS NOT NEW.position);
  INSERT INTO processed_headings
    (document_id, origin, level, position, title, image_id)
  SELECT NEW.document_id, 'image', 1, NEW.position, NEW.title,
         NEW.rendition_id
   WHERE NEW.title IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM processed_headings WHERE image_id = NEW.rendition_id);
END''',
];

/// Los nombres de [processedImageHeadingTriggers].
const processedImageHeadingTriggerNames = [
  'processed_images_heading_ai',
  'processed_images_heading_au',
];

/// Las entradas de las imágenes ya tituladas, todas de una vez, como las
/// habrían escrito [processedImageHeadingTriggers] fila por fila: para rehacer
/// el Índice entero (decisión F).
const populateProcessedImageHeadings = '''
INSERT INTO processed_headings
  (document_id, origin, level, position, title, image_id)
SELECT document_id, 'image', 1, position, title, rendition_id
  FROM processed_images
 WHERE title IS NOT NULL''';

/// Las imágenes que todavía no se titularon (decisión E): las de antes de
/// v51, hasta que el relleno del Índice les pone su título. PARCIAL a
/// propósito, como `idx_item_trashed`: tiene tantas entradas como imágenes sin
/// titular —ninguna, pasado el relleno—, y encontrarlas no recorre la galería
/// de toda la bóveda.
const createUntitledProcessedImagesIndex =
    'CREATE INDEX IF NOT EXISTS idx_processed_images_untitled '
    'ON processed_images (rendition_id) WHERE title IS NULL';
