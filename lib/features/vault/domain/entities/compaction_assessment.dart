import 'package:flutter/foundation.dart';

/// Cómo devuelve SQLite al sistema de archivos lo que se borra
/// (`PRAGMA auto_vacuum`).
enum AutoVacuumMode {
  /// Las páginas que quedan libres al borrar se quedan dentro del archivo, a la
  /// espera de que las reuse algo nuevo: el archivo no achica nunca. Así están
  /// todas las bóvedas hasta la primera compactación.
  none,

  /// Cada borrado devuelve el espacio en el mismo momento. No se usa: es más
  /// lento y la app no lo pidió nunca.
  full,

  /// Las páginas libres se acumulan y se devuelven cuando se pide, de a
  /// tramos (`PRAGMA incremental_vacuum`). Es el modo en que la primera
  /// compactación deja la bóveda, y el que permite las siguientes sin
  /// reescribirla entera.
  incremental;

  /// El valor que devuelve `PRAGMA auto_vacuum`: 0, 1 o 2.
  static AutoVacuumMode fromPragma(int value) => switch (value) {
    1 => AutoVacuumMode.full,
    2 => AutoVacuumMode.incremental,
    _ => AutoVacuumMode.none,
  };
}

/// Lo que decide, con lo que se sabe de la base y del disco, si se puede
/// compactar ahora.
enum CompactionVerdict {
  /// No hay páginas libres: compactar no achicaría nada.
  nothingToReclaim,

  /// Hay algo que recuperar y el disco tiene lugar de sobra.
  ready,

  /// Hay algo que recuperar pero el disco no tiene lugar para hacerlo. Una
  /// compactación completa necesita, mientras dura, bastante más espacio libre
  /// que el que va a devolver: ver [CompactionAssessment.requiredBytes].
  notEnoughSpace,

  /// Hay algo que recuperar y no se pudo saber cuánto espacio libre hay —el
  /// sistema no lo dice—. Se puede intentar: si falta lugar, SQLite lo detecta
  /// y deja la base como estaba.
  spaceUnknown,
}

/// Cuántas páginas devuelve cada tramo de una compactación incremental.
///
/// Es lo que acota el disco y el tiempo de cada paso —y por lo tanto cada
/// cuánto se puede cancelar y se puede mostrar progreso—: con páginas de 4 KiB
/// son 8 MiB por tramo.
const kIncrementalStepPages = 2048;

/// Cuánto más de lo medido se pide de espacio para una compactación completa,
/// en porcentaje.
///
/// `VACUUM` gastó entre 1,98 y 1,99 veces el contenido útil en las mediciones
/// (ver la decisión 45 de docs/arquitectura.md); esto es holgura para que un
/// disco casi justo no se quede a medias.
const kCompactionSlackPercent = 10;

/// Lo que se le deja siempre libre al resto de la app, en bytes: sin esto, una
/// compactación que «entra justo» dejaría el teléfono sin poder guardar la
/// próxima captura.
const kCompactionSpareBytes = 16 * 1024 * 1024;

/// Qué hay para recuperar en la base y qué hace falta para recuperarlo, en el
/// momento en que se midió.
///
/// Las páginas libres son lo que el usuario ya borró —una fuente, un lote de
/// sugerencias, una migración que reconstruyó tablas— y SQLite no devolvió: el
/// archivo de la bóveda no achica solo. Esto es solo el cálculo: no toca nada
/// (compactar es otra pieza) y no tiene memoria, así que se vuelve a medir cada
/// vez que hace falta.
@immutable
class CompactionAssessment {
  const CompactionAssessment({
    required this.pageSize,
    required this.pageCount,
    required this.freePages,
    required this.autoVacuum,
    required this.freeSpaceBytes,
  });

  /// El tamaño de cada página de la base, en bytes.
  final int pageSize;

  /// Cuántas páginas tiene el archivo, libres o no.
  final int pageCount;

  /// Cuántas de esas páginas están libres (`PRAGMA freelist_count`).
  final int freePages;

  /// Cómo devuelve la base lo que se borra.
  final AutoVacuumMode autoVacuum;

  /// Cuánto espacio libre hay donde vive la base, en bytes; `null` si el
  /// sistema no lo dice.
  final int? freeSpaceBytes;

  /// Lo que ocupa el archivo de la base.
  int get fileBytes => pageCount * pageSize;

  /// Lo que se recuperaría: las páginas libres, enteras. Es un piso —al
  /// reescribir la base, SQLite además reacomoda las páginas que quedan medio
  /// llenas—, así que la compactación nunca devuelve menos que esto.
  int get reclaimableBytes => freePages * pageSize;

  /// Lo que la base tiene de verdad, sin las páginas libres.
  int get usefulBytes => fileBytes - reclaimableBytes;

  /// Si la primera compactación es la completa: reescribir la base entera (y de
  /// paso dejarla en modo incremental) en lugar de devolver tramos. Es lo que
  /// hace falta mientras [autoVacuum] no sea [AutoVacuumMode.incremental].
  bool get needsFullRewrite => autoVacuum != AutoVacuumMode.incremental;

  /// El espacio libre que hace falta para compactar.
  ///
  /// La reescritura completa arma una copia de trabajo del contenido útil y,
  /// para pisar el archivo con ella, guarda en el diario de reversión las
  /// páginas originales que reemplaza —otro tanto—: pide el doble de lo que la
  /// base tiene de verdad, no el doble del archivo, porque las páginas libres
  /// no se copian. La compactación incremental, en cambio, solo mueve un tramo
  /// por vez, y le alcanza con lo que ese tramo escriba y su diario.
  int get requiredBytes {
    if (!needsFullRewrite) return 2 * kIncrementalStepPages * pageSize;
    final work = 2 * usefulBytes;
    return work + work * kCompactionSlackPercent ~/ 100 + kCompactionSpareBytes;
  }

  /// Cuánto falta para poder compactar; 0 si no falta nada o no se sabe.
  int get missingBytes {
    final free = freeSpaceBytes;
    if (free == null || free >= requiredBytes) return 0;
    return requiredBytes - free;
  }

  CompactionVerdict get verdict {
    if (freePages == 0) return CompactionVerdict.nothingToReclaim;
    final free = freeSpaceBytes;
    if (free == null) return CompactionVerdict.spaceUnknown;
    return free >= requiredBytes
        ? CompactionVerdict.ready
        : CompactionVerdict.notEnoughSpace;
  }

  @override
  bool operator ==(Object other) =>
      other is CompactionAssessment &&
      other.pageSize == pageSize &&
      other.pageCount == pageCount &&
      other.freePages == freePages &&
      other.autoVacuum == autoVacuum &&
      other.freeSpaceBytes == freeSpaceBytes;

  @override
  int get hashCode =>
      Object.hash(pageSize, pageCount, freePages, autoVacuum, freeSpaceBytes);

  @override
  String toString() =>
      'CompactionAssessment($freePages de $pageCount páginas libres, '
      '$autoVacuum, ${freeSpaceBytes ?? '?'} bytes libres → $verdict)';
}
