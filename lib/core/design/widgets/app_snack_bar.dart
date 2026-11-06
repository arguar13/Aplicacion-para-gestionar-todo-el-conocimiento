import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:sinapsis/core/design/widgets/snack_bar_footprint.dart';
import 'package:sinapsis/core/design/widgets/top_edge_probe.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que dura un aviso de abajo si no se dice otra cosa: lo mismo que
/// `SnackBar`.
const kSnackBarDefaultDuration = Duration(milliseconds: 4000);

/// Hasta cuántos renglones muestra el texto de un aviso de abajo (F45, paso
/// 1); lo que no entra termina en «…».
const kSnackBarMaxLines = 3;

/// El aviso de abajo de la app, el único (F45, paso 1): el texto a la
/// izquierda, hasta [kSnackBarMaxLines] renglones; uno o dos botones a la
/// derecha —«Ver», «Deshacer»—, y la ✕ siempre, también en una confirmación
/// corta como «Copiado» (decisión A), para que se pueda sacar en el acto.
///
/// Se acomoda como una tarjeta:
/// - si el texto entra en un renglón al lado de los botones y la ✕, va todo
///   en ese renglón;
/// - si no, y hay botones, el texto toma el ancho entero arriba, y abajo va
///   un renglón con los botones y la ✕ al final, pegados a la derecha y
///   centrados entre sí, como el `SnackBar` de Material 3 con un botón largo
///   pero sin su hueco: el renglón empieza donde termina el texto y el aviso
///   donde termina el renglón, porque los botones y la ✕ ya traen su aire
///   adentro, el mismo arriba y abajo de su letra (F46, paso 5d). Si los
///   botones no entran juntos al lado de la ✕, se apilan a la derecha y la ✕
///   queda al lado del último, el principal: pegada a él como en un renglón,
///   y abajo a la derecha como siempre que hay botones;
/// - si no, y no hay botones, el texto toma el ancho menos la ✕, que queda
///   arriba a la derecha, centrada con el primer renglón.
///
/// Hasta el paso 5d, la ✕ quedaba arriba a la derecha también con botones, y
/// con su caja de 48 para el dedo empujaba el renglón de los botones: un
/// texto de un renglón (de 14 a 34) dejaba los botones en 48, con un hueco
/// grande entre los dos y más aire abajo que arriba.
///
/// Con un botón, el aviso se queda hasta que lo cierren (`persist`), salvo
/// que se pida lo contrario. Mientras se ve, publica lo que ocupa abajo
/// ([SnackBarFootprint]) para que lo que flota encima de las pantallas se
/// corra arriba (decisión C).
///
/// Se muestra con [AppSnackBarMessenger.showAppSnackBar], y así lo exige el
/// censo de los avisos (`test/core/design/snack_bar_census_test.dart`).
class AppSnackBar extends SnackBar {
  AppSnackBar({
    required Widget content,
    super.key,
    SnackBarAction? action,
    SnackBarAction? secondaryAction,
    super.duration = kSnackBarDefaultDuration,
    bool? persist,
    super.behavior,
    super.shape,
    super.margin,
    super.width,
    super.backgroundColor,
    super.onVisible,
    super.dismissDirection,
  }) : super(
         content: _NoticeBody(
           message: content,
           secondaryAction: secondaryAction,
           action: action,
         ),
         // Los márgenes de adentro, la ✕ y los botones los pone el aviso: los
         // de Material dejaban el hueco. Tampoco su ✕, aunque la pida el tema:
         // serían dos.
         padding: EdgeInsets.zero,
         showCloseIcon: false,
         persist: persist ?? (action != null || secondaryAction != null),
       );
}

/// La única puerta para mostrar un aviso de abajo (F45, paso 1): recibe un
/// [AppSnackBar], no cualquier `SnackBar`, así que un aviso armado a mano no
/// compila. Fuera de este archivo, `showSnackBar` no se usa: lo vigila el
/// censo de los avisos.
extension AppSnackBarMessenger on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    AppSnackBar snackBar,
  ) => showSnackBar(snackBar);
}

/// Lo de adentro del aviso: el texto, los botones y la ✕, acomodados por
/// [_NoticeLayout], y la huella que publica mientras se ve.
class _NoticeBody extends StatefulWidget {
  const _NoticeBody({
    required this.message,
    required this.secondaryAction,
    required this.action,
  });

