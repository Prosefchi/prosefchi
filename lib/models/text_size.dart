import 'package:flutter/painting.dart';

/// How large the app draws its text.
///
/// [small] is what the app drew before there was a choice, and stays the
/// default. A multiplier rather than point sizes, so it composes with the
/// platform's own text size instead of overruling it; [over] is the one place
/// that composition is expressed.
enum TextSize {
  small('small', 1.0),
  medium('medium', 1.3),
  large('large', 1.8);

  const TextSize(this.slug, this.scale);

  /// What is written to storage. A stable string rather than the index, so
  /// reordering the sizes does not change what a device already has.
  final String slug;

  final double scale;

  /// This size applied on top of [base], never in place of it: a system text
  /// size is what the reader already said they need. Every place that scales
  /// text goes through here.
  TextScaler over(TextScaler base) => _ScaledBy(base, scale);

  /// The size [slug] names, or [small] if it names none — which is what a
  /// value written by a later build should come back as on an older one.
  static TextSize bySlug(String? slug) =>
      values.firstWhere((size) => size.slug == slug, orElse: () => small);
}

/// [base], multiplied.
///
/// Equality is load-bearing: `MediaQuery` compares scalers to decide whether
/// to rebuild the text widgets below it, so without it each build would
/// invalidate the whole subtree.
class _ScaledBy extends TextScaler {
  const _ScaledBy(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  // Deprecated on TextScaler but still abstract there, so a subclass has to
  // supply it. MediaQueryData's own == and hashCode go through it.
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledBy && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
