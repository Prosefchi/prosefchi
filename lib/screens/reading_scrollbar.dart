import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How the reading pill is drawn, in one place. `main.dart` hands this to
/// `ThemeData.scrollbarTheme`, and [ReadingScrollbar] falls back to it where no
/// theme is in scope, so a widget test draws the pill the app ships.
///
/// [ScrollbarThemeData.minThumbLength] is the load-bearing one: the thumb is
/// drawn in proportion to the content, so without a floor the longest rule at
/// the largest text size tapers it to a few unusable pixels.
ScrollbarThemeData readingScrollbarTheme(ColorScheme scheme) =>
    ScrollbarThemeData(
      // Fattens under a finger, the way Cupertino's does.
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged) ? 12 : 8,
      ),
      radius: const Radius.circular(12),
      minThumbLength: 56,
      mainAxisMargin: 8,
      crossAxisMargin: 4,
      // Material's default grey comes out near-white on the dark theme, where
      // it reads as a foreign object laid over the page.
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
/// Material's `Scrollbar` pages the list on a *track* tap, and the track is the
/// full height of the page: with the thumb near the bottom of a long rule,
/// holding the phone is enough to jump the page. `CupertinoScrollbar` overrides
/// the same handler, so this only makes Android behave as iOS already did.
///
/// Subclassing costs the state-resolved styling Material does behind a private
/// state class, so that is repeated below. Only [readingScrollbarTheme]'s
/// properties are forwarded — the track ones would do nothing here.
class ReadingScrollbar extends RawScrollbar {
  const ReadingScrollbar({
    super.key,
    required ScrollController super.controller,
    required super.child,
    this.showProgress = false,
  }) : super(interactive: true);

  /// Shown only while the pill is held: a figure sitting on the page
  /// permanently is one more thing to read while trying to read something else.
  final bool showProgress;

  @override
  RawScrollbarState<ReadingScrollbar> createState() => _ReadingScrollbarState();
}

class _ReadingScrollbarState extends RawScrollbarState<ReadingScrollbar> {
  bool _dragging = false;
  bool _hovering = false;

  /// `RawScrollbarState` tracks hovering privately and dragging not at all, so
  /// both are kept again here to resolve the theme's per-state properties.
  Set<WidgetState> get _states => <WidgetState>{
    if (_dragging) WidgetState.dragged,
    if (_hovering) WidgetState.hovered,
  };

  /// The one reason this class exists. Not calling super is the point: all the
  /// base does is refresh a cached controller, which the thumb handlers do
  /// themselves, and dispatch the paging intent.
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
  Widget build(BuildContext context) {
    final bar = super.build(context);
    if (!widget.showProgress) return bar;
    // The Stack stays, only its second child comes and goes. Guarding on
    // _dragging would swap the widget type here and remount the whole rule.
    return Stack(children: [bar, if (_dragging) _Progress(widget.controller!)]);
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

/// How far through the text the reader is, pinned beside the middle of the bar
/// rather than following the pill, which the finger is on anyway.
///
/// Takes the controller rather than looking for a [Scrollable]: this is stacked
/// beside the bar, so the scrollable is not above it in the tree.
class _Progress extends StatelessWidget {
  const _Progress(this.controller);

  final ScrollController controller;

  /// The outer edge of the pill's touch target: 4 of crossAxisMargin, half of
  /// the 12 it widens to while dragged, half of the framework's 48dp minimum.
  /// Widening the pill in [readingScrollbarTheme] without changing this puts
  /// the bubble under the finger.
  static const _inset = 34.0;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasClients) return const SizedBox.shrink();
    final position = controller.position;
    return ListenableBuilder(
      listenable: position,
      builder: (context, _) {
        if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: _inset),
            child: ScrollProgressBubble(
              fraction: (position.pixels / position.maxScrollExtent).clamp(
                0.0,
                1.0,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How far through a text the reader has scrolled, as a percentage. Separate
/// from the bar so the rounding and the fixed size can be tested without a drag.
class ScrollProgressBubble extends StatelessWidget {
  const ScrollProgressBubble({super.key, required this.fraction});

  /// 0 at the top of the text, 1 at the end.
  final double fraction;

  /// A minimum, not a size: the stadium is round at "30%" and grows for "100%".
  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.primary,
        shape: const StadiumBorder(),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _size, minHeight: _size),
        // The factors are load-bearing: without them this takes the largest
        // size offered, which is the whole screen, and covers the rule.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${(fraction.clamp(0.0, 1.0) * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
              // Chrome, not text to be read: growing it spills the shape.
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );
  }
}