  final Widget message;

  /// Los botones se leen en este orden: el secundario primero —«Ver»— y el
  /// principal pegado a la ✕ —«Deshacer»—. Si hay uno solo, va pegado a la
  /// ✕, sea cual sea.
  final SnackBarAction? secondaryAction;
  final SnackBarAction? action;

  @override
  State<_NoticeBody> createState() => _NoticeBodyState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Widget>('message', message));
  }
}

class _NoticeBodyState extends State<_NoticeBody> {
  /// La animación con que el `ScaffoldMessenger` muestra y saca el aviso.
  Animation<double> _shown = kAlwaysCompleteAnimation;

  /// [_shown] con la forma con que se mueve el aviso: ver
  /// [SnackBarFootprint.presence].
  CurvedAnimation? _presence;
  bool? _still;

  SnackBarFootprints? _footprints;
  var _visible = false;
  var _viewHeight = 0.0;
  double? _top;

  /// Mientras se va, el aviso ya no recibe toques: otro botón tocado a
  /// destiempo haría algo sobre un aviso que ya se cerró.
  var _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    CurvedAnimation? retired;
    // La del `SnackBar` que lo muestra: `ScaffoldMessenger` arma uno nuevo
    // con su animación (`withAnimation`), y ese es el que está arriba.
    final shown =
        context.findAncestorWidgetOfExactType<SnackBar>()?.animation ??
        kAlwaysCompleteAnimation;
    // Con el lector de pantalla, Material muestra el aviso sin animación; con
    // «sin animaciones», lo que se corre por él tampoco se anima.
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (!identical(shown, _shown) || still != _still) {
      _shown.removeStatusListener(_onStatus);
      retired = _presence;
      _shown = shown..addStatusListener(_onStatus);
      _still = still;
      _presence = CurvedAnimation(
        parent: shown,
        // Al llegar, sube como el aviso, que crece desde abajo con esta curva
        // (la de Material 3). Al irse, el aviso se desvanece en el medio de
        // su animación y su lugar se suelta al final: lo de encima espera a
        // que se desvanezca y baja.
        curve: still ? const Threshold(0) : Curves.easeInOutQuart,
        reverseCurve: still
            ? const Threshold(0)
            : const Interval(0, 0.6, curve: Curves.easeOutCubic),
      );
      _leaving = shown.status == AnimationStatus.reverse;
    }

    final footprints = SnackBarFootprintHost.maybeOf(context);
    if (!identical(footprints, _footprints)) {
      final previous = _footprints;
      if (previous != null) _afterFrame(() => previous.withdraw(this));
      _footprints = footprints;
    }
    // Una pantalla tapada por otra o una pestaña que no es la de ahora
    // dibujan el aviso fuera de la vista: no corren nada.
    _visible = TickerMode.valuesOf(context).enabled;
    _viewHeight = MediaQuery.sizeOf(context).height;
    _publish();
    // La huella publicada sigue con la animación de antes hasta que se
    // publique la nueva, al final del cuadro: recién después se suelta.
    if (retired != null) _afterFrame(retired.dispose);
  }

  void _onStatus(AnimationStatus status) {
    final leaving = status == AnimationStatus.reverse;
    if (leaving != _leaving && mounted) setState(() => _leaving = leaving);
  }

  void _measured(double top) {
    _top = top;
    _publish();
  }

  /// Al final del cuadro, no en medio del dibujo ni de la construcción: lo
  /// que escucha las huellas se reconstruye.
  void _publish() => _afterFrame(() {
    if (!mounted) return;
    final footprints = _footprints;
    final top = _top;
    final presence = _presence;
    if (footprints == null) return;
    if (_visible && top != null && presence != null) {
      footprints.report(
        this,
        SnackBarFootprint(
          height: math.max(0, _viewHeight - top),
          presence: presence,
        ),
      );
    } else {
      footprints.withdraw(this);
    }
  });

  /// Al final de este cuadro, o del que sigue si este ya terminó: la sonda
  /// también mide al final del cuadro.
  void _afterFrame(VoidCallback callback) => SchedulerBinding.instance
    ..addPostFrameCallback((_) => callback())
    ..ensureVisualUpdate();

  @override
  void dispose() {
    _shown.removeStatusListener(_onStatus);
    final footprints = _footprints;
    final presence = _presence;
    // La huella se retira al final del cuadro, y recién entonces se suelta su
    // animación: hasta ahí, lo que se corrió la sigue leyendo.
    _afterFrame(() {
      footprints?.withdraw(this);
      presence?.dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      ignoring: _leaving,
      child: TopEdgeProbe(
        onTop: _measured,
        child: _NoticeLayout(
          textDirection: Directionality.of(context),
          message: DefaultTextStyle.merge(
            maxLines: kSnackBarMaxLines,
            overflow: TextOverflow.ellipsis,
            child: widget.message,
          ),
          secondaryAction: widget.secondaryAction,
          action: widget.action,
          // La ✕ de Material, con su color sobre el aviso en cada tema; el
          // nombre dice qué cierra, para no confundirse con la ✕ de una hoja
          // que esté abierta debajo.
          close: IconButton(
            key: StandardComponentType.closeButton.key,
            icon: const Icon(Icons.close),
            iconSize: 24,
            color:
                SnackBarTheme.of(context).closeIconColor ??
                theme.colorScheme.onInverseSurface,
            tooltip:
                AppLocalizations.of(context)?.f45S1CloseNotice ??
                MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss),
          ),
        ),
      ),
    );
  }
}

