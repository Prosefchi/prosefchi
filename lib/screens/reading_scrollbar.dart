import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A scrollbar whose track does nothing, so only the pill itself scrolls.
///
/// Material's `Scrollbar` pages the list when its *track* is tapped, and the
/// track is the whole column the thumb travels in — the full height of the
/// page, not the pill. So a touch anywhere down that edge jumps a page, and
/// with a thumb resting near the bottom of a long rule most of that edge is
/// track. Holding a phone is enough to do it by accident, which is exactly
/// what someone reading a prayer does not want.
///
/// There is no flag for this. `RawScrollbar` registers the track recogniser
/// unconditionally whenever gestures are enabled, so the handler it calls is
/// overridden to do nothing instead. The recogniser still claims the tap and
/// then ignores it; a *drag* begun on the track is not a tap, so it still
/// scrolls the list the ordinary way.
///
/// The thumb keeps the touch target Flutter gives it, which expands a thin
/// pill out to the 48dp minimum along its own length. That is deliberate: the
/// pill is 8dp wide, and a target only 8dp across would be unusable — most so
/// at the large text size, for the reader who needs it. The complaint this
/// answers is the full-height column, not the few dp either side of the pill.
///
/// Subclassing `RawScrollbar` costs the state-resolved styling that Material's
/// `Scrollbar` does behind a private state class, so that is repeated here:
/// the same `ScrollbarThemeData` still drives it, and the pill still fattens
/// and darkens under a finger.
class ReadingScrollbar extends RawScrollbar {
  const ReadingScrollbar({
    super.key,
    required ScrollController super.controller,
    required super.child,
  }) : super(interactive: true);

  @override
  RawScrollbarState<ReadingScrollbar> createState() => _ReadingScrollbarState();
}

class _ReadingScrollbarState extends RawScrollbarState<ReadingScrollbar> {
  bool _dragging = false;
  bool _hovering = false;

  Set<WidgetState> get _states => <WidgetState>{
    if (_dragging) WidgetState.dragged,
    if (_hovering) WidgetState.hovered,
  };

  /// The one reason this class exists. The base implementation pages the list
  /// towards the tap; doing nothing leaves the pill as the only thing that
  /// scrolls.
  ///
  /// Not calling super is the whole point, so the `mustCallSuper` it carries
  /// is suppressed rather than honoured. All the base does here is refresh a
  /// cached controller and dispatch the paging intent, and the thumb handlers
  /// refresh that cache themselves — there is no bookkeeping to lose.
  ///
  /// Blocking the gesture earlier is not available: the recogniser decides
  /// what it will accept from the painter's own hit test rather than from
  /// anything this class can override.
  @override
  // ignore: must_call_super
  void handleTrackTapDown(TapDownDetails details) {}

  @override
  void updateScrollbarPainter() {
    final theme = ScrollbarTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    scrollbarPainter
      ..color =
          theme.thumbColor?.resolve(_states) ??
          scheme.onSurface.withValues(alpha: 0.4)
      ..textDirection = Directionality.of(context)
      ..thickness = theme.thickness?.resolve(_states) ?? 8
      ..radius = theme.radius
      ..crossAxisMargin = theme.crossAxisMargin ?? 0
      ..mainAxisMargin = theme.mainAxisMargin ?? 0
      ..minLength = theme.minThumbLength ?? 18
      ..padding = MediaQuery.paddingOf(context)
      ..ignorePointer = !enableGestures;
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    setState(() => _dragging = true);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    setState(() => _dragging = false);
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final over = isPointerOverScrollbar(
      event.position,
      event.kind,
      forHover: true,
    );
    if (over != _hovering) setState(() => _hovering = over);
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    setState(() => _hovering = false);
  }
}
