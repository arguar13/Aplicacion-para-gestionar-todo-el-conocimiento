import 'package:html/dom.dart';

/// El ancho de un teléfono, en píxeles lógicos: el de la página web de
/// Procesado también en una pantalla ancha (F45, paso 4, decisión D).
const kMobilePageWidth = 412.0;

/// El `id` de la hoja de estilos que arma la vista móvil.
const kMobilePageStyleId = 'sinapsis-mobile';

/// Lo que dice la página de su ancho para verse como en un navegador del
/// teléfono.
const kMobileViewport = 'width=device-width, initial-scale=1';

/// Deja [document] —la copia de una página archivada que se muestra— para
/// verla como en un navegador del teléfono (F45, paso 4): con el ancho de la
/// pantalla, sin el menú lateral ni las columnas de escritorio.
///
/// La página se archiva como la sirve el sitio a un programa —la versión de
/// escritorio—, y Wikipedia declara `width=1120`: el visor la armaba con ese
/// ancho y la achicaba entera, con su menú a la izquierda, su índice y su
/// columna de herramientas. Acá:
///
/// - **el ancho de la pantalla** (`<meta name="viewport">` con
///   [kMobileViewport]), en lugar del que declara la página;
/// - **una sola columna**: fuera la navegación, los menús laterales, los
///   pies y las cajas de navegación —los de Wikipedia, por nombre, y los de
///   cualquier sitio, por su papel (`nav`, `aside`)—, y el contenido a todo
///   lo ancho;
/// - **lo que se pasaba de ancho, adentro**: las fotos y los videos se
///   achican, una tabla ancha se desplaza de costado, el cuadro de datos de
///   Wikipedia deja de flotar y ocupa el ancho.
///
/// Lo que se oculta sigue en la página, sin mostrarse: el texto que se
/// cuenta para estudiar y resaltar sobre ella es el mismo (ver
/// `ArchivedPageAlignment`), y el archivo guardado no se toca.
void makeArchivedPageMobile(Document document) {
  final html = document.documentElement;
  if (html == null) return;
  var head = document.head;
  if (head == null) {
    head = Element.tag('head');
    html.insertBefore(head, html.firstChild);
  }
  for (final meta in head.querySelectorAll('meta[name="viewport"]')) {
    meta.remove();
  }
  for (final old in document.querySelectorAll('#$kMobilePageStyleId')) {
    old.remove();
  }
  head
    ..append(
      Element.tag('meta')
        ..attributes['name'] = 'viewport'
        ..attributes['content'] = kMobileViewport,
    )
    // Al final del `<head>`: con `!important`, gana a lo de la página.
    ..append(
      Element.tag('style')
        ..attributes['id'] = kMobilePageStyleId
        ..append(Text(mobileArchivedPageCss)),
    );
}

/// Lo que se oculta: la navegación de cualquier sitio y lo de Wikipedia que
/// no es el artículo —su encabezado, sus menús laterales (Vector 2010 y
/// 2022), su índice, sus herramientas, sus pies y sus cajas de navegación—.
const _hidden = [
  'nav',
  'aside',
  '[role="navigation"]',
  '[role="complementary"]',
  '#mw-panel',
  '#mw-head',
  '#mw-head-base',
  '#mw-page-base',
  '#mw-navigation',
  '.vector-header-container',
  '.vector-sticky-header',
  '.vector-column-start',
  '.vector-column-end',
  '.vector-page-toolbar',
  '.vector-main-menu-landmark',
  '.vector-toc-landmark',
  '.mw-portlet',
  '.mw-indicators',
  '.mw-editsection',
  '.mw-jump-link',
  '#siteNotice',
  '#catlinks',
  '.mw-footer',
  '#footer',
  '.navbox',
  '.vertical-navbox',
];

/// Lo que contiene el artículo y ocupa todo el ancho, sin márgenes de
/// escritorio.
const _fullWidth = [
  'main',
  '.mw-page-container',
  '.mw-page-container-inner',
  '.mw-content-container',
  '#content',
  '.mw-body',
  '#bodyContent',
  '.vector-body',
  '.mw-body-content',
  '#mw-content-text',
  '.mw-parser-output',
];

/// Lo que flota al costado en una pantalla ancha y en el teléfono va en su
/// renglón.
const _unfloated = [
  '.infobox',
  '.sidebar',
  '.thumb',
  '.tright',
  '.tleft',
  '.floatright',
  '.floatleft',
  'figure',
];

/// La hoja de estilos de la vista móvil (ver [makeArchivedPageMobile]).
final mobileArchivedPageCss = [
  _pageRule,
  '${_hidden.join(',')}{display:none!important;}',
  '${_fullWidth.join(',')}$_fullWidthRule',
  '${_unfloated.join(',')}$_unfloatedRule',
  _mediaRule,
].join(' ');

/// El ancho de la pantalla y el margen de un teléfono.
const _pageRule =
    'html{-webkit-text-size-adjust:100%!important;'
    'text-size-adjust:100%!important;} '
    'html,body{max-width:100%!important;min-width:0!important;'
    'overflow-x:hidden!important;} '
    'body{margin:0!important;padding:0 12px!important;width:auto!important;}';

const _fullWidthRule =
    '{margin:0!important;padding:0!important;max-width:none!important;'
    'min-width:0!important;width:auto!important;float:none!important;'
    'border:0!important;display:block!important;}';

const _unfloatedRule =
    '{float:none!important;clear:both!important;width:auto!important;'
    'max-width:100%!important;box-sizing:border-box!important;'
    'margin:12px 0!important;}';

/// Lo que se pasa de ancho, adentro: las fotos se achican, una tabla ancha se
/// desplaza de costado y el código se parte.
const _mediaRule =
    'img,video,svg,canvas,iframe,embed,object{max-width:100%!important;'
    'height:auto!important;} '
    'table{display:block!important;max-width:100%!important;'
    'overflow-x:auto!important;} '
    'pre{white-space:pre-wrap!important;overflow-wrap:anywhere!important;}';
