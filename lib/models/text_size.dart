import 'package:flutter/painting.dart';

/// How large the app draws its text.
///
/// [small] is what the app drew before there was a choice, and stays the
/// default, so nobody's app changes under them. [large] is meant to be enough
/// for someone who needs it rather than merely bigger than medium, which is
/// why the second step is the larger one.
///
/// A multiplier rather than a set of point sizes, so it composes with the text
/// size the platform was already asked for instead of overruling it. [over] is
/// the one place that composition is expressed.
enum TextSize {
  small('small', 1.0),
  medium('medium', 1.3),
  large('large', 1.8);

  const TextSize(this.slug, this.scale);

  /// What is written to storage. A short stable string rather than the index,
  /// since reordering or inserting a size would otherwise silently change what
  /// a device already has.
  final String slug;

  final double scale;

  /// This size applied on top of [base], rather than in place of it.
  ///
  /// The distinction is the whole point of the setting. Someone who has
  /// already set a system text size has said what they need, and an app that
  /// replaces that with its own idea of "small" takes it away from exactly the
  /// reader this exists for. Every place that scales text goes through here,
  /// so the rule is stated once — a preview that showed the sizes without it
  /// was reporting something other than what choosing them would do.
  TextScaler over(TextScaler base) => _ScaledBy(base, scale);

  /// The size [slug] names, or [small] if it names none — which is what a
  /// value written by a later build should come back as on an older one.
  static TextSize bySlug(String? slug) =>
      values.firstWhere((size) => size.slug == slug, orElse: () => small);

  /// What [scaled] was built on top of, undoing [over].
  ///
  /// For drawing a preview of a size other than the one in force. Every
  /// MediaQuery in the app already carries the current choice, so composing
  /// onto it would show each option multiplied by whatever is selected —
  /// picking "large" once would make every option enormous, including
  /// "small". This recovers the platform's own size to draw them against.
  static TextScaler platformBase(TextScaler scaled) =>
      scaled is _ScaledBy ? scaled.base : scaled;
}

/// [base], multiplied.
///
/// Equality is load-bearing rather than decoration: `MediaQuery` decides
/// whether to rebuild every text widget below it by comparing scalers, so
/// without it each build would invalidate the whole subtree.
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