enum _NoticeSlot { message, secondaryAction, action, close }

/// Acomoda el texto, los botones y la ✕ del aviso: en un renglón si el texto
/// entra entero al lado de los botones y la ✕; si no, como una tarjeta, con
/// el texto arriba y, debajo, los botones y la ✕ en un renglón a la derecha;
/// sin botones, con la ✕ arriba a la derecha.
class _NoticeLayout
    extends SlottedMultiChildRenderObjectWidget<_NoticeSlot, RenderBox> {
  const _NoticeLayout({
    required this.textDirection,
    required this.message,
    required this.secondaryAction,
    required this.action,
    required this.close,
  });

  final TextDirection textDirection;
  final Widget message;
  final Widget? secondaryAction;
  final Widget? action;
  final Widget close;

  @override
  Iterable<_NoticeSlot> get slots => _NoticeSlot.values;

  @override
  Widget? childForSlot(_NoticeSlot slot) => switch (slot) {
    _NoticeSlot.message => message,
    _NoticeSlot.secondaryAction => secondaryAction,
    _NoticeSlot.action => action,
    _NoticeSlot.close => close,
  };

  @override
  _RenderNoticeLayout createRenderObject(BuildContext context) =>
      _RenderNoticeLayout(textDirection: textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNoticeLayout renderObject,
  ) {
    renderObject.textDirection = textDirection;
  }
}

/// Dónde va cada parte del aviso, y su tamaño. `buttons` va en el orden de
/// `_RenderNoticeLayout._buttons`; `messageWidth` es el ancho que se le dio al
/// texto, para medir su línea base en seco.
typedef _NoticeGeometry = ({
  Size size,
  Offset message,
  double messageWidth,
  List<Offset> buttons,
  Offset close,
});

