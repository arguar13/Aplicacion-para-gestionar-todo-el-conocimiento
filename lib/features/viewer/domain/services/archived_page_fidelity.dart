import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Deja la copia de una página archivada como se vería con JavaScript
/// prendido (F39), que es como se ve la original.
///
/// Una página archivada es la que llegó del servidor, antes de que corra
/// ningún programa suyo, y la copia que se muestra no los corre. Pero muchas
/// páginas llegan en un estado «sin JavaScript» que un programa chiquito, de
/// las primeras líneas del `<head>`, cambia al instante. Lo que se veía sin
/// ese cambio no era la página: era otra, que nadie ve.
///
/// El caso medido es Wikipedia (Vector 2022), guardada el 23/10/2026: el
/// servidor entrega `<html class="client-nojs …">`, y el programa del
/// `<head>` lo cambia a `client-js` antes de pintar. Sus hojas de estilo
/// dependen de esa clase: `.client-js .mw-table-of-contents-container
/// {display:none}` esconde el índice lateral que, con `client-nojs`, queda
/// abierto —con `#vector-toc-pinned-container{max-height:200px}`, una caja
/// con barra— arriba de todo el artículo. Cambiar solo esa clase, sin correr
/// nada, deja la página igual a la original: medido, hasta el píxel.
///
/// Es seguro en MediaWiki porque `client-js` es el estado de partida de sus
/// hojas, que cuentan con que el JavaScript tarde en llegar. No se hace con
/// el `no-js` genérico: una página que esconde cosas con `.js …` para
/// mostrarlas con un programa las dejaría escondidas para siempre.
void restoreScriptState(Document document) {
  _flipClientJs(document);
  _dropNoscript(document);
}

/// `client-nojs` → `client-js`, solo si la propia página lo cambia: tiene en
/// el `<head>` un programa que arma `document.documentElement.className`
/// con `client-js`.
void _flipClientJs(Document document) {
  final classes = document.documentElement?.classes;
  if (classes == null || !classes.contains('client-nojs')) return;
  final flipped = document
      .querySelectorAll('script')
      .any(
        (script) =>
            script.text.contains('client-js') &&
            script.text.contains('documentElement.className'),
      );
  if (!flipped) return;
  classes
    ..remove('client-nojs')
    ..add('client-js');
}

/// Lo que va en un `<noscript>` no se dibuja en la página original, donde el
/// JavaScript corre: ni sus hojas de estilo del `<head>` —las de quien no
/// tiene JavaScript, que cambian la página—, ni la foto de respaldo de una
/// carga perezosa, que repetiría la que ya está al lado.
void _dropNoscript(Document document) {
  final head = document.head;
  for (final noscript in document.querySelectorAll('noscript')) {
    if (head != null && _isInside(noscript, head)) {
      noscript.remove();
    } else if (_backsUpAnImage(noscript)) {
      noscript.remove();
    }
  }
}

bool _isInside(Node node, Element ancestor) {
  for (Node? parent = node.parent; parent != null; parent = parent.parent) {
    if (parent == ancestor) return true;
  }
  return false;
}

/// Si el `<noscript>` es la foto de respaldo de una que está pegada a él.
bool _backsUpAnImage(Element noscript) {
  if (!_hasImage(noscript)) return false;
  final neighbours = [
    noscript.previousElementSibling,
    noscript.nextElementSibling,
  ];
  return neighbours.any(
    (neighbour) =>
        neighbour != null &&
        neighbour.localName != 'noscript' &&
        (neighbour.localName == 'img' ||
            neighbour.localName == 'picture' ||
            neighbour.querySelector('img, picture') != null),
  );
}

/// Si lo que hay adentro de [noscript] es una foto. Según con qué se haya
/// leído el archivo, el contenido llega como elementos o como un solo texto.
bool _hasImage(Element noscript) {
  if (noscript.querySelector('img, picture') != null) return true;
  if (noscript.nodes.length == 1 && noscript.nodes.single is Text) {
    final fragment = html_parser.parseFragment(
      (noscript.nodes.single as Text).data,
    );
    return fragment.querySelector('img, picture') != null;
  }
  return false;
}
