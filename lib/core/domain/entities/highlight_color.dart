/// Los colores del resaltador a mano (F38, decisión A del plan; ampliados a
/// nueve en F39).
///
/// Son distintos del verde, el celeste y el rosa de lo estudiado (F36), para
/// no confundir «lo marqué yo» con «lo marcó la IA»: por eso el verde es un
/// lima, el azul uno más violáceo que el celeste y el rojo un coral. El
/// amarillo fuerte es solo de lo que se lee en voz alta. Un subrayado sin
/// color elegido —todos los de antes— se ve con el color de siempre.
///
/// El orden es el de la paleta en pantalla, de los cálidos a los fríos y al
/// final el gris. Se guardan **por nombre** (`textEnum`): sumar uno no toca lo
/// ya guardado, y no hace falta migrar; un nombre no se renombra ni se saca.
enum HighlightColor {
  lightYellow,
  orange,
  coral,
  sand,
  lime,
  turquoise,
  blue,
  violet,
  gray,
}
