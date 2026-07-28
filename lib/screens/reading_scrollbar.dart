import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How the reading pill is drawn, in one place.
///
/// Lives beside the widget that consumes it rather than in the theme file, so
/// the numbers and the code reading them cannot drift apart. `main.dart` hands
/// this to `ThemeData.scrollbarTheme`; [ReadingScrollbar] falls back to it
/// where no theme is in scope, so a widget test draws the pill the app ships
/// rather than a third set of numbers.
///
/// [ScrollbarThemeData.minThumbLength] is the load-bearing one: the thumb is
/// drawn in proportion to the content, so without a floor the longest rule at
/// the largest text size tapers it to a few unusable pixels.
ScrollbarThemeData readingScrollbarTheme(ColorScheme scheme) =>
    ScrollbarThemeData(
      // Fattens under a finger, the way Cupertino's does, so the thing being
      // dragged is the thing that answers.
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged) ? 12 : 8,
      ),
      radius: const Radius.circular(12),
      minThumbLength: 56,
      mainAxisMargin: 8,
      crossAxisMargin: 4,
      // Material's default thumb is a flat grey that comes out near-white on
      // the dark theme, where it reads as a foreign object laid over the page.
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) return scheme.primary;
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.7);
        }
        return scheme.primary.withValues(alpha: 0.45);
      }),
    );

/// A scrollbar whose track does nothing, so only the pill itself scrolls.
///
/// Material's `Scrollbar` pages the list when its *track* is tapped, and the
/// track is the whole column the thumb travels in — the full height of the
/// page, not the pill. With the thumb near the bottom of a long rule most of
/// that edge is track, so holding a phone is enough to jump the page by
/// accident, which is exactly what someone reading a prayer does not want.
/// The thumb keeps its ordinary 48dp touch target; the complaint was the
/// full-height column, not the few dp either side of an 8dp pill.
///
/// This is the technique the framework itself uses: `CupertinoScrollbar`
/// overrides the same handler so that iOS does not page on a track tap. So
/// what this really does is make Android behave as iOS already did — and, as
/// a side effect, gives iOS the app's own pill, since `CupertinoScrollbar`
/// reads no `ScrollbarTheme` at all. What iOS loses is its thickness
/// animation and the haptic tick on release.
///
/// Subclassing costs the state-resolved styling that Material's `Scrollbar`
/// does behind a private state class, so that is repeated below. Only
/// [readingScrollbarTheme]'s properties are forwarded: `thumbVisibility`,
/// `trackVisibility`, `trackColor` and `trackBorderColor` are deliberately
/// not, since this bar paints no track. Setting those in the app theme would
/// do nothing here.
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

  /// `RawScrollbarState` tracks hovering privately with no accessor, and does
  /// not track dragging at all, so both are kept again here to resolve the
  /// theme's per-state thickness and colour.
  Set<WidgetState> get _states => <WidgetState>{
    if (_dragging) WidgetState.dragged,
    if (_hovering) WidgetState.hovered,
  };

  /// The one reason this class exists: the base implementation pages the rule
  /// towards the tap.
  ///
  /// Not calling super is the point, so the `mustCallSuper` is suppressed
  /// rather than honoured. All the base does is refresh a cached controller
  /// and dispatch the paging intent, and the thumb handlers refresh that cache
  /// themselves, so nothing is lost. Refusing the gesture earlier is not
  /// available: the recogniser decides what to accept from the painter's own
  /// hit test rather than from anything overridable.
  @override
  // ignore: must_call_super
  void handleTrackTapDown(TapDownDetails details) {}

  @override
  void updateScrollbarPainter() {
    final defaults = readingScrollbarTheme(Theme.of(context).colorScheme);
    final theme = ScrollbarTheme.of(context);
    scrollbarPainter
      ..color = (theme.thumbColor ?? defaults.thumbColor)!.resolve(_states)!
      ..thickness = (theme.thickness ?? defaults.thickness)!.resolve(_states)!
      ..radius = theme.radius ?? defaults.radius
      ..minLength = theme.minThumbLength ?? defaults.minThumbLength!
      ..mainAxisMargin = theme.mainAxisMargin ?? defaults.mainAxisMargin!
      ..crossAxisMargin = theme.crossAxisMargin ?? defaults.crossAxisMargin!
      ..textDirection = Directionality.of(context)
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
    // Only on the transition. handleHover fires per pointer-move sample, and
    // handleHoverExit is what clears it when the pointer leaves the bar.
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
