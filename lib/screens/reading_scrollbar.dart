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
    this.showProgress = false,
  }) : super(interactive: true);

  /// Whether to show how far through the text the pill has been dragged.
  ///
  /// Off by default. It answers "where am I in this?", which is a question
  /// about a long text and not about a list of settings, and it only appears
  /// while the pill is held — a figure that sat on the page permanently would
  /// be one more thing to read while trying to read something else.
  final bool showProgress;

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
  Widget build(BuildContext context) {
    final bar = super.build(context);
    if (!widget.showProgress) return bar;
    return Stack(
      textDirection: Directionality.of(context),
      children: [bar, if (_dragging) _Progress(widget.controller!)],
    );
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

/// How far through the text the pill has been dragged, beside the pill.
///
/// Tracks the position and places [ScrollProgressBubble] beside the pill.
///
/// Takes the controller rather than looking for a [Scrollable]: this is stacked
/// *beside* the bar, so the scrollable is not above it in the tree. Rebuilds on
/// the position so the figure keeps up with the drag rather than with the
/// parent's rebuilds.
class _Progress extends StatelessWidget {
  const _Progress(this.controller);

  final ScrollController controller;

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
        final fraction = (position.pixels / position.maxScrollExtent).clamp(
          0.0,
          1.0,
        );
        // Rides the pill: -1 is the top of its travel, 1 the bottom, which is
        // the same fraction the thumb itself is drawn at.
        return Align(
          alignment: Alignment(1, fraction * 2 - 1),
          child: Padding(
            // Clear of the pill and its touch target, so the finger doing the
            // dragging does not cover the number it is there to read.
            padding: const EdgeInsets.only(right: 34),
            child: ScrollProgressBubble(fraction: fraction),
          ),
        );
      },
    );
  }
}

/// How far through a text the reader has scrolled, as a percentage.
///
/// Separated from the bar so it can be shown and checked on its own: a thumb
/// drag cannot be driven under `flutter_test`, so this is where the parts that
/// can actually be wrong — the rounding and the fixed size — are pinned.
class ScrollProgressBubble extends StatelessWidget {
  const ScrollProgressBubble({super.key, required this.fraction});

  /// 0 at the top of the text, 1 at the end.
  final double fraction;

  /// Round for "30%", a little wider for "100%".
  ///
  /// A fixed circle would have to be sized for the widest figure and so look
  /// oversized for every other one; a stadium is round at the common width and
  /// simply grows the one case that needs it.
  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.primary,
        shape: const StadiumBorder(),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: _height,
          minHeight: _height,
        ),
        // The factors are load-bearing. Without them this takes the largest
        // size offered, and the caller offers the whole screen, so the bubble
        // covered the rule instead of sitting beside it.
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
              // The shape is a fixed size, so the figure inside it must not
              // grow with the reader's text size and spill out of it. This is
              // chrome telling them where they are, not text to be read.
              textScaler: TextScaler.noScaling,
            ),
          ),
        ),
      ),
    );
  }
}