class _RenderNoticeLayout extends RenderBox
    with SlottedContainerRenderObjectMixin<_NoticeSlot, RenderBox> {
  _RenderNoticeLayout({required TextDirection textDirection})
    : _textDirection = textDirection;

  /// Del borde al texto, como el `SnackBar` flotante de Material; en una
  /// tarjeta, también del texto al otro borde.
  static const _start = 16.0;

  /// Arriba y abajo del texto: con un renglón, el aviso mide 48, como el de
  /// Material.
  static const _textVertical = 14.0;

  /// Del borde a la ✕ y a los botones: cada uno ya trae su aire adentro.
  static const _end = 4.0;

  /// Entre el texto y los botones o la ✕, en un renglón.
  static const _gap = 8.0;

  /// Entre un botón y el otro, uno al lado del otro: cada uno ya trae su
  /// aire adentro. Apilados no llevan nada: sus cajas de 48 ya los separan.
  static const _buttonSpacing = 4.0;

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _message => childForSlot(_NoticeSlot.message)!;
  RenderBox get _close => childForSlot(_NoticeSlot.close)!;

  /// Los botones, en el orden en que se leen: el último va pegado a la ✕.
  List<RenderBox> get _buttons => [
    ?childForSlot(_NoticeSlot.secondaryAction),
    ?childForSlot(_NoticeSlot.action),
  ];

  /// En el orden en que se dibujan y se leen. Mientras se arma, puede faltar
  /// alguno.
  @override
  Iterable<RenderBox> get children => [
    for (final slot in _NoticeSlot.values) ?childForSlot(slot),
  ];

  /// Lo que ocupan los botones uno al lado del otro.
  static double _rowWidth(Iterable<double> widths) => widths.isEmpty
      ? 0
      : widths.reduce((a, b) => a + b) + _buttonSpacing * (widths.length - 1);

  /// Lo que pide todo en un renglón, con el texto entero.
  double _inlineWidth() =>
      _start +
      _message.getMaxIntrinsicWidth(double.infinity) +
      _gap +
      _rowWidth([
        for (final button in _buttons)
          button.getMaxIntrinsicWidth(double.infinity),
      ]) +
      _close.getMaxIntrinsicWidth(double.infinity) +
      _end;

  /// Dónde empieza cada botón si van uno al lado del otro y el último termina
  /// en [end].
  static List<double> _rowStarts(double end, List<Size> sizes) {
    final starts = List<double>.filled(sizes.length, 0);
    var x = end;
    for (var i = sizes.length - 1; i >= 0; i--) {
      starts[i] = x - sizes[i].width;
      x = starts[i] - _buttonSpacing;
    }
    return starts;
  }

  _NoticeGeometry _compute(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final message = _message;
    final buttons = _buttons;
    final closeSize = layoutChild(_close, const BoxConstraints());
    final inlineWidth = _inlineWidth();
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : inlineWidth;
    final closeX = width - _end - closeSize.width;

    if (inlineWidth <= width) {
      // En un solo renglón: el texto se lleva lo que sobra, y los botones y
      // la ✕ quedan pegados a la derecha, centrados con él.
      final buttonSizes = [
        for (final button in buttons)
          layoutChild(
            button,
            BoxConstraints(
              maxWidth: button.getMaxIntrinsicWidth(double.infinity),
            ),
          ),
      ];
      final buttonXs = _rowStarts(closeX, buttonSizes);
      final messageWidth = math.max<double>(
        0,
        (buttonXs.firstOrNull ?? closeX) - _gap - _start,
      );
      final messageSize = layoutChild(
        message,
        BoxConstraints(maxWidth: messageWidth),
      );
      final height = constraints.constrainHeight(
        [
          messageSize.height + 2 * _textVertical,
          closeSize.height,
          for (final size in buttonSizes) size.height,
        ].reduce(math.max),
      );
      double centered(Size size) => (height - size.height) / 2;
      return (
        size: Size(width, height),
        message: Offset(_start, centered(messageSize)),
        messageWidth: messageWidth,
        buttons: [
          for (var i = 0; i < buttons.length; i++)
            Offset(buttonXs[i], centered(buttonSizes[i])),
        ],
        close: Offset(closeX, centered(closeSize)),
      );
    }

    if (buttons.isEmpty) {
      // Sin botones, el texto toma el ancho menos la ✕, que queda arriba a la
      // derecha, centrada con el primer renglón: abajo no hay renglón que la
      // lleve.
      final messageWidth = math.max<double>(0, closeX - _start);
      final messageSize = layoutChild(
        message,
        BoxConstraints(maxWidth: messageWidth),
      );
      final firstLine = math.min(
        messageSize.height,
        message.getMinIntrinsicHeight(
          message.getMaxIntrinsicWidth(double.infinity),
        ),
      );
      final closeY = math.max<double>(
        0,
        _textVertical + firstLine / 2 - closeSize.height / 2,
      );
      return (
        size: constraints.constrain(
          Size(
            width,
            math.max(
              _textVertical + messageSize.height + _textVertical,
              closeY + closeSize.height,
            ),
          ),
        ),
        message: const Offset(_start, _textVertical),
        messageWidth: messageWidth,
        buttons: const [],
        close: Offset(closeX, closeY),
      );
    }

    // Como una tarjeta: el texto toma el ancho entero, y debajo, sin aire de
    // más —los botones y la ✕ ya lo traen adentro, el mismo arriba y abajo de
    // su letra—, los botones y la ✕ en un renglón, pegados a la derecha.
    final messageWidth = math.max<double>(0, width - 2 * _start);
    final messageSize = layoutChild(
      message,
      BoxConstraints(maxWidth: messageWidth),
    );
    final rowTop = _textVertical + messageSize.height;
    final room = math.max<double>(0, closeX - _start);
    final buttonSizes = [
      for (final button in buttons)
        layoutChild(button, BoxConstraints(maxWidth: room)),
    ];

    if (_rowWidth([for (final size in buttonSizes) size.width]) <= room) {
      // Todos en el renglón, centrados entre sí.
      final rowHeight = [
        closeSize.height,
        for (final size in buttonSizes) size.height,
      ].reduce(math.max);
      final buttonXs = _rowStarts(closeX, buttonSizes);
      double centered(Size size) => rowTop + (rowHeight - size.height) / 2;
      return (
        size: constraints.constrain(Size(width, rowTop + rowHeight)),
        message: const Offset(_start, _textVertical),
        messageWidth: messageWidth,
        buttons: [
          for (var i = 0; i < buttons.length; i++)
            Offset(buttonXs[i], centered(buttonSizes[i])),
        ],
        close: Offset(closeX, centered(closeSize)),
      );
    }

    // Los botones no entran juntos al lado de la ✕: se apilan, en el orden en
    // que se leen y pegados a la ✕, que queda al lado del último —el
    // principal, como en un renglón—, centrada con él. Si la ✕ fuera más alta
    // que ese botón, no sube más allá del texto.
    final buttonOffsets = <Offset>[];
    var y = rowTop;
    for (final size in buttonSizes) {
      buttonOffsets.add(Offset(closeX - size.width, y));
      y += size.height;
    }
    final last = buttonSizes.last;
    final closeY = math.max(rowTop, y - last.height / 2 - closeSize.height / 2);
    return (
      size: constraints.constrain(
        Size(width, math.max(y, closeY + closeSize.height)),
      ),
      message: const Offset(_start, _textVertical),
      messageWidth: messageWidth,
      buttons: buttonOffsets,
      close: Offset(closeX, closeY),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final buttons = _buttons;
    final message = _message.getMinIntrinsicWidth(double.infinity);
    final close = _close.getMinIntrinsicWidth(double.infinity);
    // Sin botones, el texto va al lado de la ✕; con botones, toma el ancho
    // entero, y debajo cada botón, apilado, va al lado de la ✕.
    if (buttons.isEmpty) return _start + message + close + _end;
    return math.max(
      _start + message + _start,
      _start +
          [
            for (final button in buttons)
              button.getMinIntrinsicWidth(double.infinity),
          ].reduce(math.max) +
          close +
          _end,
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) => _inlineWidth();

  @override
  double computeMinIntrinsicHeight(double width) => _compute(
    BoxConstraints.tightFor(width: width),
    ChildLayoutHelper.dryLayoutChild,
  ).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _compute(constraints, ChildLayoutHelper.dryLayoutChild).size;

  /// La del texto, como la de verdad: medida en seco con el ancho que le toca.
  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final geometry = _compute(constraints, ChildLayoutHelper.dryLayoutChild);
    final distance = _message.getDryBaseline(
      BoxConstraints(maxWidth: geometry.messageWidth),
      baseline,
    );
    if (distance == null) return null;
    return distance + geometry.message.dy;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final message = _message;
    final distance = message.getDistanceToActualBaseline(baseline);
    if (distance == null) return null;
    return distance + (message.parentData! as BoxParentData).offset.dy;
  }

  @override
  void performLayout() {
    final geometry = _compute(constraints, ChildLayoutHelper.layoutChild);
    size = geometry.size;
    _place(_message, geometry.message);
    final buttons = _buttons;
    for (var i = 0; i < buttons.length; i++) {
      _place(buttons[i], geometry.buttons[i]);
    }
    _place(_close, geometry.close);
  }

  /// Pone a [child] en [offset], medido de izquierda a derecha; en un idioma
  /// que se escribe al revés, lo da vuelta.
  void _place(RenderBox child, Offset offset) {
    (child.parentData! as BoxParentData).offset = switch (textDirection) {
      TextDirection.ltr => offset,
      TextDirection.rtl => Offset(
        size.width - offset.dx - child.size.width,
        offset.dy,
      ),
    };
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        (child.parentData! as BoxParentData).offset + offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final hit = result.addWithPaintOffset(
        offset: (child.parentData! as BoxParentData).offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
