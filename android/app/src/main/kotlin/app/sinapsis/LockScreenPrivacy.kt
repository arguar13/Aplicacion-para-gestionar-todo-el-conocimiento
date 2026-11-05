package app.sinapsis

import android.app.Notification

/**
 * Qué deja ver la tarjeta de lo que suena con el teléfono bloqueado (F47,
 * paso 7a-bis, decisión J precisada el 5/11): de entrada, nada de lo que
 * suena —ni el título, ni el subtítulo, ni la imagen—; con «Mostrar el título
 * en la pantalla de bloqueo» prendido en Ajustes › Privacidad, todo, como
 * antes.
 *
 * El título se puede ver sin desbloquear por **tres caminos**, y la tarjeta
 * los cierra los tres ([MediaPlaybackService]):
 * 1. **La notificación**, con «mostrar todo el contenido» del teléfono: una
 *    notificación privada se muestra entera igual. Por eso, bloqueado, la
 *    tarjeta misma pasa a decir [Face.GENERIC].
 * 2. **La notificación**, con «ocultar contenido sensible»: el sistema
 *    muestra su versión pública. Por eso va privada ([visibility]) y con una
 *    versión pública genérica: cubre también el instante antes de que el
 *    servicio se entere de que se bloqueó.
 * 3. **La sesión de medios**: desde Android 11 los controles de medios de la
 *    pantalla de bloqueo y de los ajustes rápidos se arman con sus metadatos
 *    —título, artista, imagen—, no con el texto de la notificación. Por eso,
 *    bloqueado, los metadatos también son los genéricos.
 *
 * Funciones puras, sin nada de Android salvo dos constantes, para que la
 * regla se lea entera en un lugar. La de Dart (`lockScreenTitleProvider`)
 * solo guarda la preferencia y la manda; decide esto.
 */
object LockScreenPrivacy {
    /** Lo que muestra la tarjeta: lo que suena de verdad, o algo genérico. */
    enum class Face {
        /** El título, el subtítulo y la imagen de lo que suena. */
        FULL,

        /** «Reproduciendo» y el nombre de la app, sin imagen. */
        GENERIC,
    }

    /**
     * Qué muestra la tarjeta —la notificación y los metadatos de la sesión—:
     * lo de verdad si la persona eligió verlo en la pantalla de bloqueo
     * ([showTitleOnLockScreen]) o si el teléfono no está bloqueado
     * ([locked]); si no, lo genérico.
     *
     * «Bloqueado» es la pantalla apagada —también la siempre encendida, que
     * para Android no es interactiva— o el bloqueo a la vista: al apagarse la
     * pantalla la tarjeta ya pasa a lo genérico, antes de que nadie la vea, y
     * vuelve a lo de verdad recién al desbloquear.
     */
    fun face(showTitleOnLockScreen: Boolean, locked: Boolean): Face =
        if (showTitleOnLockScreen || !locked) Face.FULL else Face.GENERIC

    /**
     * La visibilidad de la notificación en la pantalla de bloqueo: pública si
     * la persona lo eligió; si no, privada, con una versión pública genérica.
     */
    fun visibility(showTitleOnLockScreen: Boolean): Int =
        if (showTitleOnLockScreen) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_PRIVATE
}
